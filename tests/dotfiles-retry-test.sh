#!/usr/bin/env bash
#
# dotfiles-retry-test.sh — deterministic coverage for dotfiles-retry.sh
# (the login/manual relauncher for the deferred dotfiles worker).
#
# The host running these tests may lack flock and setsid (macOS), so both
# are faked on PATH: flock honors an env knob for "lock held", tmux runs
# the launched command synchronously. The real lock semantics are exercised
# on real Linux workspaces (see the layer runbook).

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  grep -q -- "$pattern" "$file" || fail "$message"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -q -- "$pattern" "$file"; then
    fail "$message"
  fi
}

HOME="$FIXTURE_DIR/home"
FAKE_BIN="$FIXTURE_DIR/bin"
TRACE_FILE="$FIXTURE_DIR/trace"
STATE_DIR="$HOME/.local/state/dotfiles"
export HOME FAKE_BIN TRACE_FILE
unset SSH_AUTH_SOCK
mkdir -p "$HOME/.local/bin" "$FAKE_BIN" "$STATE_DIR" "$HOME/.dotfiles"

# The deferred worker stand-in: relaunching it is the entire point.
cat > "$HOME/.dotfiles/install.sh" <<'EOF'
#!/usr/bin/env bash
printf 'deferred-relaunch\n' >> "$TRACE_FILE"
EOF
chmod +x "$HOME/.dotfiles/install.sh"

# flock fake: `flock -n <file> <command...>` honors FLOCK_HELD.
cat > "$FAKE_BIN/flock" <<'EOF'
#!/usr/bin/env bash
if [ "${FLOCK_HELD:-0}" = "1" ]; then
  exit 1
fi
shift 2
exec "$@"
EOF
chmod +x "$FAKE_BIN/flock"

# tmux fake: run the new session's command synchronously (last two args).
cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "$TRACE_FILE"
bash "${@: -2}"
EOF
chmod +x "$FAKE_BIN/tmux"

export PATH="$FAKE_BIN:/usr/bin:/bin"
: > "$TRACE_FILE"

write_status() {
  # $1 state, $2 finished_at ("" for running)
  local finished="null"
  [ -n "${2:-}" ] && finished="\"$2\""
  printf '{"state":"%s","started_at":"2026-10-27T14:27:32Z","finished_at":%s,"exit_code":1,"revision":"x"}\n' \
    "$1" "$finished" > "$STATE_DIR/install.status"
}

# --- auto mode gating ------------------------------------------------------

# No status file at all: nothing to retry.
rm -f "$STATE_DIR/install.status"
: > "$TRACE_FILE"
bash "$REPO_DIR/dotfiles-retry.sh" --auto
assert_not_contains "$TRACE_FILE" "deferred-relaunch" \
  "--auto relaunched without a status file"

# A succeeded attempt is never retried.
write_status succeeded "2020-01-01T00:00:00Z"
: > "$TRACE_FILE"
bash "$REPO_DIR/dotfiles-retry.sh" --auto
assert_not_contains "$TRACE_FILE" "deferred-relaunch" \
  "--auto relaunched a succeeded installation"

# A failed attempt inside the cooldown window is left alone.
write_status failed "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
: > "$TRACE_FILE"
bash "$REPO_DIR/dotfiles-retry.sh" --auto
assert_not_contains "$TRACE_FILE" "deferred-relaunch" \
  "--auto relaunched a fresh failure inside the cooldown"

# A failed attempt outside the cooldown is retried.
write_status failed "2020-01-01T00:00:00Z"
: > "$TRACE_FILE"
bash "$REPO_DIR/dotfiles-retry.sh" --auto
assert_contains "$TRACE_FILE" "deferred-relaunch" \
  "--auto did not relaunch a cold failed installation"
assert_not_contains "$TRACE_FILE" "relaunching the deferred dotfiles worker" \
  "--auto printed the manual-mode banner"

# A stale "running" attempt with a free lock is healed.
write_status running ""
: > "$TRACE_FILE"
bash "$REPO_DIR/dotfiles-retry.sh" --auto
assert_contains "$TRACE_FILE" "deferred-relaunch" \
  "--auto did not heal a stale running attempt"

# A held lock suppresses the relaunch.
write_status failed "2020-01-01T00:00:00Z"
: > "$TRACE_FILE"
FLOCK_HELD=1 bash "$REPO_DIR/dotfiles-retry.sh" --auto
assert_not_contains "$TRACE_FILE" "deferred-relaunch" \
  "--auto relaunched while the deferred lock was held"

# Without a ~/.dotfiles checkout there is nothing to retry.
mv "$HOME/.dotfiles" "$HOME/.dotfiles.aside"
write_status failed "2020-01-01T00:00:00Z"
: > "$TRACE_FILE"
bash "$REPO_DIR/dotfiles-retry.sh" --auto
assert_not_contains "$TRACE_FILE" "deferred-relaunch" \
  "--auto relaunched without a dotfiles checkout"
mv "$HOME/.dotfiles.aside" "$HOME/.dotfiles"

# --- manual mode -----------------------------------------------------------

# Manual ignores the cooldown but still respects the lock.
write_status failed "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
: > "$TRACE_FILE"
out="$(bash "$REPO_DIR/dotfiles-retry.sh")"
printf '%s\n' "$out" >> "$TRACE_FILE"
assert_contains "$TRACE_FILE" "deferred-relaunch" \
  "manual mode did not relaunch inside the cooldown"
case "$out" in
  *relaunching*) : ;;
  *) fail "manual mode did not announce the relaunch" ;;
esac

: > "$TRACE_FILE"
export FLOCK_HELD=1
out="$(bash "$REPO_DIR/dotfiles-retry.sh")"
unset FLOCK_HELD
printf '%s\n' "$out" >> "$TRACE_FILE"
assert_not_contains "$TRACE_FILE" "deferred-relaunch" \
  "manual mode relaunched while the lock was held"
case "$out" in
  *already\ running*) : ;;
  *) fail "manual mode did not explain the held lock" ;;
esac

printf 'PASS: dotfiles-retry gating matches the contract\n'
