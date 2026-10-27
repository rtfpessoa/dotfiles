# Deferred dotfiles install retry (Linux workspaces): when the recorded
# deferred installation did not succeed and no worker is running, relaunch
# it — fresh workspaces provision the deferred run before any SSH
# connection forwards an agent, so a failed code-factory clone heals itself
# on the first interactive login. See ~/.local/bin/dotfiles-retry
# (dotfiles-retry.sh in the dotfiles repo) for the gating rules.
if status is-interactive; and test (uname -s) = Linux; and test -x "$HOME/.local/bin/dotfiles-retry"
    "$HOME/.local/bin/dotfiles-retry" --auto >/dev/null 2>&1
end
