#!/usr/bin/env bash

function install_brew() {
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	/bin/bash ./brew.sh
}

function install_asdf() {
	/bin/bash ./asdf.sh
}

function setup_git() {
	local name="${1:-$(git config user.name)}"
	local email="${2:-$(git config user.email)}"

	if [[ -n "$name" && -n "$email" ]]
	then
		source ~/.extra
		return 0
	fi

	read -r -p 'Name: ' name
	read -r -p 'Email: ' email

	cat > ~/.extra <<- EOF
	# Git credentials
	# Not in the repository, to prevent people from accidentally committing under my name
	export GIT_AUTHOR_NAME="$name"
	export GIT_COMMITTER_NAME="\$GIT_AUTHOR_NAME"
	git config --global user.name "\$GIT_AUTHOR_NAME"
	export GIT_AUTHOR_EMAIL="$email"
	export GIT_COMMITTER_EMAIL="\$GIT_AUTHOR_EMAIL"
	git config --global user.email "\$GIT_AUTHOR_EMAIL"
	EOF

	source ~/.extra
}

function install_dotfiles() {
	local name="$(git config user.name)"
	local email="$(git config user.email)"

	rsync \
		--exclude "init/" \
		--exclude ".git/" \
		--exclude ".macos" \
		--exclude ".DS_Store" \
		--exclude ".osx" \
		--exclude "asdf.sh" \
		--exclude "bootstrap.sh" \
		--exclude "brew.sh" \
		--exclude "LICENSE.txt" \
		--exclude "README.md" \
		-avh --no-perms . ~

	setup_git "$name" "$email"
}

function setup_fonts() {
	if test -e ~/.local/share/fonts/Inconsolata[wdth,wght].ttf || test -e ~/Library/Fonts/Inconsolata[wdth,wght].ttf
	then
		exit 0
	fi

	function download_font() {
		curl -Lso $1/Inconsolata[wdth,wght].ttf https://github.com/google/fonts/raw/master/ofl/inconsolata/Inconsolata%5Bwdth%2Cwght%5D.ttf
	}

	case "$(uname)" in
		"Darwin")
			download_font ~/Library/Fonts
			;;

		*)
			mkdir -p ~/.local/share/fonts/ &&
				download_font ~/.local/share/fonts/
			if command -qs fc-cache
			then
				fc-cache -fv
			fi
			;;
	esac
}

function set_computer_name() {
	local name=""
	read -p "Computer name: " name
	if [ -z "$name" ]
	then
		return 0
	fi

	sudo scutil --set ComputerName "${name}"
	sudo scutil --set HostName "${name}"
	sudo scutil --set LocalHostName "${name}"
	sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${name}"
}

function install_macos_defaults() {
	/bin/bash .macos
}

function bootstrap() {
	read -p "Install homebrew and packages? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_brew
	read -p "Install asdf and packages? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_asdf
	read -p "Copy dotfiles into $HOME? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_dotfiles
	read -p "Set computer name? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && set_computer_name
	read -p "Install fonts? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && setup_fonts
	read -p "Install MacOS defaults? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_macos_defaults
}

install_dotfiles
exit 1

if [ "$1" != "--force" -a "$1" != "-f" ]
then
	read -p "This may overwrite existing files in your home directory and install software. Are you sure? (y/N) " REPLY
	echo ""
	if [[ ! $REPLY =~ ^[Yy]$ ]]
	then
		exit 0
	fi
fi

cd "$(dirname "${BASH_SOURCE}")"

git pull origin main

bootstrap
