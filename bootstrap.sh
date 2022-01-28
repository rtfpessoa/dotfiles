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

	if [[ -n "$name" && -n "$email" && -f ~/.gitconfig.extras ]]; then
		return 0
	fi

	read -r -p 'Name: ' name
	read -r -p 'Email: ' email

	cat >~/.gitconfig.extras <<-EOF
	[user]

	    name = "$name"
	    email = "$email"
	EOF
}

function setup_vscode() {
	cat ./apps/Library/Application\ Support/Code/User/extensions.json | jq -r .recommendations[] | xargs -L 1 code --install-extension
}

function setup_vim() {
	curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
		https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
	vim +'PlugInstall --sync' +qa
}

function install_dotfiles() {
	local name
	name="$(git config user.name)"
	local email
	email="$(git config user.email)"


	local stow_dirs
	stow_dirs=("apps" "bash" "common-sh" "fish" "git" "nsh" "vim" "zsh")

	for stow_dir in "${stow_dirs[@]}"; do
		stow -D "$stow_dir"
		stow "$stow_dir"
	done

	setup_git "$name" "$email"
}

function setup_fonts() {
	if test -e "$HOME/.local/share/fonts/FiraCode-Retina.ttf" || test -e "$HOME/Library/Fonts/FiraCode-Retina.ttf"; then
		return 0
	fi

	function install_font() {
		cp -f ./fonts/FiraCode-Retina.ttf "$1/FiraCode-Retina.ttf"
	}

	case "$(uname)" in
	"Darwin")
		download_font ~/Library/Fonts
		;;

	*)
		mkdir -p ~/.local/share/fonts/ &&
			download_font ~/.local/share/fonts/
		if command -qs fc-cache; then
			fc-cache -fv
		fi
		;;
	esac
}

function set_computer_name() {
	local name=""
	read -r -p "Computer name: " name
	if [ -z "$name" ]; then
		return 0
	fi

	sudo scutil --set ComputerName "${name}"
	sudo scutil --set HostName "${name}"
	sudo scutil --set LocalHostName "${name}"
	sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${name}"
}

function install_macos_defaults() {
	/bin/bash ./macos.sh
}

function bootstrap() {
	read -r -p "Update repository? (y/N) " REPLY
	[[ "$REPLY" =~ ^[Yy]$ ]] && git pull origin main
	read -r -p "Install homebrew and packages? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && install_brew
	read -r -p "Install asdf and packages? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && install_asdf
	read -r -p "Install vscode plugins? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && setup_vscode
	read -r -p "Copy dotfiles into $HOME? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && install_dotfiles
	read -r -p "Install vim plugins? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && setup_vim
	read -r -p "Set computer name? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && set_computer_name
	read -r -p "Install fonts? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && setup_fonts
	read -r -p "Install MacOS defaults? (Y/n) " REPLY
	[[ ! "$REPLY" =~ ^[Nn]$ ]] && install_macos_defaults
}

if [ "$1" != "--force" ] && [ "$1" != "-f" ]; then
	read -r -p "This may overwrite existing files in your home directory and install software. Are you sure? (y/N) " REPLY
	echo ""
	if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
		exit 0
	fi
fi

cd "$(dirname "${BASH_SOURCE}")"

bootstrap
