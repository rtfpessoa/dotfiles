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
install_code_factory() {
  if [ -d "$CODE_FACTORY_DIR" ]; then
    info "Updating code-factory..."
    git -C "$CODE_FACTORY_DIR" pull --ff-only origin main || true
  else
    info "Cloning code-factory..."
    git clone "$CODE_FACTORY_REPO" "$CODE_FACTORY_DIR"
  fi

  info "Running code-factory init..."
  bash "$CODE_FACTORY_DIR/init.sh"
}
