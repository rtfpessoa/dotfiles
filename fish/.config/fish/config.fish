# Setup

function fish_greeting
end

set -g fish_prompt_pwd_dir_length 1

if type oh-my-posh &>/dev/null
    oh-my-posh init fish --config ~/.config/omp/rtfpessoa.omp.json | source
end

test -e {$HOME}/.iterm2_shell_integration.fish ; and source {$HOME}/.iterm2_shell_integration.fish
