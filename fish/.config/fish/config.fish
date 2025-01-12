# Setup

function fish_greeting
end

set -g fish_prompt_pwd_dir_length 1

source ~/.config/fish/theme.fish

source ~/.config/fish/functions.fish

source ~/.config/fish/init.fish

if type oh-my-posh &>/dev/null
    oh-my-posh init fish --config ~/.config/omp/rtfpessoa.omp.json | source
end
