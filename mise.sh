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

tools=("go" "rust")
for tool in "${tools[@]}"; do
	mise use --global $tool@latest
	mise reshim
done

# Java
mise use --global java@zulu-26
mise reshim

# Node.JS
mise install node@20
mise install node@22
mise use --global node@24
mise reshim
corepack enable
mise reshim
npm install -g diff2html-cli
npm install -g neovim
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
npm install -g --ignore-scripts @earendil-works/pi-agent-core
npm install -g --ignore-scripts @earendil-works/pi-ai
pi install git:github.com/earendil-works/pi-review
mise reshim

# Python
mise use -g python@3.14 python@3.10 python@2.7
pip install neovim
mise reshim

# Ruby
mise use -g ruby@4
gem install neovim
mise reshim

mise reshim -f
