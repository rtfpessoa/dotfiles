# Setup

# Base-image fish init, moved aside by the installer: newer workspace images
# ship a real ~/.config/fish/config.fish; source it back so image machinery
# keeps running underneath the dotfiles layer.
if test -r ~/.config/fish/config.fish.image
    source ~/.config/fish/config.fish.image
end

function fish_greeting
end

set -g fish_prompt_pwd_dir_length 1

source ~/.config/fish/theme.fish

source ~/.config/fish/functions.fish

source ~/.config/fish/init.fish

# Re-initialize Oh My Posh from the config (also clears its caches).
function __omp_reset
    oh-my-posh init fish --config ~/.config/omp/rtfpessoa.omp.json | source
    # Re-apply the fish-async-prompt wrapper (no-op without it): OMP init
    # redefines fish_prompt, which would otherwise drop the wrapper.
    functions -q __async_prompt_rewrap; and __async_prompt_rewrap
end

if type oh-my-posh &>/dev/null
	__omp_reset
end
