# rtfpessoa's dotfiles

![Screenshot of my shell prompt](https://i.imgur.com/EkEtphC.png)

> Sourced from [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles)

## Installation

**Warning:** If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don't want or need. Don't blindly use my settings unless you know what that entails. Use at your own risk!

### macOS (bootstrap script)

You can clone the repository wherever you want. (I like to keep it in `~/Projects/dotfiles`, with `~/dotfiles` as a symlink.) The bootstrapper script will pull in the latest version, copy the dotfiles to your home folder and install the brew and mise tools.

```bash
git clone https://github.com/rtfpessoa/dotfiles.git && cd dotfiles && bash bootstrap.sh
```

To update, `cd` into your local `dotfiles` repository and then:

```bash
bash bootstrap.sh
```

Alternatively, to update while avoiding the confirmation prompt:

```bash
bash bootstrap.sh -f
```

To update later on, just run that command again.

### Linux / Datadog Workspaces (install script)

For remote Linux environments (Datadog workspaces, containers, VMs), use the non-interactive installer:

```bash
git clone https://github.com/rtfpessoa/dotfiles.git && cd dotfiles && bash install.sh
```

This will:
- Stow dotfiles into `$HOME` (bash, zsh, fish, git, vim, oh-my-posh configs)
- Complete Git setup in the foreground
- Continue slower package, code-factory, plugin, and font installation in a detached tmux session

The script is fully non-interactive and idempotent — safe to run multiple times.
The foreground output prints the unique tmux session name and its attach command.
Its persistent log and status are available at
`~/.local/state/dotfiles/install.log` and `~/.local/state/dotfiles/install.status`.

To configure git credentials, set environment variables before running:

```bash
export GIT_AUTHOR_NAME="Your Name"
export GIT_AUTHOR_EMAIL="your@email.com"
bash install.sh
```

The deferred `code-factory` setup is non-interactive:
- It uses SSH when the workspace can access the repository through its SSH agent.
- Otherwise it uses HTTPS and preserves the configured Git credential helpers.
- If neither transport is authenticated, the installer fails with an actionable error instead of waiting for a prompt in tmux.

For HTTPS authentication, configure GitHub CLI credentials before running the installer:

```bash
gh auth login
gh auth setup-git
```

`code-factory` also requires the workspace-side `mcp-auth` binary to generate the Pi MCP configuration.
That binary and the browser bridge are provisioned by `ssaitch`, not by this repository.
Connect to a workspace through `ssaitch` before running the installer:

```bash
ssaitch <workspace>
```

If SSH uses 1Password, export its agent socket when launching `ssaitch`:

```bash
SSH_AUTH_SOCK="/path/to/1Password/agent.sock" ssaitch <workspace>
```

A raw `ssh <workspace>` session does not upload `mcp-auth` or configure the browser callback bridge.

### Cross-platform shell configs

Shell configuration files (aliases, functions, exports, PATH) are split into three variants:
- **Base files** (`.aliases`, `.functions`, `.exports`, `.path`) — cross-platform, sourced on all systems
- **`.darwin` files** (`.aliases.darwin`, etc.) — macOS-specific, sourced only on Darwin
- **`.linux` files** (`.aliases.linux`) — Linux-specific, sourced only on Linux

### Add custom commands without creating a new fork

If `~/.extra` exists, it will be sourced along with the other files. You can use this to add a few custom commands without the need to fork this entire repository, or to add commands you don't want to commit to a public repository.

My `~/.extra` looks something like this:

```bash
# Git credentials
# Not in the repository, to prevent people from accidentally committing under my name
GIT_AUTHOR_NAME="Mathias Bynens"
GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
git config --global user.name "$GIT_AUTHOR_NAME"
GIT_AUTHOR_EMAIL="mathias@mailinator.com"
GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git config --global user.email "$GIT_AUTHOR_EMAIL"
```

You could also use `~/.extra` to override settings, functions and aliases from my dotfiles repository. It's probably better to [fork this repository](https://github.com/rtfpessoa/dotfiles/fork) instead, though.
