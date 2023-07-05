#!/usr/bin/env bash

# Install command-line tools using Homebrew.

# Save Homebrew’s installed location.
HOMEBREW_PREFIX=$(brew --prefix)

eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"

# Make sure we’re using the latest Homebrew.
brew update

# Upgrade any already-installed formulae.
brew upgrade

# Install dotfiles symlink manager
brew install stow

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
brew install vim
if [ -n "$INSTALL_ALL" ]
then
	brew install neovim
fi
# Install GNU `grep`, overwriting the built-in `grep`.
# Don’t forget to add `$(brew --prefix)/opt/grep/libexec/gnubin` to `$PATH`.
brew install grep
brew install openssh
brew install screen

# Install font tools.
brew tap bramstein/webfonttools
brew install sfnt2woff
brew install sfnt2woff-zopfli
brew install woff2

# Install some CTF tools; see https://github.com/ctfs/write-ups.
# brew install aircrack-ng # Not available for amd64
brew install bfg
brew install binutils
brew install binwalk
brew install cifer
brew install dex2jar
brew install dns2tcp
brew install fcrackzip
brew install foremost
brew install hashpump
brew install hydra
brew install john
brew install knock
brew install netpbm
brew install nmap
brew install pngcheck
brew install socat
brew install sqlmap
brew install tcpflow
brew install tcpreplay
brew install tcptrace
brew install ucspi-tcp # `tcpserver` etc.
brew install xpdf
brew install xz

# Install other useful binaries.
brew install git
brew install git-lfs

# Others
brew install fish
brew install bat
brew install ripgrep
brew install jq
brew install yq

brew install shellcheck

# Casks
brew install --cask spotify
brew install --cask iterm2
brew install --cask visual-studio-code
brew install --cask vlc
if [ -n "$INSTALL_ALL" ]
then
	brew install --cask brave-browser
	brew install --cask intellij-idea-ce
	brew install --cask discord
	brew install --cask dozer
	brew install --cask keepingyouawake
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

# Docker for Mac
# brew install --cask docker
# Slow as hell https://github.com/docker/cli/issues/3889
# brew install docker-completion

# Install docker cli
brew install docker
brew install colima
# colima start --arch=aarch64 --vm-type=vz --vz-rosetta --mount-type virtiofs --memory 16 --cpu 4 --disk 64
