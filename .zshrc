source "$HOME/.asdf/asdf.sh"

# Add tab completion for many commands
if type brew &>/dev/null
then
  FPATH="${ASDF_DIR}/completions:$(brew --prefix)/share/zsh/site-functions:$(brew --prefix)/share/zsh-completions:${FPATH}"

  autoload -Uz compinit
  compinit
fi

# Load the shell dotfiles, and then some:
# * ~/.path can be used to extend `$PATH`.
# * ~/.extra can be used for other settings you don’t want to commit.
for file in ~/.{functions,exports,path,zsh_prompt,aliases,datadog,extra}
do
	[ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# Add tab completion for many commands
source "$HOME/.asdf/plugins/java/set-java-home.bash"

setopt HIST_FIND_NO_DUPS
# following should be turned off, if sharing history via setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY

# Avoid issues with `gpg` as installed via Homebrew.
# https://stackoverflow.com/a/42265848/96656
export GPG_TTY="$(tty)"
