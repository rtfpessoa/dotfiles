if test -x $HOME/.local/bin/mise
    $HOME/.local/bin/mise activate fish | source
end

if test (uname -s) = Darwin
    if test (uname -m) = arm64
        set -gx HOMEBREW_PREFIX /opt/homebrew
    else
        set -gx HOMEBREW_PREFIX /usr/local
    end
end

# Skip .functions — bash functions don't work in fish
set -l _os (uname -s | tr '[:upper:]' '[:lower:]')
for file in ~/.{exports,path,aliases,extra}
    if test -r $file
        source $file
    end
    if test -r $file.fish
        source $file.fish
    end
    if test -r $file.$_os
        source $file.$_os
    end
end

# Avoid issues with `gpg` as installed via Homebrew.
# https://stackoverflow.com/a/42265848/96656
set -gx GPG_TTY (tty)

if type -q brew
    if test -d (brew --prefix)"/share/fish/completions"
        set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/completions
    end

    if test -d (brew --prefix)"/share/fish/vendor_completions.d"
        set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/vendor_completions.d
    end
end

if type -q kubectl
    kubectl completion fish | source
end

if type -q direnv
    direnv hook fish | source
end
