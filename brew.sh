#!/usr/bin/env bash

# Install command-line tools using Homebrew.

# Save Homebrew’s installed location.
if [ "$(uname -m)" = 'arm64' ]
then
	export HOMEBREW_PREFIX="/opt/homebrew"
else
	export HOMEBREW_PREFIX="/usr/local"
fi

eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"

# Make sure we’re using the latest Homebrew.
brew update

# Upgrade any already-installed formulae.
brew upgrade

# Install dotfiles symlink manager
brew install stow

brew install binutils

# Install GNU core utilities (those that come with macOS are outdated).
# Don’t forget to add `$(brew --prefix coreutils)/libexec/gnubin` to `$PATH`.
brew install coreutils

# Install some other useful utilities like `sponge`.
brew install moreutils
# Install GNU `find`, `locate`, `updatedb`, and `xargs`, `g`-prefixed.
brew install findutils
# Install GNU `sed`, overwriting the built-in `sed`.
# Don’t forget to add `$(brew --prefix)/opt/gnu-sed/libexec/gnubin` to `$PATH`.
brew install gnu-sed

# Install a modern version of Bash.
brew install bash
brew install bash-completion@2

# Install a modern version of Zsh.
brew install zsh
brew install zsh-completions
brew install zsh-history-substring-search
brew install zsh-syntax-highlighting
brew install zsh-autosuggestions

# Shell prompt
brew install jandedobbeleer/oh-my-posh/oh-my-posh

# Install `wget` with IRI support.
brew install wget

# Install GnuPG to enable PGP-signing commits.
brew install gnupg

# Install more recent versions of some macOS tools.
brew install nvim
brew install fd
brew install lazygit

# Install GNU `grep`, overwriting the built-in `grep`.
# Don’t forget to add `$(brew --prefix)/opt/grep/libexec/gnubin` to `$PATH`.
brew install grep
brew install openssh
brew install screen

# Install other useful binaries.
brew install git
brew install git-lfs
brew install git-machete

# Others
brew install fish
brew install bat
brew install ripgrep
brew install jq
brew install yq

brew install shellcheck

# ruby-build
brew install openssl@3 readline libyaml gmp autoconf

# Docker for Mac
# brew install --cask docker
# Slow as hell https://github.com/docker/cli/issues/3889
# brew install docker-completion

# Install docker cli
brew install --formula docker
brew install colima
mkdir -p ~/.docker/cli-plugins
brew install docker-buildx
ln -sfn $(which docker-buildx) ~/.docker/cli-plugins/docker-buildx
# To keep using the `docker build` install but with buildkit: https://docs.docker.com/engine/reference/commandline/buildx_install/
docker buildx install
brew install docker-compose
ln -sfn $(which docker-compose) ~/.docker/cli-plugins/docker-compose

# colima start --arch=aarch64 --vm-type=vz --vz-rosetta --mount-type virtiofs --memory 16 --cpu 4 --disk 64

# Casks
brew install --force --cask spotify
brew install --force --cask iterm2
brew install --force --cask visual-studio-code
brew install --force --cask vlc
if [ -n "$INSTALL_ALL" ]
then
	brew install --force --cask firefox
	brew install --force --cask intellij-idea-ce
	brew install --force --cask discord
	brew install --force --cask keepingyouawake
	brew install --force --cask linearmouse
	brew install --force --cask whisky
	brew install --force --cask orbstack
	brew install --force --cask utm
	brew install --force --cask lm-studio
	brew install --force --cask ghostty
	brew install --force --cask nikitabobko/tap/aerospace
fi

# Remove outdated versions from the cellar.
brew cleanup

# Fix permissions
chmod -R go-w "${HOMEBREW_PREFIX}/share"

# Add brew-installed bash shell to list
if ! fgrep -q "${HOMEBREW_PREFIX}/bin/bash" /etc/shells; then
	echo "${HOMEBREW_PREFIX}/bin/bash" | sudo tee -a /etc/shells
fi

# Add brew-installed zsh shell to list
if ! fgrep -q "${HOMEBREW_PREFIX}/bin/zsh" /etc/shells; then
	echo "${HOMEBREW_PREFIX}/bin/zsh" | sudo tee -a /etc/shells
fi

# Switch to using brew-installed fish shell as default shell
if ! fgrep -q "${HOMEBREW_PREFIX}/bin/fish" /etc/shells; then
	echo "${HOMEBREW_PREFIX}/bin/fish" | sudo tee -a /etc/shells
	chsh -s "${HOMEBREW_PREFIX}/bin/fish"
fi
