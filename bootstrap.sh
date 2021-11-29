#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE}")"

git pull origin main

function install_brew() {
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	/bin/bash ./brew.sh
}

function install_asdf() {
	/bin/bash ./asdf.sh
}

function setup_git() {
	local name="$(git config user.name)"
	local email="$(git config user.email)"

	if [[ -N "$name" && -n "$email" ]]
	then
		return 0
	fi

	read -r -p 'Name: ' name
	git config --global user.name "$name"
	read -r -p 'Email: ' email
	git config --global user.email "$email"
}

function install_dotfiles() {
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

	setup_git
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

function doIt() {
	read -p "Install homebrew and packages? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_brew
	read -p "Install asdf and packages? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_asdf
	read -p "Copy dotfiles into $HOME? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_dotfiles
	read -p "Set computer name? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && set_computer_name
	read -p "Install MacOS defaults? (Y/n) " REPLY
	[[ ! $REPLY =~ ^[Nn]$ ]] && install_macos_defaults
}

if [ "$1" = "--force" -o "$1" = "-f" ]
then
	doIt
else
	read -p "This may overwrite existing files in your home directory and install software. Are you sure? (y/N) " REPLY
	echo ""
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		doIt
	fi
fi

unset doIt
