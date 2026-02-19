#!/usr/bin/env bash
#
# lib.sh — Shared functions for bootstrap.sh and install.sh
#
# Source this file from your installer scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib.sh"
#

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
