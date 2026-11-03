#!/usr/bin/env bash
# Exercise the real background fish in an isolated configuration.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture" XDG_CONFIG_HOME="$fixture/config"
export XDG_DATA_HOME="$fixture/data" XDG_CACHE_HOME="$fixture/cache"
conf="$XDG_CONFIG_HOME/fish"
mkdir -p "$conf/conf.d"
ln -s "$repo"/fish/.config/fish/conf.d/{75-async-prompt,76-async-prompt-config}.fish "$conf/conf.d/"
cat > "$conf/config.fish" <<'FISH'
function fish_greeting
end
function fish_prompt
    printf "%s/%s" $status (string join , $pipestatus)
end
FISH

# Fish expands the variables in this command.
# shellcheck disable=SC2016
TERM=dumb async_prompt_enable=1 fish -ic '
    if test (fish_prompt_loading_indicator previous) != previous
        echo "Loading indicator lost the previous prompt" >&2
        exit 1
    end
    if not string match -q -- "*⟳*" (fish_prompt_loading_indicator)
        echo "Empty prompt has no loading indicator" >&2
        exit 1
    end

    builtin true | builtin false
    emit fish_postexec
    emit fish_prompt
    set -l file "$__async_prompt_tmpdir/$fish_pid"_fish_prompt
    for attempt in (seq 1 100)
        if test -s "$file"; and test (string collect < "$file") = "1/0,1"
            exit 0
        end
        sleep 0.05
    end
    echo "Background prompt did not receive the command status and pipeline" >&2
    exit 1
'
