#!/usr/bin/env bash
#
# install.sh — Non-interactive dotfiles installer for Linux (Datadog workspaces)
#
# Usage: bash install.sh
#
# Installs shell tools via apt-get and direct binary downloads,
# then stows dotfiles into $HOME. Fully non-interactive and idempotent.
#

set -euo pipefail

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

info() { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  ARCH_DEB="amd64"; ARCH_GO="amd64"; ARCH_ALT="x86_64" ;;
  aarch64) ARCH_DEB="arm64"; ARCH_GO="arm64"; ARCH_ALT="aarch64" ;;
  arm64)   ARCH_DEB="arm64"; ARCH_GO="arm64"; ARCH_ALT="aarch64" ;;
  *)       error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Use sudo if available and not root
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

# --------------------------------------------------------------------------
# 1. apt-get packages
# --------------------------------------------------------------------------

install_apt_packages() {
  info "Updating apt package lists..."
  $SUDO apt-get update -qq

  local packages=(
    stow
    git
    git-lfs
    bat
    ripgrep
    jq
    fzf
    fd-find
    shellcheck
    direnv
    zsh
    fish
    bash-completion
    luarocks
    zsh-autosuggestions
    zsh-syntax-highlighting
    curl
    unzip
    tar
    gzip
  )

  info "Installing apt packages: ${packages[*]}"
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "${packages[@]}"
}

# --------------------------------------------------------------------------
# 2. Direct binary installs (GitHub releases)
# --------------------------------------------------------------------------

# Helper: download a file and make it executable
install_binary() {
  local name="$1"
  local url="$2"
  local dest="$3"

  if [ -f "$dest" ]; then
    info "$name already installed at $dest, skipping download"
    return 0
  fi

  info "Installing $name from $url"
  if ! curl -fsSL "$url" -o "$dest"; then
    error "Failed to download $name from $url"
    return 1
  fi
  chmod +x "$dest"
}

# Helper: download a tarball, extract a binary, clean up
install_from_tarball() {
  local name="$1"
  local url="$2"
  local binary_name="$3"
  local dest="$4"

  if [ -f "$dest" ]; then
    info "$name already installed at $dest, skipping download"
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  info "Installing $name from $url"
  if ! curl -fsSL "$url" -o "$tmpdir/archive.tar.gz"; then
    error "Failed to download $name from $url"
    rm -rf "$tmpdir"
    return 1
  fi
  tar -xzf "$tmpdir/archive.tar.gz" -C "$tmpdir"
  # Find the binary — it may be at top level or in a subdirectory
  local found
  found="$(find "$tmpdir" -name "$binary_name" -type f | head -1)"
  if [ -z "$found" ]; then
    error "Could not find $binary_name in $name archive"
    rm -rf "$tmpdir"
    return 1
  fi
  mv "$found" "$dest"
  chmod +x "$dest"
  rm -rf "$tmpdir"
}

install_oh_my_posh() {
  if [ -f "$BIN_DIR/oh-my-posh" ]; then
    info "oh-my-posh already installed, skipping"
    return 0
  fi
  info "Installing oh-my-posh..."
  curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$BIN_DIR"
}

install_yq() {
  install_binary "yq" \
    "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH_GO}" \
    "$BIN_DIR/yq"
}

install_lazygit() {
  if [ -f "$BIN_DIR/lazygit" ]; then
    info "lazygit already installed, skipping"
    return 0
  fi
  local version
  version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  install_from_tarball "lazygit" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${ARCH_ALT}.tar.gz" \
    "lazygit" \
    "$BIN_DIR/lazygit"
}

install_neovim() {
  if [ -f "$BIN_DIR/nvim" ]; then
    info "neovim already installed, skipping"
    return 0
  fi
  info "Installing neovim..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH_ALT}.tar.gz" -o "$tmpdir/nvim.tar.gz"
  tar -xzf "$tmpdir/nvim.tar.gz" -C "$tmpdir"
  # nvim tarball extracts to nvim-linux-x86_64/ or similar
  local nvim_dir
  nvim_dir="$(find "$tmpdir" -maxdepth 1 -type d -name 'nvim-*' | head -1)"
  if [ -z "$nvim_dir" ]; then
    error "Could not find neovim directory in archive"
    rm -rf "$tmpdir"
    return 1
  fi
  # Copy the entire neovim installation to ~/.local/
  cp -r "$nvim_dir"/* "$HOME/.local/"
  rm -rf "$tmpdir"
}

install_ast_grep() {
  if [ -f "$BIN_DIR/ast-grep" ]; then
    info "ast-grep already installed, skipping"
    return 0
  fi
  info "Installing ast-grep..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  local arch_sg
  if [ "$ARCH_ALT" = "x86_64" ]; then
    arch_sg="x86_64"
  else
    arch_sg="aarch64"
  fi
  curl -fsSL "https://github.com/ast-grep/ast-grep/releases/latest/download/app-${arch_sg}-unknown-linux-gnu.zip" -o "$tmpdir/ast-grep.zip"
  unzip -q "$tmpdir/ast-grep.zip" -d "$tmpdir"
  local found
  found="$(find "$tmpdir" -name 'sg' -o -name 'ast-grep' | head -1)"
  if [ -n "$found" ]; then
    mv "$found" "$BIN_DIR/ast-grep"
    chmod +x "$BIN_DIR/ast-grep"
  else
    warn "Could not find ast-grep binary in archive, skipping"
  fi
  rm -rf "$tmpdir"
}

install_tree_sitter_cli() {
  if [ -f "$BIN_DIR/tree-sitter" ]; then
    info "tree-sitter-cli already installed, skipping"
    return 0
  fi
  local arch_ts
  if [ "$ARCH_ALT" = "x86_64" ]; then
    arch_ts="linux-x64"
  else
    arch_ts="linux-arm64"
  fi
  info "Installing tree-sitter-cli..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-${arch_ts}.gz" -o "$tmpdir/tree-sitter.gz"
  gunzip "$tmpdir/tree-sitter.gz"
  mv "$tmpdir/tree-sitter" "$BIN_DIR/tree-sitter"
  chmod +x "$BIN_DIR/tree-sitter"
  rm -rf "$tmpdir"
}

install_binaries() {
  install_oh_my_posh
  install_yq
  install_lazygit
  install_neovim
  install_ast_grep
  install_tree_sitter_cli
}

# --------------------------------------------------------------------------
# 3. zsh-history-substring-search (not in apt, install from git)
# --------------------------------------------------------------------------

install_zsh_history_substring_search() {
  local dest="/usr/share/zsh-history-substring-search"
  if [ -d "$dest" ]; then
    info "zsh-history-substring-search already installed, skipping"
    return 0
  fi
  info "Installing zsh-history-substring-search..."
  $SUDO mkdir -p "$dest"
  if ! curl -fsSL "https://raw.githubusercontent.com/zsh-users/zsh-history-substring-search/master/zsh-history-substring-search.zsh" \
    | $SUDO tee "$dest/zsh-history-substring-search.zsh" >/dev/null; then
    error "Failed to download zsh-history-substring-search"
    return 1
  fi
}

# --------------------------------------------------------------------------
# 4. Git setup (non-interactive)
# --------------------------------------------------------------------------

setup_git() {
  if [ -f "$HOME/.gitconfig.extras" ]; then
    info "Git extras already configured, skipping"
    return 0
  fi

  local name="${GIT_AUTHOR_NAME:-$(git config user.name 2>/dev/null || echo '')}"
  local email="${GIT_AUTHOR_EMAIL:-$(git config user.email 2>/dev/null || echo '')}"

  if [ -n "$name" ] && [ -n "$email" ]; then
    info "Configuring git user: $name <$email>"
    cat > "$HOME/.gitconfig.extras" <<-EOF
	[user]
	    name = "$name"
	    email = "$email"
	EOF
  else
    info "Git user not configured (set GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL to configure)"
    touch "$HOME/.gitconfig.extras"
  fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

main() {
  info "Starting dotfiles installation for Linux..."
  info "Architecture: $ARCH ($ARCH_DEB)"

  if [ "$(uname -s)" != "Linux" ]; then
    error "This script is intended for Linux systems only."
    error "On macOS, use: bash bootstrap.sh"
    exit 1
  fi

  install_apt_packages
  install_binaries
  install_zsh_history_substring_search
  install_dotfiles bash common-sh fish git oh-my-posh vim zsh
  setup_git
  setup_vim
  setup_fonts

  # Set fish as the default shell
  local fish_bin
  fish_bin="$(which fish 2>/dev/null)"
  if [ -n "$fish_bin" ]; then
    if [ "$SHELL" != "$fish_bin" ]; then
      if ! grep -qxF "$fish_bin" /etc/shells; then
        info "Adding $fish_bin to /etc/shells..."
        echo "$fish_bin" | $SUDO tee -a /etc/shells >/dev/null
      fi
      info "Setting default shell to fish..."
      $SUDO chsh -s "$fish_bin" "$(whoami)"
    else
      info "fish is already the default shell"
    fi
  else
    warn "fish not found, skipping default shell change"
  fi

  info "Installation complete!"
  info "Start a new shell session to apply changes: exec \$SHELL -l"
}

main "$@"
