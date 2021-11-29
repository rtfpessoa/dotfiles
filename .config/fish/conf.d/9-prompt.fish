# Shell prompt based on the Solarized Dark theme.
# Screenshot: http://i.imgur.com/EkEtphC.png
# Heavily inspired by @necolas’s prompt: https://github.com/necolas/dotfiles
# iTerm → Profiles → Text → use 13pt Monaco with 1.1 vertical spacing.s

function prompt_git
    set -l branchName ''
    set -l s ''

    # Check if the current directory is in a Git repository.
    git rev-parse --is-inside-work-tree &>/dev/null; or return

    # Check for what branch we’re on.
    # Get the short symbolic ref. If HEAD isn’t a symbolic ref, get a
    # tracking remote branch or tag. Otherwise, get the
    # short SHA for the latest commit, or give up.
    set -l branchName (git symbolic-ref --quiet --short HEAD 2> /dev/null || \
		git describe --all --exact-match HEAD 2> /dev/null || \
		git rev-parse --short HEAD 2> /dev/null || \
		echo '(unknown)')

    # Early exit for Chromium & Blink repo, as the dirty check takes too long.
    # Thanks, @paulirish!
    # https://github.com/paulirish/dotfiles/blob/dd33151f/.bash_prompt#L110-L123
    set -l repoUrl (git config --get remote.origin.url)
    if echo "$repoUrl" | grep -q 'chromium/src.git'
        set s "$s*"
    else
        # Check for uncommitted changes in the index.
        if not git diff --quiet --ignore-submodules --cached
            set s "$s+"
        end
        # Check for unstaged changes.
        if not git diff-files --quiet --ignore-submodules --
            set s "$s!"
        end
        # Check for untracked files.
        if string length -q -- (git ls-files --others --exclude-standard)
            set s "$s?"
        end
        # Check for stashed files.
        if git rev-parse --verify refs/stash &>/dev/null
            set s "$s+\$"
        end
    end

    test -n "$s"; and set s " [$s]"

    set_color white
    printf ' on '
    set_color brmagenta # 5f5faf
    printf '%s' $branchName
    set_color blue
    printf '%s' $s
end

# Highlight the user name when logged in as root.
if test "$USER" = root
    set userStyle red
else
    set userStyle brred
    # d75f00
end

# Highlight the hostname when connected via SSH.
if test -n "$SSH_TTY"
    set hostStyle red
else
    set hostStyle yellow
end

function fish_prompt
    if not set -q VIRTUAL_ENV_DISABLE_PROMPT
        set -g VIRTUAL_ENV_DISABLE_PROMPT true
    end
    set_color $userStyle
    printf '%s' $USER
    set_color white
    printf ' at '

    set_color $hostStyle
    echo -n (prompt_hostname)
    set_color white
    printf ' in '

    set_color $fish_color_cwd
    printf '%s' (prompt_pwd)
    set_color white

    prompt_git
    set_color white

    # Line 2
    echo
    if test -n "$VIRTUAL_ENV"
        printf "(%s) " (set_color blue)(basename $VIRTUAL_ENV)(set_color white)
    end
    printf '↪ '
    set_color white
end
