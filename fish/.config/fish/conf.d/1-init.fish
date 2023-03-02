if test (uname -m) = 'arm64'
	export HOMEBREW_PREFIX="/opt/homebrew"
else
	export HOMEBREW_PREFIX="/usr/local"
end

for file in ~/.{exports,path,aliases,extra}
    if test -f $file
        source $file
    end
    if test -f $file.fish
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

for file in "$HOME/.asdf/asdf.fish" "$HOME/.asdf/completions/asdf.fish" "$HOME/.asdf/plugins/java/set-java-home.fish"
    if test -f $file
        source $file
    end
end

if type -q kubectl
	kubectl completion fish | source
end
