#!/usr/bin/env bash

# Re-entrancy guard: interactive shells source ~/.bash_profile from here;
# if that file (or a machine-local patch on it) re-sources ~/.bashrc along
# the way, stop instead of recursing. Shell-local (not exported), so
# nested/child shells start clean.
if [ -n "${_DOTFILES_BASH_RC:-}" ]; then
  return 0 2>/dev/null || true
fi
_DOTFILES_BASH_RC=1

[ -n "$PS1" ] && source $HOME/.bash_profile
