#!/usr/bin/env bash
#
# lib.sh — Shared functions for bootstrap.sh and install.sh
#
# Source this file from your installer scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib.sh"
#

# --------------------------------------------------------------------------
# Logging helpers
# --------------------------------------------------------------------------
info() { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

CODE_FACTORY_DIR="$HOME/.code-factory"
CODE_FACTORY_REPO="https://github.com/rtfpessoa/code-factory.git"
CODE_FACTORY_SSH_REPO="git@github.com:rtfpessoa/code-factory.git"
CODE_FACTORY_HTTPS_PREFIX="https://github.com/rtfpessoa/"

# --------------------------------------------------------------------------
# Git config helpers
# --------------------------------------------------------------------------
remove_git_config_section_if_present() {
  local config_file="$1"
  local section="$2"
  local escaped_section="${section//./\\.}"
  local status

  if git config --file "$config_file" --get-regexp "^${escaped_section}\\.[^.]+$" >/dev/null; then
    git config --file "$config_file" --remove-section "$section"
  else
    status=$?
    if [ "$status" -eq 1 ]; then
      return 0
    fi
    return "$status"
  fi
}

# --------------------------------------------------------------------------
# wmux delegate-worktree signing/transport overrides
# --------------------------------------------------------------------------
# wmux (wmuxd) runs GitHub delegates as linked worktrees named
# "<branch>--<target12>" (first 12 hex chars of the wmux target id) under
# <repo>/.git/worktrees/. includeIf gitdir: conditions resolve to that real
# gitdir — the worktree's .git FILE path under /instance_storage never
# matches — so the two includeIf sections (re-)created by this function are
# the discriminator, validated against real delegate worktrees, plain
# worktrees, and main checkouts.
#
# Inside those worktrees there is no attached operator, so:
#   - commits are unsigned by design (gh.signing's materialized key goes
#     away when that wmuxd auth target is disabled; owners sign on merge),
#     and
#   - pushes ride HTTPS + the gh CLI credential helper (the forwarded
#     1Password agent socket is only alive while an operator is attached).
# ~/.gitconfig.wmux-unsigned carries both.
#
# ORDERING (critical): the includeIf sections are appended at the END of
# ~/.gitconfig, AFTER wmuxd's own includeIf hasconfig:remote.*.url lines —
# git resolves repeated keys last-writer-wins in file order, and the wmux
# git-auth layers set commit.gpgsign = true after the ~/.gitconfig.machine
# include. Remove-and-re-add at the end also self-heals the order if a
# later wmuxd bootstrap appends its lines below ours (git-doctor detects a
# stale order and re-runs this upsert).
upsert_wmux_unsigned_gitconfig() {
  local gitconfig="$HOME/.gitconfig"
  local unsigned="$HOME/.gitconfig.wmux-unsigned"
  local cond_home='gitdir:~/**/.git/worktrees/*--[0-9a-f]*'
  local cond_workspaces='gitdir:/workspaces/**/.git/worktrees/*--[0-9a-f]*'
  local tmp

  # stow makes ~/.gitconfig a symlink into the dotfiles clone; write to
  # the link target so the appends land in the clone file (the same file
  # wmuxd writes its own lines into) instead of through the symlink.
  if [ -L "$gitconfig" ]; then
    gitconfig="$(readlink -f "$gitconfig")"
  fi

  # Canonical content, rewritten on every run. Reverse rules ONLY
  # (SSH-form remotes -> HTTPS): identity rules cannot beat the Datadog
  # layers' https->ssh rewrites (equal-prefix ties resolve first-defined,
  # and those layers come earlier), while SSH-form remote strings are
  # matched only by these reverse rules. Git applies exactly one rewrite
  # (longest insteadOf prefix, no chaining), so the HTTPS result is not
  # re-rewritten back to SSH.
  cat > "$unsigned" <<'EOF'
# wmux delegate worktrees: no operator attached, no forwarded 1Password
# agent. Unsigned commits by design; HTTPS pushes via the gh CLI helper.
[commit]
	gpgsign = false

[url "https://github.com/"]
	insteadOf = git@github.com:
[url "https://github.com/DataDog/"]
	insteadOf = git@github.com:DataDog:
[url "https://github.com/ddoghq/"]
	insteadOf = git@ddoghq.github.com:ddoghq:
	insteadOf = git@github.com:ddoghq:
	insteadOf = ssh://git@github.com/ddoghq/
[url "https://github.com/ddoghq-sandbox/"]
	insteadOf = git@ddoghq.github.com:ddoghq-sandbox:
	insteadOf = git@github.com:ddoghq-sandbox:
EOF

  # Remove any existing copy of our two sections (idempotency +
  # re-positioning to the end), then append them fresh. Plain file
  # surgery, NOT `git config --file`: its lock-and-rename would replace a
  # symlinked ~/.gitconfig with a plain file, and --remove-section cannot
  # address these includeIf subsections at all (the key parser's last-dot
  # rule lands inside the ".git/worktrees" substring of the section name).
  if [ -f "$gitconfig" ]; then
    tmp="$(mktemp)"
    awk -v h1="[includeIf \"${cond_home}\"]" \
        -v h2="[includeIf \"${cond_workspaces}\"]" '
      $0 == h1 || $0 == h2 { skip = 1; next }
      /^\[/ { skip = 0 }
      skip == 0 { print }
    ' "$gitconfig" > "$tmp"
    cat "$tmp" > "$gitconfig"
    rm -f "$tmp"
    # Guarantee a trailing newline before appending.
    if [ -n "$(tail -c 1 "$gitconfig")" ]; then
      printf '\n' >> "$gitconfig"
    fi
  fi
  printf '\n[includeIf "%s"]\n\tpath = ~/.gitconfig.wmux-unsigned\n' "$cond_home" >> "$gitconfig"
  printf '[includeIf "%s"]\n\tpath = ~/.gitconfig.wmux-unsigned\n' "$cond_workspaces" >> "$gitconfig"
}

# --------------------------------------------------------------------------
# Stow dotfiles
# --------------------------------------------------------------------------
# Usage: install_dotfiles dir1 dir2 dir3 ...
# If no arguments, stows all directories.
install_dotfiles() {
  local stow_dirs=("$@")
  if [ ${#stow_dirs[@]} -eq 0 ]; then
    stow_dirs=("apps" "bash" "common-sh" "fish" "git" "nvim" "oh-my-posh" "vim" "zsh")
  fi

  for stow_dir in "${stow_dirs[@]}"; do
    stow -R -d "$SCRIPT_DIR" -t "$HOME" "$stow_dir"
  done
}

# --------------------------------------------------------------------------
# Vim/Neovim plugin setup
# --------------------------------------------------------------------------
setup_vim() {
  if command -v vim &>/dev/null; then
    vim -es '+PlugInstall --sync' +qa </dev/null 2>/dev/null || true
  fi

  if command -v nvim &>/dev/null; then
    nvim --headless '+Lazy! sync' +qa 2>/dev/null || true
  fi
}

# --------------------------------------------------------------------------
# Font installation
# --------------------------------------------------------------------------
install_font() {
  local dest_dir="$1"
  local font_src="$SCRIPT_DIR/fonts/FiraCode-Retina.ttf"
  if [ -f "$font_src" ]; then
    mkdir -p "$dest_dir"
    cp -f "$font_src" "$dest_dir/FiraCode-Retina.ttf"
  fi
}

setup_fonts() {
  case "$(uname -s)" in
    Darwin)
      install_font ~/Library/Fonts
      ;;
    *)
      install_font ~/.local/share/fonts/
      if command -v fc-cache &>/dev/null; then
        fc-cache -f 2>/dev/null || true
      fi
      ;;
  esac
}

# --------------------------------------------------------------------------
# AI coding configs (code-factory)
# --------------------------------------------------------------------------
code_factory_git_https() {
  # Isolate from the machine's global and system config: the Datadog
  # git-config-tool layer rewrites https://github.com/ to git@github.com:
  # with unusable signing pubkeys, which turns this HTTPS fallback into a
  # broken SSH attempt on workspaces (same rationale as the workspaces
  # dotfiles layer's dotfiles_git helper).
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_TERMINAL_PROMPT=0 \
    git -c "url.${CODE_FACTORY_HTTPS_PREFIX}.insteadOf=${CODE_FACTORY_HTTPS_PREFIX}" "$@"
}

code_factory_git_ssh() {
  GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    git "$@"
}

code_factory_ssh_available() {
  [ -n "${SSH_AUTH_SOCK:-}" ] || return 1
  code_factory_git_ssh ls-remote "$CODE_FACTORY_SSH_REPO" HEAD >/dev/null 2>&1
}

code_factory_transport() {
  if code_factory_ssh_available; then
    printf 'ssh\n'
  else
    printf 'https\n'
  fi
}

code_factory_checkout_is_valid() {
  [ -e "$CODE_FACTORY_DIR/.git" ] || return 1
  git -C "$CODE_FACTORY_DIR" rev-parse HEAD >/dev/null 2>&1
}

code_factory_access_error() {
  local operation="$1"
  local transport="$2"

  error "Unable to ${operation} code-factory over ${transport}."
  error "GitHub authentication must be available non-interactively."
  if [ "$transport" = "ssh" ]; then
    error "Provide a working SSH agent/key for git@github.com or configure HTTPS Git credentials."
  else
    error "Configure HTTPS Git credentials, for example with: gh auth login && gh auth setup-git"
  fi
}

install_code_factory() {
  local transport

  # mcp-auth is not a prerequisite: code-factory's init.sh auto-installs it
  # (fetching ddoghq/ssaitch and building the binary) whenever it is missing.

  if [ -e "$CODE_FACTORY_DIR" ] && ! code_factory_checkout_is_valid; then
    error "code-factory directory is not a complete Git checkout: $CODE_FACTORY_DIR"
    error "Remove the incomplete directory and rerun the installer."
    return 1
  fi

  transport="$(code_factory_transport)"
  if [ -d "$CODE_FACTORY_DIR" ]; then
    info "Updating code-factory over $transport..."
    if [ "$transport" = "ssh" ]; then
      if ! code_factory_git_ssh \
        -c "remote.origin.url=$CODE_FACTORY_SSH_REPO" \
        -C "$CODE_FACTORY_DIR" pull --ff-only origin main; then
        code_factory_access_error update "$transport"
        return 1
      fi
    elif ! code_factory_git_https \
      -c "remote.origin.url=$CODE_FACTORY_REPO" \
      -C "$CODE_FACTORY_DIR" pull --ff-only origin main; then
      code_factory_access_error update "$transport"
      return 1
    fi
  else
    info "Cloning code-factory over $transport..."
    if [ "$transport" = "ssh" ]; then
      if ! code_factory_git_ssh clone "$CODE_FACTORY_SSH_REPO" "$CODE_FACTORY_DIR"; then
        code_factory_access_error clone "$transport"
        return 1
      fi
    elif ! code_factory_git_https clone "$CODE_FACTORY_REPO" "$CODE_FACTORY_DIR"; then
      code_factory_access_error clone "$transport"
      return 1
    fi
  fi

  info "Running code-factory init..."
  bash "$CODE_FACTORY_DIR/init.sh"
}
