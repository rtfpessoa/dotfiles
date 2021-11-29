for file in ~/.{exports,path,aliases,extra}
    if test -f $file
        source $file
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

source $HOME/.asdf/asdf.fish
source $HOME/.asdf/completions/asdf.fish
source $HOME/.asdf/plugins/java/set-java-home.fish
