#!/usr/bin/env bash
#
# lib.sh — Shared functions for bootstrap.sh and install.sh
#
# Source this file from your installer scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib.sh"
#

# --------------------------------------------------------------------------
# Logging helpers
# --------------------------------------------------------------------------
info() { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

CODE_FACTORY_DIR="$HOME/.code-factory"
CODE_FACTORY_REPO="https://github.com/rtfpessoa/code-factory.git"
CODE_FACTORY_SSH_REPO="git@github.com:rtfpessoa/code-factory.git"
CODE_FACTORY_HTTPS_PREFIX="https://github.com/rtfpessoa/"

# --------------------------------------------------------------------------
# Git config helpers
# --------------------------------------------------------------------------
remove_git_config_section_if_present() {
  local config_file="$1"
  local section="$2"
  local escaped_section="${section//./\\.}"
  local status

  if git config --file "$config_file" --get-regexp "^${escaped_section}\\.[^.]+$" >/dev/null; then
    git config --file "$config_file" --remove-section "$section"
  else
    status=$?
    if [ "$status" -eq 1 ]; then
      return 0
    fi
    return "$status"
  fi
}

# --------------------------------------------------------------------------
# Stow dotfiles
# --------------------------------------------------------------------------
# Usage: install_dotfiles dir1 dir2 dir3 ...
# If no arguments, stows all directories.
install_dotfiles() {
  local stow_dirs=("$@")
  if [ ${#stow_dirs[@]} -eq 0 ]; then
    stow_dirs=("apps" "bash" "common-sh" "fish" "git" "nvim" "oh-my-posh" "vim" "zsh")
  fi

  for stow_dir in "${stow_dirs[@]}"; do
    stow -R -d "$SCRIPT_DIR" -t "$HOME" "$stow_dir"
  done
}

# --------------------------------------------------------------------------
# Vim/Neovim plugin setup
# --------------------------------------------------------------------------
setup_vim() {
  if command -v vim &>/dev/null; then
    vim -es '+PlugInstall --sync' +qa </dev/null 2>/dev/null || true
  fi

  if command -v nvim &>/dev/null; then
    nvim --headless '+Lazy! sync' +qa 2>/dev/null || true
  fi
}

# --------------------------------------------------------------------------
# Font installation
# --------------------------------------------------------------------------
install_font() {
  local dest_dir="$1"
  local font_src="$SCRIPT_DIR/fonts/FiraCode-Retina.ttf"
  if [ -f "$font_src" ]; then
    mkdir -p "$dest_dir"
    cp -f "$font_src" "$dest_dir/FiraCode-Retina.ttf"
  fi
}

setup_fonts() {
  case "$(uname -s)" in
    Darwin)
      install_font ~/Library/Fonts
      ;;
    *)
      install_font ~/.local/share/fonts/
      if command -v fc-cache &>/dev/null; then
        fc-cache -f 2>/dev/null || true
      fi
      ;;
  esac
}

# --------------------------------------------------------------------------
# AI coding configs (code-factory)
# --------------------------------------------------------------------------
code_factory_git_https() {
  GIT_TERMINAL_PROMPT=0 \
    git -c "url.${CODE_FACTORY_HTTPS_PREFIX}.insteadOf=${CODE_FACTORY_HTTPS_PREFIX}" "$@"
}

code_factory_git_ssh() {
  GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    git "$@"
}

code_factory_ssh_available() {
  [ -n "${SSH_AUTH_SOCK:-}" ] || return 1
  code_factory_git_ssh ls-remote "$CODE_FACTORY_SSH_REPO" HEAD >/dev/null 2>&1
}

code_factory_transport() {
  if code_factory_ssh_available; then
    printf 'ssh\n'
  else
    printf 'https\n'
  fi
}

code_factory_checkout_is_valid() {
  [ -e "$CODE_FACTORY_DIR/.git" ] || return 1
  git -C "$CODE_FACTORY_DIR" rev-parse HEAD >/dev/null 2>&1
}

code_factory_require_mcp_auth() {
  if command -v mcp-auth >/dev/null 2>&1; then
    return 0
  fi

  error "mcp-auth is required by code-factory to generate the Pi MCP configuration."
  error "For workspaces, connect with ssaitch so it uploads mcp-auth and the browser bridge."
  error "Raw ssh sessions do not provision this dependency."
  return 1
}

code_factory_access_error() {
  local operation="$1"
  local transport="$2"

  error "Unable to ${operation} code-factory over ${transport}."
  error "GitHub authentication must be available non-interactively."
  if [ "$transport" = "ssh" ]; then
    error "Provide a working SSH agent/key for git@github.com or configure HTTPS Git credentials."
  else
    error "Configure HTTPS Git credentials, for example with: gh auth login && gh auth setup-git"
  fi
}

install_code_factory() {
  local transport

  if ! code_factory_require_mcp_auth; then
    return 1
  fi

  if [ -e "$CODE_FACTORY_DIR" ] && ! code_factory_checkout_is_valid; then
    error "code-factory directory is not a complete Git checkout: $CODE_FACTORY_DIR"
    error "Remove the incomplete directory and rerun the installer."
    return 1
  fi

  transport="$(code_factory_transport)"
  if [ -d "$CODE_FACTORY_DIR" ]; then
    info "Updating code-factory over $transport..."
    if [ "$transport" = "ssh" ]; then
      if ! code_factory_git_ssh \
        -c "remote.origin.url=$CODE_FACTORY_SSH_REPO" \
        -C "$CODE_FACTORY_DIR" pull --ff-only origin main; then
        code_factory_access_error update "$transport"
        return 1
      fi
    elif ! code_factory_git_https \
      -c "remote.origin.url=$CODE_FACTORY_REPO" \
      -C "$CODE_FACTORY_DIR" pull --ff-only origin main; then
      code_factory_access_error update "$transport"
      return 1
    fi
  else
    info "Cloning code-factory over $transport..."
    if [ "$transport" = "ssh" ]; then
      if ! code_factory_git_ssh clone "$CODE_FACTORY_SSH_REPO" "$CODE_FACTORY_DIR"; then
        code_factory_access_error clone "$transport"
        return 1
      fi
    elif ! code_factory_git_https clone "$CODE_FACTORY_REPO" "$CODE_FACTORY_DIR"; then
      code_factory_access_error clone "$transport"
      return 1
    fi
  fi

  info "Running code-factory init..."
  bash "$CODE_FACTORY_DIR/init.sh"
}
