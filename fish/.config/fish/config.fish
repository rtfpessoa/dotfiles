# Setup

function fish_greeting
end

set -g fish_prompt_pwd_dir_length 1

source ~/.config/fish/theme.fish

source ~/.config/fish/functions.fish

source ~/.config/fish/init.fish

# Toggle an Oh My Posh segment twice (forces a re-render) safely.
function __omp_reset
    oh-my-posh init fish --config ~/.config/omp/rtfpessoa.omp.json | source
end

if type oh-my-posh &>/dev/null
	__omp_reset
end

# Invalidate OMP cache after switching K8s context/namespace
# Triggered after every command that runs in the shell.
function __omp_clear_cache_after_kctx --on-event fish_postexec --argument-names cmd _status
    if string match -rq '^(ddtool|kubectl|k|kubectx|kctx)\s.+' -- $cmd
        __omp_reset
    end
end
