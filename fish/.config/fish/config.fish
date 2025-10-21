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

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/opt/homebrew/share/google-cloud-sdk/path.fish.inc' ]; . '/opt/homebrew/share/google-cloud-sdk/path.fish.inc'; end

# Toggle an Oh My Posh segment twice (forces a re-render) safely.
function __omp_reset
    oh-my-posh init fish --config ~/.config/omp/rtfpessoa.omp.json | source
end

# Invalidate OMP cache after switching K8s context/namespace
# Triggered after every command that runs in the shell.
function __omp_clear_cache_after_kctx --on-event fish_postexec --argument-names cmd _status
    if string match -rq '^(ddtool|kubectl|k|kubectx|kctx)\s.+' -- $cmd
        __omp_reset
    end
end
