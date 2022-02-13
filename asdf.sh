#!/usr/bin/env bash

set -ux

# Install command-line tools using asdf.

function install_asdf_package() {
	local package_name="$1"
	local global="${2:-true}"
	local version="${3:-}"
	local plugin_url="${4:-}"

	if [ -n "$plugin_url" ]; then
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

asdf_tools=("github-cli" "golang" "sbt" "scala" "terraform" "terraform-lsp")
for tool in "${asdf_tools[@]}"; do
	install_asdf_package $tool
done

install_asdf_package "rust" "true" stable

# Not available for arm64
# install_asdf_package "graalvm" "false" ""

# Java
install_asdf_package "java" "false" "zulu-8.58.0.13"
install_asdf_package "java" "false" "zulu-11.52.13"
install_asdf_package "java" "true" "zulu-15.36.13"
install_asdf_package "java" "false" "zulu-17.30.15"

# Node.JS
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-previous-release-team-keyring'
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
install_asdf_package "nodejs" "true" "16.13.2"
install_asdf_package "yarn"
yarn global add diff2html-cli
asdf reshim nodejs

# Python
install_asdf_package "python" "false" "3.10.1"
install_asdf_package "python" "false" "2.7.18"
install_asdf_package "python" "false" "3.7.12"
asdf global python 3.7.12 2.7.18
asdf reshim python

# Ruby
install_asdf_package "ruby" "true" "3.0.3"
asdf reshim ruby
