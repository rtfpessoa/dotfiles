#!/usr/bin/env zsh

eval "$($HOME/.local/bin/mise activate zsh)"

if [ "$(uname -m)" = 'arm64' ]
then
	export HOMEBREW_PREFIX="/opt/homebrew"
else
	export HOMEBREW_PREFIX="/usr/local"
fi

# Add tab completion for many commands
if [ -f "$HOMEBREW_PREFIX/bin/brew" ]
then
  FPATH="${HOME}/.config/completions:$HOMEBREW_PREFIX/share/zsh/site-functions:$HOMEBREW_PREFIX/share/zsh-completions:${FPATH}"
fi

autoload -Uz promptinit && promptinit
autoload -Uz compinit compdef && compinit

# case-insensitive (uppercase from lowercase) completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# process completion
zstyle ':completion:*:processes' command 'ps -au$USER'
zstyle ':completion:*:*:kill:*:processes' list-colors "=(#b) #([0-9]#)*=36=31"

# zstyle
zstyle ':completion:*' completer _expand _complete _ignored _approximate
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu select=2
zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
zstyle ':completion:*:descriptions' format '%U%F{yellow}%d%f%u'

# Load the shell dotfiles, and then some:
# * ~/.path can be used to extend `$PATH`.
# * ~/.extra can be used for other settings you don’t want to commit.
for file in ~/.{functions,exports,path,aliases,extra}
do
	[ -r "${file}" ] && [ -f "${file}" ] && source "${file}"
	[ -r "${file}.zsh" ] && [ -f "${file}.zsh" ] && source "${file}.zsh"
done
unset file

if type oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init zsh --config ~/.config/omp/rtfpessoa.omp.json)"
fi

for file in "$HOMEBREW_PREFIX/share/zsh-history-substring-search/zsh-history-substring-search.zsh" "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
do
	[ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

if type kubectl &>/dev/null; then
  source <(kubectl completion zsh)
fi

if type direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Immmediatly write to history (cannot be used together with SHARE_HISTORY)
# setopt INC_APPEND_HISTORY
# Write to history but also save time (similar to EXTENDED_HISTORY, cannot be used together with SHARE_HISTORY)
# setopt INC_APPEND_HISTORY_TIME
# Share history between sessions (cannot be used together with INC_APPEND_HISTORY)
setopt SHARE_HISTORY
# Write time of execution of commands (cannot be used together with SHARE_HISTORY or INC_APPEND_HISTORY)
# setopt EXTENDED_HISTORY
# Remove dups when navigation history
setopt HIST_FIND_NO_DUPS
# Skip dups when saving to history
setopt HIST_IGNORE_ALL_DUPS
# Remove superfluous blanks from each command line being added to the history list
setopt histreduceblanks
# Remove command lines from the history list when the first character on the
# line is a space, or when one of the expanded aliases contains a leading space
setopt histignorespace
# Do not enter command lines into the history list if they are duplicates of the previous event.
setopt histignorealldups
# Switching directories for lazy people
setopt autocd
# See: http://zsh.sourceforge.net/Intro/intro_6.html
setopt autopushd pushdminus pushdsilent pushdtohome pushdignoredups
# Don't kill background jobs when I logout
setopt nohup
# See: http://zsh.sourceforge.net/Intro/intro_2.html
setopt extendedglob
# Do not require a leading '.' in a filename to be matched explicitly
setopt globdots
# Use vi key bindings in ZSH
setopt vi
# Causes field splitting to be performed on unquoted parameter expansions
setopt shwordsplit
# Automatically use menu completion after the second consecutive request for completion
setopt automenu
# If the argument to a cd command (or an implied cd with the AUTO_CD option set)
# is not a directory, and does not begin with a slash, try to expand the
# expression as if it were preceded by a '~'
setopt cdablevars
# Try to make the completion list smaller (occupying less lines) by printing
# the matches in columns with different widths
setopt listpacked
# Don't show types in completion lists
setopt nolisttypes
# If a completion is performed with the cursor within a word, and a full
# completion is inserted, the cursor is moved to the end of the word
setopt alwaystoend
# Try to correct the spelling of commands
setopt correct
# https://github.com/robbyrussell/oh-my-zsh/issues/449
setopt no_nomatch
# Disable annoying confirm
setopt rmstarsilent

# Avoid issues with `gpg` as installed via Homebrew.
# https://stackoverflow.com/a/42265848/96656
export GPG_TTY="$(tty)"
