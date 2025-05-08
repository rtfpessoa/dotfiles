$HOME/.local/bin/mise activate fish | source

if test (uname -m) = arm64
    set -gx HOMEBREW_PREFIX "/opt/homebrew"
else
    set -gx HOMEBREW_PREFIX "/usr/local"
end

for file in ~/.{exports,path,aliases,extra}
    if test -r $file
        source $file
    end
    if test -r $file.fish
        source $file.fish
    end
end

# Avoid issues with `gpg` as installed via Homebrew.
# https://stackoverflow.com/a/42265848/96656
set -gx GPG_TTY (tty)

if test -d (brew --prefix)"/share/fish/completions"
    set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/completions
end

if test -d (brew --prefix)"/share/fish/vendor_completions.d"
    set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/vendor_completions.d
end

if test -d (brew --prefix)"/share/fish/completions"
    set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/completions
end

if type -q kubectl
	kubectl completion fish | source
end

if type -q direnv
	direnv hook fish | source
end
