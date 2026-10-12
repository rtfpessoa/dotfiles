# Local configuration for fish-async-prompt (vendored in 75-async-prompt.fish).
#
# Only the left prompt renders asynchronously; the right prompt (clock and
# execution time) stays synchronous so command durations stay accurate.
#
# Kill switch (keeps the files installed): set -U async_prompt_enable 0
# Full rollback: set -e async_prompt_functions; and __omp_reset

# Which prompt functions to render in the background. Universal so every
# fish instance (including nested and future panes) agrees.
set -U async_prompt_functions fish_prompt

# Build the stripped-down theme used for the loading seed: the session +
# path segments and the ↪ line of the real prompt, without the slow parts
# (git, kubectl) or the right-aligned clock. Cached under ~/.cache/oh-my-posh
# and regenerated only when the theme file changes.
function __async_prompt_seed_config
    set -l theme ~/.config/omp/rtfpessoa.omp.json
    test -r $theme; or return 1
    set -l cachedir ~/.cache/oh-my-posh
    mkdir -p $cachedir; or return 1
    set -l cfg $cachedir/async-seed.omp.json
    # stat flags differ between BSD and GNU coreutils; both forms yield
    # '<epoch-seconds> <size>', matching the stamp python3 writes below.
    set -l fresh
    if test (uname -s) = Darwin
        set fresh (stat -f '%m %z' $theme)
    else
        set fresh (stat -c '%Y %s' $theme)
    end
    if test -r $cfg; and test (cat $cfg.stamp 2>/dev/null; or echo none) = "$fresh"
        printf '%s' $cfg
        return 0
    end
    python3 -c 'import json,sys,os
src,dst=sys.argv[1],sys.argv[2]
cfg=json.load(open(src))
out=[]
for b in cfg.get("blocks",[]):
    if b.get("alignment")=="right":
        continue
    if b.get("segments") and any(s.get("type")=="path" for s in b["segments"]):
        segs=[s for s in b["segments"] if s.get("type") in ("session","path")]
        segs.append({"type":"text","style":"plain","foreground":"#6272a4","template":"⟳","options":{"prefix":" ","postfix":""}})
        b=dict(b,segments=segs)
    out.append(b)
cfg["blocks"]=out
json.dump(cfg,open(dst,"w"),indent=2)
open(dst+".stamp","w").write("%d %d"%(os.stat(src).st_mtime,os.stat(src).st_size))' $theme $cfg 2>/dev/null; or return 1
    printf '%s' $cfg
end

# The loading seed itself: render the prompt start with the real
# oh-my-posh binary so the folder icon, mapped-path emoji and ↪ line are
# pixel-identical to the finished prompt minus the slow segments, plus a dim ⟳ hint at the end of line 1 (line 2 keeps the original ↪). POSH_SESSION_ID must be scrubbed: oh-my-posh keys its loaded theme on it and it would override --config; an exported POSH_CONFIG value alone is harmless but is overridden too.
function __async_prompt_seed_prompt
    set -l cfg (__async_prompt_seed_config)
    or return 1
    set -l out (env -u POSH_SESSION_ID POSH_CONFIG=$cfg oh-my-posh print primary --config $cfg --shell=fish 2>/dev/null | string collect)
    test -n "$out"; or return 1
    printf '\e[0J%s' "$out"
end

# Seed this shell's prompt file so the very first prompt render is never
# blank while the background render warms up. The tmpdir only exists in
# interactive shells (75- exits early otherwise), and the seed is also
# what makes the first prompt of a new pane instant.
if status is-interactive; and set -q __async_prompt_tmpdir
    __async_prompt_seed_prompt > $__async_prompt_tmpdir'/'$fish_pid'_fish_prompt'
    or printf '%s' (set_color brblack)"⟳ "(prompt_pwd)(set_color normal)' $ ' > $__async_prompt_tmpdir'/'$fish_pid'_fish_prompt'
end

# Rendered synchronously between firing the background render and its
# arrival: keep the previous prompt (no flicker); fall back to a minimal
# dim prompt if there is nothing to keep yet.
function fish_prompt_loading_indicator --argument-names last_prompt
    if test -n "$last_prompt"
        printf '%s' "$last_prompt"
    else
        __async_prompt_seed_prompt
        or printf '%s' (set_color brblack)"⟳ "(prompt_pwd)(set_color normal)' $ '
    end
end

# Re-apply the async wrapper after __omp_reset (or anything else) replaces
# fish_prompt with a fresh OMP definition — OMP init would otherwise drop
# the wrapper. Also runs at config load (via __omp_reset in config.fish) so
# the FIRST prompt of a new shell is the instant seed instead of a full
# synchronous OMP render; the vendored setup skips already-wrapped functions
# (see the LOCAL PATCH there).
function __async_prompt_rewrap
    functions -q __async_prompt_fire; or return 0
    test "$async_prompt_enable" != 0; or return 0
    contains -- fish_prompt $async_prompt_functions; or return 0
    functions -e __async_prompt_orig_fish_prompt 2>/dev/null
    functions -c fish_prompt __async_prompt_orig_fish_prompt
    function fish_prompt
        test -e $__async_prompt_tmpdir'/'$fish_pid'_fish_prompt'
        and string collect <$__async_prompt_tmpdir'/'$fish_pid'_fish_prompt'
    end
end

# fish 4.9 (the Rust rewrite) waits for every `&` child spawned inside event
# handlers and other non-interactive evals — `fish -c 'x &'` blocks until x
# exits — and such jobs never enter the job table, so the vendored `disown`
# cannot detach them either. That made every prompt cycle a synchronous full
# render (7s+ in dd-source). Override the spawner with a true double-fork
# detach via perl: the parent only waits for perl (~10ms) and the render
# continues in a session-detached grandchild. The variable list moves from
# the vendored stdin pipe to the child's $argv (fish -c passes trailing
# arguments through as $argv).
function __async_prompt_spawn -a cmd
    __async_prompt_log "__async_prompt_spawn" "(fish 4.9 override) Spawning command: $cmd"

    # Determines values for the inherited variable names, as a list of
    # `name value` strings (one element each — the child splits them again).
    # Never reads stdin: event-handler context stdin is the tty, not a pipe
    # (that is what broke the vendored spawn).
    set -l envs
    set -l varlist
    for line in (__async_prompt_config_inherit_variables)
        switch "$line"
            case fish_bind_mode
                set varlist $varlist "fish_bind_mode $fish_bind_mode"
            case FISH_VERSION PWD _ history 'fish_*' hostname version status_generation
            case status pipestatus
                set varlist $varlist "pipestatus $__async_prompt_last_pipestatus"
            case SHLVL
                set envs $envs SHLVL=$SHLVL
            case '*'
                set varlist $varlist "$line "(string escape -- $$line)
        end
    end

    perl -e 'exit if fork; setpgrp; exec @ARGV' \
        env $envs __async_prompt_last_pipestatus=$__async_prompt_last_pipestatus \
        fish -c 'begin
    function __async_prompt_signal
        kill -s "'(__async_prompt_config_internal_signal)'" '$fish_pid' 2>/dev/null
    end
    for line in $argv
        test -z "$line"
        and continue

        set -f __parts $line
        if test "$__parts[1]" = pipestatus
            set -f _pipestatus $__parts[2..]
        else
            eval set "$line"
        end
    end

    function __async_prompt_set_status
        return $argv
    end
    if set -q _pipestatus
        switch (count $_pipestatus)
            case 1
                __async_prompt_set_status $_pipestatus[1]
            case 2
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2]
            case 3
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3]
            case 4
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4]
            case 5
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5]
            case 6
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6]
            case 7
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6] \
                | __async_prompt_set_status $_pipestatus[7]
            case 8
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6] \
                | __async_prompt_set_status $_pipestatus[7] \
                | __async_prompt_set_status $_pipestatus[8]
            default
                __async_prompt_set_status $_pipestatus[1] \
                | __async_prompt_set_status $_pipestatus[2] \
                | __async_prompt_set_status $_pipestatus[3] \
                | __async_prompt_set_status $_pipestatus[4] \
                | __async_prompt_set_status $_pipestatus[5] \
                | __async_prompt_set_status $_pipestatus[6] \
                | __async_prompt_set_status $_pipestatus[7] \
                | __async_prompt_set_status $_pipestatus[8] \
                | __async_prompt_set_status $_pipestatus[-1]
        end
    else
        true
    end
    '$cmd'
    __async_prompt_signal
end' $varlist < /dev/null 2>/dev/null
end
