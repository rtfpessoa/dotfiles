#!/usr/bin/env bash

set -ux

# Install command-line tools using asdf.

function install_asdf_package() {
	local package_name="$1"
	local global="${2:-true}"
	local version="${3:-}"
	local plugin_url="${4:-}"

	if asdf plugin list | grep "${package_name}"; then
		asdf plugin update "${package_name}"
	elif [ -n "$plugin_url" ]; then
		asdf plugin add "${package_name}" "${plugin_url}"
	else
		asdf plugin add "${package_name}"
	fi

	if [ -z "$version" ]; then
		version=$(asdf latest "${package_name}")
	fi

	asdf install "${package_name}" "${version}"

	if [ "$global" == "true" ]; then
		asdf global "${package_name}" "${version}"
	fi
}

if ! which asdf &>/dev/null; then
	git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf"
	(
		cd "$HOME/.asdf" &&
			git checkout "$(git describe --abbrev=0 --tags)"
	)
fi

mkdir -p ~/.config/fish/completions && ln -fs ~/.asdf/completions/asdf.fish ~/.config/fish/completions

(
	cd $HOME/.asdf &&
		git fetch --prune --tags --all --force &&
		git checkout "$(git describe --abbrev=0 --tags)"
)

source $HOME/.asdf/asdf.sh

asdf update

asdf_tools=("golang" "terraform" "terraform-ls")
for tool in "${asdf_tools[@]}"; do
	install_asdf_package $tool
done

# Java
install_asdf_package "java" "true" "zulu-23.30.13"

# Node.JS
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-previous-release-team-keyring'
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
install_asdf_package "nodejs" "false" "18.20.5"
install_asdf_package "nodejs" "false" "20.18.0"
install_asdf_package "nodejs" "true" "22.11.0"
corepack enable
asdf reshim nodejs
# yarn set version stable
yarn global add diff2html-cli --prefix /usr/local

# Python
install_asdf_package "python" "false" "3.13.0"
install_asdf_package "python" "false" "2.7.18"
asdf global python 3.13.0 2.7.18
asdf reshim python

# Ruby - broken in m1
export RUBY_CONFIGURE_OPTS="--with-openssl-dir=$HOMEBREW_PREFIX/opt/openssl@3"
export RUBY_CFLAGS="-Wno-error=implicit-function-declaration"
install_asdf_package "ruby" "true" "3.3.6"
asdf reshim ruby
