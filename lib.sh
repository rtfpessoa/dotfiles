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
  # Isolate from the machine's global and system config: the global
  # gitconfig rewrites https://github.com/ to git@github.com:, which turns
  # this HTTPS fallback into an SSH attempt that detached installs (no
  # agent) cannot serve — and that bootstrap-time workspaces may not have
  # materialized keys for yet (same rationale as the workspaces dotfiles
  # layer's dotfiles_git helper).
  # The isolation also drops the credential helper `gh auth setup-git`
  # writes, so hand gh's helper to git explicitly: this branch is only
  # reachable after `gh auth token` produced a token, and without the
  # helper that token would never reach the HTTPS request.
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_TERMINAL_PROMPT=0 \
    git -c "url.${CODE_FACTORY_HTTPS_PREFIX}.insteadOf=${CODE_FACTORY_HTTPS_PREFIX}" \
        -c credential.helper= \
        -c "credential.https://github.com.helper=!gh auth git-credential" "$@"
}

bounded() {
  # bounded <seconds> <command...> — cap a probe's runtime when the
  # coreutils timeout binary is available (a half-dead forwarded agent or
  # a blackholed connection must not hang the deferred worker).
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

code_factory_git_ssh() {
  GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=15" \
    git "$@"
}

# Agent socket candidates for detached runs, deduped. The deferred worker's
# own SSH_AUTH_SOCK is empty or stale at provision time (no connection has
# forwarded an agent yet); the workspaces ssh-agent-fixer symlink
# ~/.ssh/ssh_auth_sock is re-pointed at the newest agent socket on every SSH
# connection, so it is the path that keeps working across connections.
code_factory_agent_sockets() {
  local sock seen=""
  for sock in "${SSH_AUTH_SOCK:-}" "$HOME/.ssh/ssh_auth_sock"; do
    [ -n "$sock" ] || continue
    [ -e "$sock" ] || continue
    case ":$seen:" in
      *":$sock:"*) continue ;;
    esac
    seen="$seen:$sock"
    printf '%s\n' "$sock"
  done
}

# True when the candidate socket lists at least one key: gate the network
# probe so the wait loop stays off github.com while nothing is forwarded.
# Conservative when ssh-add is missing (candidate is skipped).
code_factory_socket_lists_keys() {
  SSH_AUTH_SOCK="$1" bounded 10 ssh-add -l >/dev/null 2>&1
}

# Bounded network probe against the repo over SSH for one agent socket.
code_factory_ssh_probe() {
  SSH_AUTH_SOCK="$1" \
  GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15" \
    bounded 30 git ls-remote "$CODE_FACTORY_SSH_REPO" HEAD >/dev/null 2>&1
}

# Sets CODE_FACTORY_SSH_SOCK to the working agent socket on success. Must
# be called without a subshell (a `$(...)` capture would drop the global —
# today's transport picker had exactly that bug) so the chosen socket can
# be exported to the clone and to init.sh, which fetches ddoghq repos over
# SSH itself.
code_factory_ssh_available() {
  local sock

  CODE_FACTORY_SSH_SOCK=""

  if [ "$(uname -s)" != "Linux" ]; then
    # macOS bootstrap path: keep the historical check. The agent may be
    # reachable only through ssh_config IdentityAgent (1Password), and
    # $SSH_AUTH_SOCK may point at a proxy socket (herdr) that ssh-add -l
    # semantics do not describe; do not gate on ssh-add here.
    [ -n "${SSH_AUTH_SOCK:-}" ] || return 1
    CODE_FACTORY_SSH_SOCK="$SSH_AUTH_SOCK"
    if code_factory_git_ssh ls-remote "$CODE_FACTORY_SSH_REPO" HEAD >/dev/null 2>&1; then
      return 0
    fi
    CODE_FACTORY_SSH_SOCK=""
    return 1
  fi

  while IFS= read -r sock; do
    code_factory_socket_lists_keys "$sock" || continue
    if code_factory_ssh_probe "$sock"; then
      CODE_FACTORY_SSH_SOCK="$sock"
      return 0
    fi
  done < <(code_factory_agent_sockets)

  return 1
}

# HTTPS is only attempted when gh holds a token locally (cheap, no network)
# AND the config-isolated ls-remote proves the credential works. The token
# gate keeps unauthenticated requests off github.com's rate limits.
code_factory_https_available() {
  command -v gh >/dev/null 2>&1 || return 1
  [ -n "$(gh auth token 2>/dev/null)" ] || return 1
  code_factory_git_https ls-remote "$CODE_FACTORY_REPO" HEAD >/dev/null 2>&1
}

# Sets CODE_FACTORY_TRANSPORT (ssh|https|none) and, for ssh, the
# CODE_FACTORY_SSH_SOCK global. No subshell capture: callers read the
# globals directly.
select_code_factory_transport() {
  CODE_FACTORY_TRANSPORT="none"
  if code_factory_ssh_available; then
    CODE_FACTORY_TRANSPORT="ssh"
    return 0
  fi
  if code_factory_https_available; then
    CODE_FACTORY_TRANSPORT="https"
    return 0
  fi
  return 1
}

# Any live agent socket listing keys (Linux): drives the probe backoff when
# an agent is present but cannot read the repo (key not authorized), so a
# stuck agent does not generate a probe storm.
code_factory_any_agent_lists_keys() {
  local sock
  [ "$(uname -s)" = "Linux" ] || return 1
  while IFS= read -r sock; do
    code_factory_socket_lists_keys "$sock" && return 0
  done < <(code_factory_agent_sockets)
  return 1
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

code_factory_wait_timeout_error() {
  error "Timed out after ${1}s waiting for GitHub authentication (SSH agent or gh login)."
  error "Connect with agent forwarding (or run gh auth login), then retry with: dotfiles-retry"
  error "On Datadog workspaces the platform equivalent is: workspaces dotfiles sync"
}

# Wait/poll knobs. The default wait is 0 (fail fast): every foreground and
# interactive caller — including the macOS bootstrap — keeps today's
# behavior; only the detached deferred worker opts into waiting by setting
# CODE_FACTORY_AUTH_WAIT_SECONDS itself.
code_factory_auth_wait_seconds() {
  local value="${CODE_FACTORY_AUTH_WAIT_SECONDS:-0}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    warn "invalid CODE_FACTORY_AUTH_WAIT_SECONDS='${CODE_FACTORY_AUTH_WAIT_SECONDS}'; using 0"
    value=0
  fi
  printf '%s\n' "$value"
}

code_factory_auth_poll_seconds() {
  local value="${CODE_FACTORY_AUTH_POLL_SECONDS:-10}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
    warn "invalid CODE_FACTORY_AUTH_POLL_SECONDS='${CODE_FACTORY_AUTH_POLL_SECONDS}'; using 10"
    value=10
  fi
  printf '%s\n' "$value"
}

# Clone or update the checkout over the selected transport. On a failed
# clone the partial target is removed so a later attempt starts clean —
# only reached when the directory did not exist before this run (a
# pre-existing incomplete directory fails closed in install_code_factory
# before the loop, and a valid checkout is never deleted).
run_code_factory_checkout() {
  local transport="$1"

  if [ -d "$CODE_FACTORY_DIR" ]; then
    info "Updating code-factory over $transport..."
    if [ "$transport" = "ssh" ]; then
      SSH_AUTH_SOCK="$CODE_FACTORY_SSH_SOCK" \
        code_factory_git_ssh -c "remote.origin.url=$CODE_FACTORY_SSH_REPO" \
          -C "$CODE_FACTORY_DIR" pull --ff-only origin main
    else
      code_factory_git_https -c "remote.origin.url=$CODE_FACTORY_REPO" \
        -C "$CODE_FACTORY_DIR" pull --ff-only origin main
    fi
  else
    info "Cloning code-factory over $transport..."
    if [ "$transport" = "ssh" ]; then
      SSH_AUTH_SOCK="$CODE_FACTORY_SSH_SOCK" \
        code_factory_git_ssh clone "$CODE_FACTORY_SSH_REPO" "$CODE_FACTORY_DIR" \
        || { rm -rf "$CODE_FACTORY_DIR"; return 1; }
    else
      code_factory_git_https clone "$CODE_FACTORY_REPO" "$CODE_FACTORY_DIR" \
        || { rm -rf "$CODE_FACTORY_DIR"; return 1; }
    fi
  fi
}

# Layer extension point: the fixed path below is the only seam from the
# generic repo to machine-specific setup. The workspaces dotfiles layer
# installs a script there to pin the wmux signing include onto the fresh
# ~/.code-factory checkout. Depends only on the checkout, so it runs right
# after clone/pull — before init.sh and regardless of init.sh's fate.
run_code_factory_post_install_hook() {
  local hook="$HOME/.config/dotfiles/code-factory-post-install.sh"

  if [ -x "$hook" ]; then
    info "Running code-factory post-install hook..."
    if ! bash "$hook" </dev/null; then
      warn "code-factory post-install hook failed; continuing"
    fi
  fi
}

install_code_factory() {
  local wait_seconds poll_seconds waited effective_poll useless_probes
  local operation

  # mcp-auth is not a prerequisite: code-factory's init.sh auto-installs it
  # (fetching ddoghq/ssaitch and building the binary) whenever it is missing.

  if [ -e "$CODE_FACTORY_DIR" ] && ! code_factory_checkout_is_valid; then
    error "code-factory directory is not a complete Git checkout: $CODE_FACTORY_DIR"
    error "Remove the incomplete directory and rerun the installer."
    return 1
  fi

  wait_seconds="$(code_factory_auth_wait_seconds)"
  poll_seconds="$(code_factory_auth_poll_seconds)"
  waited=0
  useless_probes=0

  while :; do
    select_code_factory_transport

    if [ "$CODE_FACTORY_TRANSPORT" != "none" ]; then
      if run_code_factory_checkout "$CODE_FACTORY_TRANSPORT"; then
        run_code_factory_post_install_hook
        info "Running code-factory init..."
        # init.sh runs once, never retried: its failures are not auth
        # failures (a broken build would otherwise rebuild for the whole
        # wait budget). Its exit status propagates unchanged.
        SSH_AUTH_SOCK="$CODE_FACTORY_SSH_SOCK" \
          bash "$CODE_FACTORY_DIR/init.sh" </dev/null
        return $?
      fi

      if [ "$wait_seconds" -eq 0 ]; then
        operation="clone"
        [ -d "$CODE_FACTORY_DIR" ] && operation="update"
        code_factory_access_error "$operation" "$CODE_FACTORY_TRANSPORT"
        return 1
      fi
      warn "code-factory fetch failed; retrying while the authentication budget lasts"
    else
      if [ "$wait_seconds" -eq 0 ]; then
        error "Unable to clone code-factory: no authenticated transport is available."
        error "GitHub authentication must be available non-interactively."
        error "Provide a working SSH agent/key for git@github.com, or configure HTTPS credentials with: gh auth login && gh auth setup-git"
        return 1
      fi
      if [ "$waited" -eq 0 ]; then
        info "No GitHub authentication available yet (no SSH agent, no gh token)"
        info "Waiting up to ${wait_seconds}s for authentication (agent forwarding or gh login)..."
      fi
    fi

    if [ "$waited" -ge "$wait_seconds" ]; then
      code_factory_wait_timeout_error "$wait_seconds"
      return 1
    fi

    # Backoff: when an agent lists keys but still cannot read the repo
    # (unauthorized key), stretch the poll instead of probing every round.
    effective_poll="$poll_seconds"
    if [ "$CODE_FACTORY_TRANSPORT" = "none" ] \
       && code_factory_any_agent_lists_keys; then
      useless_probes=$((useless_probes + 1))
      effective_poll=$((poll_seconds * useless_probes))
      [ "$effective_poll" -gt 60 ] && effective_poll=60
    else
      useless_probes=0
    fi

    sleep "$effective_poll"
    waited=$((waited + effective_poll))

    if [ "$waited" -ge 60 ] && [ $((waited % 60)) -lt "$effective_poll" ]; then
      info "Still waiting for GitHub authentication (${waited}s/${wait_seconds}s)..."
    fi
  done
}
