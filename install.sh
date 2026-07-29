#!/usr/bin/env bash
#
# install.sh — Non-interactive dotfiles installer for Linux (Datadog workspaces)
#
# Usage:
#   bash install.sh             # foreground setup + deferred worker launcher
#   bash install.sh --deferred  # internal background worker
#
# The foreground path stays below the Workspaces dotfiles RPC deadline and
# completes platform-sensitive Git setup before returning. Slow, idempotent
# tooling setup runs in a detached tmux session.
#

set -euo pipefail

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

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
DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.local/state/dotfiles}"
DOTFILES_LOG_FILE="$DOTFILES_STATE_DIR/install.log"
DOTFILES_STATUS_FILE="$DOTFILES_STATE_DIR/install.status"
DOTFILES_LOCK_FILE="$DOTFILES_STATE_DIR/install.lock"
DOTFILES_TMUX_SESSION_PREFIX="${DOTFILES_TMUX_SESSION_PREFIX:-dotfiles-install}"
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
  local version arch_lg
  version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  if [ "$ARCH_ALT" = "x86_64" ]; then
    arch_lg="x86_64"
  else
    arch_lg="arm64"
  fi
  install_from_tarball "lazygit" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${arch_lg}.tar.gz" \
    "lazygit" \
    "$BIN_DIR/lazygit"
}

install_neovim() {
  if [ -f "$BIN_DIR/nvim" ]; then
    info "neovim already installed, skipping"
    return 0
  fi
  info "Installing neovim..."
  local tmpdir arch_nv
  tmpdir="$(mktemp -d)"
  if [ "$ARCH_ALT" = "x86_64" ]; then
    arch_nv="x86_64"
  else
    arch_nv="arm64"
  fi
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch_nv}.tar.gz" -o "$tmpdir/nvim.tar.gz"
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

install_rust() {
  if command -v cargo &>/dev/null; then
    info "Rust toolchain already installed, skipping"
    return 0
  fi
  info "Installing Rust toolchain via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  export PATH="$HOME/.cargo/bin:$PATH"
}

install_binaries() {
  install_oh_my_posh
  install_yq
  install_lazygit
  install_neovim
  install_ast_grep
  install_tree_sitter_cli
  install_rust
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
# Foreground setup
# --------------------------------------------------------------------------

validate_linux() {
  if [ "$(uname -s)" != "Linux" ]; then
    error "This script is intended for Linux systems only."
    error "On macOS, use: bash bootstrap.sh"
    exit 1
  fi
}

ensure_core_dependencies() {
  if command -v stow &>/dev/null; then
    return 0
  fi

  info "Installing stow for foreground dotfile setup..."
  $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq stow
}

remove_if_not_symlink() {
  local path="$1"

  # Remove files/directories/symlinks that conflict with stow symlinks.
  # On reinstall, rm -rf ~/dotfiles leaves broken symlinks behind, so we
  # must handle real files, real directories, AND stale symlinks.
  if [ -L "$path" ]; then
    info "Removing stale symlink $path"
    rm -f "$path"
  elif [ -e "$path" ]; then
    info "Removing existing $path"
    rm -rf "$path"
  fi
}

setup_core_dotfiles() {
  if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ]; then
    info "Moving existing ~/.gitconfig to ~/.gitconfig.datadog"
    mv "$HOME/.gitconfig" "$HOME/.gitconfig.datadog"
    git config --file "$HOME/.gitconfig.datadog" user.signingkey 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsIVmGXH+CLtcN2o+q057GdyVitr/ICmNT+OAAEuGBN'
    remove_git_config_section_if_present "$HOME/.gitconfig.datadog" gpg.ssh
    remove_git_config_section_if_present "$HOME/.gitconfig.datadog" dd-gitsign
  fi
  remove_if_not_symlink "$HOME/.bashrc"
  remove_if_not_symlink "$HOME/.zshrc"
  remove_if_not_symlink "$HOME/.config/fish"

  install_dotfiles bash common-sh fish git oh-my-posh vim zsh
  setup_git
}

# --------------------------------------------------------------------------
# Deferred setup
# --------------------------------------------------------------------------

setup_default_shell() {
  local fish_bin
  fish_bin="$(command -v fish 2>/dev/null || true)"

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
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

write_install_status() {
  local state="$1"
  local exit_code="$2"
  local started_at="$3"
  local finished_at="$4"
  local revision status_tmp
  local exit_code_json="null"
  local finished_at_json="null"

  revision="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  status_tmp="$DOTFILES_STATUS_FILE.tmp.$$"

  if [ -n "$exit_code" ]; then
    exit_code_json="$exit_code"
  fi
  if [ -n "$finished_at" ]; then
    finished_at_json="\"$finished_at\""
  fi

  printf '{"state":"%s","started_at":"%s","finished_at":%s,"exit_code":%s,"revision":"%s"}\n' \
    "$state" "$started_at" "$finished_at_json" "$exit_code_json" "$revision" \
    > "$status_tmp"
  mv "$status_tmp" "$DOTFILES_STATUS_FILE"
}

finish_deferred_install() {
  local exit_code="$1"
  local state="succeeded"

  trap - EXIT
  if [ "$exit_code" -ne 0 ]; then
    state="failed"
  fi
  write_install_status "$state" "$exit_code" "$DEFERRED_STARTED_AT" "$(timestamp)"
}

run_deferred_install() {
  local unavailable_started_at

  mkdir -p "$DOTFILES_STATE_DIR"
  exec > >(tee -a "$DOTFILES_LOG_FILE") 2>&1

  if ! command -v flock &>/dev/null; then
    unavailable_started_at="$(timestamp)"
    write_install_status "failed" "127" "$unavailable_started_at" "$(timestamp)"
    error "flock is required for deferred dotfiles installation"
    return 127
  fi

  exec 9>"$DOTFILES_LOCK_FILE"

  if ! flock -n 9; then
    info "Another deferred dotfiles installation is already running; skipping"
    return 0
  fi

  DEFERRED_STARTED_AT="$(timestamp)"
  write_install_status "running" "" "$DEFERRED_STARTED_AT" ""
  trap 'finish_deferred_install $?' EXIT

  info "Starting deferred dotfiles installation..."
  install_apt_packages
  install_code_factory
  install_binaries
  install_zsh_history_substring_search
  setup_vim
  setup_fonts
  setup_default_shell
  info "Deferred installation complete"
  info "Start a new shell session to apply changes: exec \$SHELL -l"
}

launch_deferred_install() {
  local tmux_session

  mkdir -p "$DOTFILES_STATE_DIR"

  if [ "${DOTFILES_DISABLE_TMUX:-0}" != "1" ] && command -v tmux &>/dev/null; then
    # Use a unique session for every launcher. The worker's flock is the source
    # of truth for overlap, so stale or user-modified tmux sessions never block
    # a later explicit update.
    tmux_session="$DOTFILES_TMUX_SESSION_PREFIX-$(date -u '+%Y%m%d%H%M%S')-$$"
    if tmux new-session -d -s "$tmux_session" \
      "$SCRIPT_DIR/install.sh" --deferred; then
      info "Deferred installation started in tmux session $tmux_session"
      info "Attach with: tmux attach -t $tmux_session"
      return 0
    fi

    error "Failed to launch deferred installation in tmux"
    return 1
  fi

  warn "tmux not found; launching deferred installation with setsid and nohup"
  nohup setsid "$SCRIPT_DIR/install.sh" --deferred \
    > /dev/null 2>&1 < /dev/null &
}

main() {
  info "Starting foreground dotfiles installation for Linux..."
  info "Architecture: $ARCH ($ARCH_DEB)"

  validate_linux
  ensure_core_dependencies
  setup_core_dotfiles
  launch_deferred_install

  info "Foreground installation complete; deferred tooling setup will continue in the background"
}

case "${1:-}" in
  "")
    main
    ;;
  --deferred)
    shift
    if [ "$#" -ne 0 ]; then
      error "Usage: bash install.sh [--deferred]"
      exit 2
    fi
    validate_linux
    run_deferred_install
    ;;
  *)
    error "Usage: bash install.sh [--deferred]"
    exit 2
    ;;
esac
