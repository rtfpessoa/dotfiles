#!/usr/bin/env bash

set -ux

# Install command-line tools using mise.

if ! which mise &>/dev/null; then
	curl https://mise.run | sh
else
	mise self-update
fi

eval "$("${HOME}/.local/bin/mise" activate bash)"

mise use -g usage
mise reshim

sudo mkdir -p /etc/bash_completion.d
mise completion bash --include-bash-completion-lib | sudo tee /etc/bash_completion.d/mise

mkdir -p "${HOME}/.config/completions"
mise completion zsh  > "${HOME}/.config/completions/_mise"

mkdir -p "${HOME}/.config/fish/completions"
mise completion fish > "${HOME}/.config/fish/completions/mise.fish"

tools=("go" "terraform" "terraform-ls" "rust")
for tool in "${tools[@]}"; do
	mise use --global $tool@latest
	mise reshim
done

# Java
mise use --global java@zulu-23.30.13
mise reshim

# Node.JS
mise install node@18.20.5
mise install node@20.18.1
mise use --global node@22.13.0
mise reshim
corepack enable
mise reshim
npm install -g diff2html-cli
mise reshim

# Python
mise use -g python@3.13 python@3.12 python@3.11 python@3.10 python@2.7
mise reshim

# Ruby
mise use -g ruby@3.4.1
mise reshim

mise reshim -f
