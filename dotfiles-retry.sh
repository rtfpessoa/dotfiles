#!/usr/bin/env bash
#
# dotfiles-retry — relaunch the deferred dotfiles worker after a failed or
# unfinished attempt. Installed to ~/.local/bin/dotfiles-retry by the
# generic installer; also invoked with --auto from the fish conf.d snippet
# on interactive Linux logins.
#
# Usage:
#   dotfiles-retry          manual: relaunch now (prints what it does)
#   dotfiles-retry --auto   login hook: relaunch only when the recorded
#                           status is not "succeeded", no worker holds the
#                           lock, and the last attempt finished at least
#                           15 minutes ago (churn guard against repeatedly
#                           relaunching full deferred runs on hosts whose
#                           failure is permanent)
#
# It never resets the repo and never stows; it only relaunches
# ~/.dotfiles/install.sh --deferred, whose own flock remains the source of
# truth for overlap. Guards on environment rather than uname so the same
# script works on workspaces and under the test harness: with no
# ~/.dotfiles checkout or no status file there is nothing to retry.

set -u

STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.local/state/dotfiles}"
STATUS_FILE="$STATE_DIR/install.status"
LOCK_FILE="$STATE_DIR/install.lock"
INSTALL_SCRIPT="$HOME/.dotfiles/install.sh"
COOLDOWN_SECONDS=900

[ -x "$INSTALL_SCRIPT" ] || exit 0
[ -f "$STATUS_FILE" ] || exit 0

auto=0
[ "${1:-}" = "--auto" ] && auto=1

status_line="$(cat "$STATUS_FILE" 2>/dev/null)" || exit 0
[ -n "$status_line" ] || exit 0

if [ "$auto" = 1 ]; then
  # Nothing to heal when the last attempt already succeeded.
  printf '%s\n' "$status_line" | grep -q '"state":"succeeded"' && exit 0

  # Churn guard: a fresh terminal on a host whose last attempt just failed
  # (or a stale "running" written moments ago) must not relaunch a full
  # deferred run — apt, chsh and friends — on every pane open.
  finished_at="$(printf '%s\n' "$status_line" | sed -n 's/.*"finished_at":"\([^"]*\)".*/\1/p')"
  if [ -n "$finished_at" ] && [ "$finished_at" != "null" ]; then
    finished_epoch="$(date -u -d "$finished_at" +%s 2>/dev/null \
      || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$finished_at" +%s 2>/dev/null \
      || true)"
    if [ -n "${finished_epoch:-}" ]; then
      now_epoch="$(date -u +%s)"
      if [ $((now_epoch - finished_epoch)) -lt "$COOLDOWN_SECONDS" ]; then
        exit 0
      fi
    fi
  fi
fi

# Lock test in command form: no file descriptor is held or leaked into the
# relaunched worker, whose own `flock -n 9` stays authoritative. Without
# flock (non-Linux dev hosts running the tests) fall back to treating a
# recorded "running" state as an active run.
if command -v flock >/dev/null 2>&1; then
  if ! flock -n "$LOCK_FILE" true 2>/dev/null; then
    echo "dotfiles-retry: a deferred dotfiles installation is already running; nothing to do"
    exit 0
  fi
else
  if printf '%s\n' "$status_line" | grep -q '"state":"running"'; then
    echo "dotfiles-retry: a deferred dotfiles installation appears to be running; nothing to do"
    exit 0
  fi
fi

if [ "$auto" = 0 ]; then
  echo "dotfiles-retry: relaunching the deferred dotfiles worker"
fi

if command -v tmux >/dev/null 2>&1; then
  session="dotfiles-retry-$(date -u '+%Y%m%d%H%M%S')-$$"
  tmux new-session -d -s "$session" "$INSTALL_SCRIPT" --deferred
  if [ "$auto" = 0 ]; then
    echo "dotfiles-retry: deferred worker running in tmux session $session (attach: tmux attach -t $session)"
  fi
else
  nohup setsid "$INSTALL_SCRIPT" --deferred >/dev/null 2>&1 </dev/null &
fi
