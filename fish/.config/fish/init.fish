if test -x $HOME/.local/bin/mise
    $HOME/.local/bin/mise activate fish | source
end

# The macOS path file needs the prefix before it is sourced.
if test "$__dotfiles_os" = darwin; and test -z "$HOMEBREW_PREFIX"
    if command -sq brew
        set -gx HOMEBREW_PREFIX (command brew --prefix)
    end
    if test -z "$HOMEBREW_PREFIX"
        if test (command uname -m) = arm64
            set -gx HOMEBREW_PREFIX /opt/homebrew
        else
            set -gx HOMEBREW_PREFIX /usr/local
        end
    end
end

# Skip .functions — bash functions don't work in fish
for file in ~/.{exports,path,aliases,extra}
    if test -r $file
        source $file
    end
    if test -r $file.fish
        source $file.fish
    end
    if test -r $file.$__dotfiles_os
        source $file.$__dotfiles_os
    end
end

# Avoid issues with `gpg` as installed via Homebrew.
# https://stackoverflow.com/a/42265848/96656
set -gx GPG_TTY (tty)

set -l prefix "$HOMEBREW_PREFIX"
if test -z "$prefix"; and command -sq brew
    set prefix (command brew --prefix)
end
if test -n "$prefix"
    for dir in $prefix/share/fish/{completions,vendor_completions.d}
        if test -d "$dir"; and not contains -- "$dir" $fish_complete_path
            set -gax fish_complete_path "$dir"
        end
    end
end

# Homebrew can install the fish hook through vendor_conf.d.
if not functions -q __direnv_export_eval; and type -q direnv
    direnv hook fish | source
end
