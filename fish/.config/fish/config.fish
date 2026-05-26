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

# Workspace ssaitch bridge: only applies when the helper is installed.
# Background: ssaitch's shim emits bash syntax that fish cannot parse, and
# /etc/fish/conf.d/00-workspace-env.fish later sets BROWSER=xdg-open under
# the workspaces daemon. Override here, in config.fish (loaded after all
# conf.d), so OAuth flows reach the laptop browser via the forwarded socket.
# The override lives here and NOT in conf.d/ because fish loads user conf.d
# before system conf.d, so a conf.d file would be silently overridden.
if test -x $HOME/.local/bin/ssaitch-browser
    set -gx BROWSER $HOME/.local/bin/ssaitch-browser
    set -gx DDTOOL_AUTH_LOGIN_MODE auth-code
    # Pick up the forwarded socket dynamically; ssaitch names it after the
    # LAPTOP UID (e.g. 502 on macOS), not the workspace UID.
    set -l _sock (ls -t /tmp/ssaitch-*.sock 2>/dev/null | head -n1)
    test -n "$_sock"; and set -gx SSAITCH_SOCK $_sock
end
