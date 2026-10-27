#!/usr/bin/env bash

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

wait_for_contains() {
  local file="$1"
  local pattern="$2"
  local attempts=0

  while ! grep -q -- "$pattern" "$file"; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 50 ]; then
      return 1
    fi
    sleep 0.01
  done
}

HOME="$FIXTURE_DIR/home"
FAKE_BIN="$FIXTURE_DIR/bin"
TRACE_FILE="$FIXTURE_DIR/trace"
DOTFILES_STATE_DIR="$HOME/.local/state/dotfiles"
export HOME FAKE_BIN TRACE_FILE DOTFILES_STATE_DIR FIXTURE_DIR
export GIT_AUTHOR_NAME="Test User"
export GIT_AUTHOR_EMAIL="test@example.com"
export SHELL="/bin/bash"
unset SSH_AUTH_SOCK
mkdir -p "$HOME/.local/bin" "$HOME/.code-factory/.git" "$FAKE_BIN"

# A live AF_UNIX socket standing in for a forwarded agent: transport
# probing checks socket liveness, so a regular file would not do. The
# ~/.ssh/ssh_auth_sock symlink (the workspaces ssh-agent-fixer path) is
# created per-case — with it present by default the deferred runs would
# take the SSH path and stop exercising HTTPS.
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
  "$FIXTURE_DIR/ssh-agent.sock"

# gh token fixture: present by default so the HTTPS fallback paths behave
# like an authenticated host; cases that need "no auth anywhere" remove it.
GH_TOKEN_FIXTURE="$FIXTURE_DIR/gh-token"
export GH_TOKEN_FIXTURE
printf 'gh-token-value\n' > "$GH_TOKEN_FIXTURE"

# The authentication wait is opt-in per case; the inherited default keeps
# the historical fail-fast behavior (the deferred worker sets its own
# default when it runs for real).
export CODE_FACTORY_AUTH_WAIT_SECONDS=0

for binary in oh-my-posh yq lazygit nvim ast-grep tree-sitter; do
  : > "$HOME/.local/bin/$binary"
done

cat > "$HOME/.code-factory/init.sh" <<'EOF'
#!/usr/bin/env bash
printf 'code-factory-init\n' >> "$TRACE_FILE"
if [ "${FAIL_CODE_FACTORY:-0}" = "1" ]; then
  exit 42
fi
EOF
chmod +x "$HOME/.code-factory/init.sh"

# Image-provided login machinery: a real ~/.bash_profile that must survive
# installation (moved to ~/.bash_profile.image and sourced by the repo's
# .bash_profile).
cat > "$HOME/.bash_profile" <<'EOF'
export FIXTURE_IMAGE_BASH=1
EOF

cat > "$FAKE_BIN/fake-command" <<'EOF'
#!/usr/bin/env bash
command_name="$(basename "$0")"
printf '%s %s\n' "$command_name" "$*" >> "$TRACE_FILE"

case "$command_name" in
  uname)
    if [ "${1:-}" = "-s" ]; then
      printf 'Linux\n'
    else
      printf 'x86_64\n'
    fi
    ;;
  id)
    printf '1000\n'
    ;;
  git)
    case " $* " in
      *" rev-parse HEAD "*)
        printf 'test-revision\n'
        ;;
      *" ls-remote "*)
        printf 'git-ls-remote terminal_prompt=%s ssh_command=%s ssh_auth_sock=%s args=%s\n' \
          "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" "${SSH_AUTH_SOCK:-}" "$*" >> "$TRACE_FILE"
        case " $* " in
          *" git@github.com:rtfpessoa/code-factory.git "*)
            if [ "${FAIL_SSH_PROBE:-0}" = "1" ]; then
              exit 1
            fi
            ;;
          *" https://github.com/rtfpessoa/code-factory.git "*)
            if [ "${FAIL_HTTPS_PROBE:-0}" = "1" ]; then
              exit 1
            fi
            ;;
        esac
        ;;
      *" clone "*)
        printf 'git-clone-config global=%s nosystem=%s terminal_prompt=%s ssh_command=%s ssh_auth_sock=%s args=%s\n' \
          "${GIT_CONFIG_GLOBAL:-}" "${GIT_CONFIG_NOSYSTEM:-}" \
          "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" "${SSH_AUTH_SOCK:-}" "$*" >> "$TRACE_FILE"
        clone_target="${@: -1}"
        if [ "${FAIL_CODE_FACTORY_GIT:-0}" = "1" ]; then
          # Simulate an interrupted clone: leave a partial directory so the
          # installer's cleanup path is genuinely exercised.
          mkdir -p "$clone_target/.git"
          exit 1
        fi
        if [ "${TEST_CLONE_FAIL_FIRST:-0}" = "1" ]; then
          attempts_file="$FIXTURE_DIR/clone-attempts"
          attempts=$(( $(cat "$attempts_file" 2>/dev/null || echo 0) + 1 ))
          printf '%s\n' "$attempts" > "$attempts_file"
          if [ "$attempts" -eq 1 ]; then
            mkdir -p "$clone_target/.git"
            exit 1
          fi
        fi
        mkdir -p "$clone_target/.git"
        printf '%s\n' \
          '#!/usr/bin/env bash' \
          "printf 'code-factory-init ssh_auth_sock=%s\\n' \"\${SSH_AUTH_SOCK:-}\" >> \"\$TRACE_FILE\"" \
          > "$clone_target/init.sh"
        chmod +x "$clone_target/init.sh"
        ;;
      *" pull --ff-only "*)
        printf 'git-pull-config global=%s nosystem=%s terminal_prompt=%s ssh_command=%s ssh_auth_sock=%s args=%s\n' \
          "${GIT_CONFIG_GLOBAL:-}" "${GIT_CONFIG_NOSYSTEM:-}" \
          "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" "${SSH_AUTH_SOCK:-}" "$*" >> "$TRACE_FILE"
        if [ "${FAIL_CODE_FACTORY_GIT:-0}" = "1" ]; then
          exit 1
        fi
        ;;
    esac
    ;;
  ssh-add)
    if [ "${TEST_SSH_ADD_FAILS:-0}" = "1" ]; then
      exit 1
    fi
    # Live socket (the fixture or its symlink) with keys: a call counter
    # makes "authentication appears after N polls" deterministic.
    [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK:-}" ] || exit 1
    calls_file="$FIXTURE_DIR/ssh-add-calls"
    calls=$(( $(cat "$calls_file" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$calls" > "$calls_file"
    [ "$calls" -gt "${TEST_SSH_ADD_SUCCEED_AFTER:-0}" ] || exit 1
    exit 0
    ;;
  gh)
    case "$1 $2" in
      "auth token")
        [ -f "${GH_TOKEN_FIXTURE:-}" ] && cat "${GH_TOKEN_FIXTURE:-}" || exit 1
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  timeout)
    # passthrough: probes run under `timeout` when the binary exists.
    # Record the wrapped invocation so bounded probes are assertable.
    printf 'timeout %s\n' "$*" >> "$TRACE_FILE"
    shift
    exec "$@"
    ;;
  curl)
    if [ "${FAIL_CURL:-0}" = "1" ]; then
      exit 1
    fi
    ;;
  sudo)
    # Consume piped input for commands such as sudo tee.
    if [ ! -t 0 ]; then
      command cat >/dev/null
    fi
    ;;
  flock)
    if [ "${FLOCK_HELD:-0}" = "1" ]; then
      exit 1
    fi
    ;;
esac
EOF
chmod +x "$FAKE_BIN/fake-command"

for command_name in uname id tmux git sudo stow curl vim nvim fc-cache fish cargo flock setsid nohup ssh-add gh timeout; do
  ln -s fake-command "$FAKE_BIN/$command_name"
done

export PATH="$FAKE_BIN:/usr/bin:/bin"

: > "$TRACE_FILE"
bash "$REPO_DIR/install.sh"

assert_contains "$TRACE_FILE" "stow -R" \
  "foreground installation did not stow dotfiles"

[ -f "$HOME/.bash_profile.image" ] \
  || fail "image ~/.bash_profile was not preserved as ~/.bash_profile.image"
grep -q 'FIXTURE_IMAGE_BASH' "$HOME/.bash_profile.image" \
  || fail "~/.bash_profile.image lost the image marker content"
[ ! -e "$HOME/.bash_profile" ] \
  || fail "~/.bash_profile was left behind, blocking stow"
assert_contains "$TRACE_FILE" "tmux new-session" \
  "foreground installation did not launch a tmux worker"
assert_contains "$TRACE_FILE" "--deferred" \
  "tmux worker did not use the internal deferred mode"
assert_not_contains "$TRACE_FILE" "sudo apt-get" \
  "foreground installation ran heavyweight apt setup"
assert_not_contains "$TRACE_FILE" "code-factory-init" \
  "foreground installation ran code-factory synchronously"
[ -x "$HOME/.local/bin/dotfiles-retry" ] \
  || fail "foreground installation did not install the retry helper"
[ -f "$REPO_DIR/fish/.config/fish/conf.d/90-dotfiles-retry.fish" ] \
  || fail "the fish conf.d retry hook is missing from the fish stow package"

first_session="$(awk '$1 == "tmux" && $2 == "new-session" {print $5}' "$TRACE_FILE")"
: > "$TRACE_FILE"
bash "$REPO_DIR/install.sh"

assert_contains "$TRACE_FILE" "tmux new-session" \
  "an explicit rerun did not launch a deferred update"
second_session="$(awk '$1 == "tmux" && $2 == "new-session" {print $5}' "$TRACE_FILE")"
[ "$first_session" != "$second_session" ] \
  || fail "explicit reruns reused a stale-prone tmux session name"

: > "$TRACE_FILE"
DOTFILES_DISABLE_TMUX=1 bash "$REPO_DIR/install.sh"

wait_for_contains "$TRACE_FILE" "nohup setsid" \
  || fail "foreground installation did not use the detached fallback without tmux"
assert_contains "$TRACE_FILE" "--deferred" \
  "detached fallback did not use the internal deferred mode"
assert_not_contains "$TRACE_FILE" "sudo apt-get" \
  "detached fallback ran heavyweight apt setup in the foreground"

: > "$TRACE_FILE"
bash "$REPO_DIR/install.sh" --deferred

assert_contains "$TRACE_FILE" "flock -n 9" \
  "deferred installation did not acquire its process lock"
assert_contains "$TRACE_FILE" "sudo apt-get update -qq" \
  "deferred installation did not run apt setup"
assert_contains "$TRACE_FILE" "code-factory-init" \
  "deferred installation did not run code-factory"
assert_contains "$TRACE_FILE" "git-pull-config global=/dev/null nosystem=1 terminal_prompt=0" \
  "code-factory update did not isolate the machine Git config or disable prompts"
assert_contains "$TRACE_FILE" "url.https://github.com/rtfpessoa/" \
  "HTTPS code-factory update did not override the broad GitHub URL rewrite"
assert_contains "$TRACE_FILE" "vim -es" \
  "deferred installation did not run Vim plugin setup"
assert_contains "$DOTFILES_STATE_DIR/install.status" '"state":"succeeded"' \
  "deferred success was not persisted"
assert_contains "$DOTFILES_STATE_DIR/install.status" '"revision":"test-revision"' \
  "dotfiles revision was not persisted"
assert_contains "$DOTFILES_STATE_DIR/install.log" "Deferred installation complete" \
  "deferred output was not persisted"

apt_line="$(grep -n 'sudo apt-get update -qq' "$TRACE_FILE" | cut -d: -f1)"
code_factory_line="$(grep -n 'code-factory-init' "$TRACE_FILE" | cut -d: -f1)"
vim_line="$(grep -n 'vim -es' "$TRACE_FILE" | cut -d: -f1)"
chsh_line="$(grep -n 'sudo chsh' "$TRACE_FILE" | cut -d: -f1)"
[ -n "$apt_line" ] || fail "deferred installation did not run apt setup"
[ "$apt_line" -lt "$code_factory_line" ] \
  || fail "code-factory ran before its apt dependencies"
[ "$apt_line" -lt "$vim_line" ] \
  || fail "vim setup ran before its apt dependencies"
[ "$vim_line" -lt "$code_factory_line" ] \
  || fail "code-factory did not run last, after the environment steps"
{ [ -n "$chsh_line" ] && [ "$chsh_line" -lt "$code_factory_line" ]; } \
  || fail "code-factory did not run after the default-shell step"

: > "$TRACE_FILE"
FLOCK_HELD=1 bash "$REPO_DIR/install.sh" --deferred
assert_contains "$TRACE_FILE" "flock -n 9" \
  "overlapping deferred installation did not check the lock"
assert_not_contains "$TRACE_FILE" "sudo apt-get" \
  "overlapping deferred installation continued after lock rejection"

: > "$TRACE_FILE"
if FAIL_CODE_FACTORY=1 bash "$REPO_DIR/install.sh" --deferred; then
  fail "deferred installation hid a code-factory failure"
fi
assert_contains "$DOTFILES_STATE_DIR/install.status" '"state":"failed"' \
  "deferred failure was not persisted"
assert_contains "$DOTFILES_STATE_DIR/install.status" '"exit_code":42' \
  "deferred failure exit code was not persisted"

rm -rf "$HOME/.code-factory"
: > "$TRACE_FILE"
SCRIPT_DIR="$REPO_DIR"
source "$REPO_DIR/lib.sh"
install_code_factory
assert_contains "$TRACE_FILE" "git-clone-config global=/dev/null nosystem=1 terminal_prompt=0" \
  "code-factory clone did not isolate the machine Git config or disable prompts"
assert_contains "$TRACE_FILE" "url.https://github.com/rtfpessoa/" \
  "HTTPS code-factory clone did not override the broad GitHub URL rewrite"
assert_contains "$TRACE_FILE" "code-factory-init" \
  "fresh code-factory clone did not run initialization"

rm -rf "$HOME/.code-factory"
: > "$TRACE_FILE"
export SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock"
FAIL_HTTPS_PROBE=1 install_code_factory
assert_contains "$TRACE_FILE" "git-ls-remote terminal_prompt=0 ssh_command=ssh -o BatchMode=yes -o ConnectTimeout=15 ssh_auth_sock=$FIXTURE_DIR/ssh-agent.sock args=ls-remote git@github.com:rtfpessoa/code-factory.git HEAD" \
  "code-factory did not probe the authenticated SSH transport"
assert_contains "$TRACE_FILE" "timeout 10 ssh-add -l" \
  "the ssh-add socket gate was not bounded"
assert_contains "$TRACE_FILE" "timeout 30 git ls-remote git@github.com:rtfpessoa/code-factory.git HEAD" \
  "the SSH ls-remote probe was not bounded"
assert_contains "$TRACE_FILE" "git-clone-config global= nosystem= terminal_prompt=0 ssh_command=ssh -o BatchMode=yes -o ConnectTimeout=15 ssh_auth_sock=$FIXTURE_DIR/ssh-agent.sock args=clone git@github.com:rtfpessoa/code-factory.git" \
  "code-factory did not clone over non-interactive authenticated SSH"
assert_not_contains "$TRACE_FILE" "https://github.com/rtfpessoa/code-factory.git" \
  "code-factory selected HTTPS after SSH authentication succeeded"

rm -rf "$HOME/.code-factory"
: > "$TRACE_FILE"
export FAIL_SSH_PROBE=1
export FAIL_CODE_FACTORY_GIT=1
if install_code_factory; then
  fail "code-factory authentication failure was hidden"
fi
assert_contains "$TRACE_FILE" "git-clone-config global=/dev/null nosystem=1 terminal_prompt=0" \
  "failed code-factory clone did not disable terminal prompts"
unset FAIL_SSH_PROBE FAIL_CODE_FACTORY_GIT SSH_AUTH_SOCK

mkdir -p "$HOME/.code-factory"
: > "$TRACE_FILE"
if install_code_factory; then
  fail "incomplete code-factory directory was treated as a valid checkout"
fi
assert_not_contains "$TRACE_FILE" "git-ls-remote" \
  "incomplete code-factory directory triggered a transport probe"
[ -d "$HOME/.code-factory" ] \
  || fail "an incomplete pre-existing code-factory directory was deleted"

rm -rf "$HOME/.code-factory"
: > "$TRACE_FILE"
if ! install_code_factory; then
  fail "missing mcp-auth blocked code-factory installation"
fi
assert_contains "$TRACE_FILE" "git-clone-config global=/dev/null nosystem=1 terminal_prompt=0" \
  "missing mcp-auth did not clone code-factory"
assert_contains "$TRACE_FILE" "code-factory-init" \
  "missing mcp-auth did not run code-factory initialization"

# --- auth knob parsing ---------------------------------------------------
# Invalid knobs fall back to their default and warn on stderr: the wait
# loop captures these functions' stdout, so a warning riding along on it
# poisons the integer comparison (the fail-fast/deadline checks silently
# stop matching). Leading zeros are decimal, not octal.
knob_warn="$FIXTURE_DIR/knob-warn"
default_wait="$(unset CODE_FACTORY_AUTH_WAIT_SECONDS; code_factory_auth_wait_seconds)"
[ "$default_wait" = "0" ] \
  || fail "the default wait knob is not 0 (got: $default_wait)"
default_poll="$(unset CODE_FACTORY_AUTH_POLL_SECONDS; code_factory_auth_poll_seconds)"
[ "$default_poll" = "10" ] \
  || fail "the default poll knob is not 10 (got: $default_poll)"
bad_wait="$(CODE_FACTORY_AUTH_WAIT_SECONDS=abc code_factory_auth_wait_seconds 2>"$knob_warn")"
[ "$bad_wait" = "0" ] \
  || fail "an invalid wait knob did not fall back to 0 (got: $bad_wait)"
grep -q "invalid CODE_FACTORY_AUTH_WAIT_SECONDS='abc'" "$knob_warn" \
  || fail "an invalid wait knob did not warn on stderr"
for bad_poll in abc 0 -1; do
  got="$(CODE_FACTORY_AUTH_POLL_SECONDS="$bad_poll" code_factory_auth_poll_seconds 2>"$knob_warn")"
  [ "$got" = "10" ] \
    || fail "invalid poll knob '$bad_poll' did not fall back to 10 (got: $got)"
  grep -q "invalid CODE_FACTORY_AUTH_POLL_SECONDS='$bad_poll'" "$knob_warn" \
    || fail "invalid poll knob '$bad_poll' did not warn on stderr"
done
octal_wait="$(CODE_FACTORY_AUTH_WAIT_SECONDS=08 code_factory_auth_wait_seconds 2>/dev/null)"
[ "$octal_wait" = "8" ] \
  || fail "a leading-zero wait knob was not normalized to decimal 8 (got: $octal_wait)"
octal_poll="$(CODE_FACTORY_AUTH_POLL_SECONDS=010 code_factory_auth_poll_seconds 2>/dev/null)"
[ "$octal_poll" = "10" ] \
  || fail "a leading-zero poll knob was not normalized to decimal 10 (got: $octal_poll)"

# --- authentication wait loop -------------------------------------------
# Fresh-workspace path: no transport at first (no agent, no gh token), then
# the agent appears (ssh-add starts answering) and the clone completes over
# SSH through the ssh-agent-fixer symlink — the socket the detached worker
# can actually see.
rm -rf "$HOME/.code-factory"
rm -f "$GH_TOKEN_FIXTURE" "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
mkdir -p "$HOME/.ssh"
ln -s "$FIXTURE_DIR/ssh-agent.sock" "$HOME/.ssh/ssh_auth_sock"
: > "$TRACE_FILE"
CODE_FACTORY_AUTH_WAIT_SECONDS=20 CODE_FACTORY_AUTH_POLL_SECONDS=1 \
TEST_SSH_ADD_SUCCEED_AFTER=2 \
  install_code_factory </dev/null >"$FIXTURE_DIR/wait-output" 2>&1 \
  || fail "the wait loop did not complete after authentication appeared"
assert_contains "$FIXTURE_DIR/wait-output" "Waiting up to 20s for authentication" \
  "the wait loop did not announce the missing authentication"
assert_not_contains "$TRACE_FILE" "args=ls-remote https://github.com/rtfpessoa/code-factory.git" \
  "unauthenticated HTTPS was probed against GitHub"
assert_contains "$TRACE_FILE" "ssh_auth_sock=$HOME/.ssh/ssh_auth_sock args=clone git@github.com:rtfpessoa/code-factory.git" \
  "the clone did not ride the fixer-symlink agent socket"
assert_contains "$TRACE_FILE" "code-factory-init ssh_auth_sock=$HOME/.ssh/ssh_auth_sock" \
  "init.sh did not run with the fixer-symlink agent socket"
unset TEST_SSH_ADD_SUCCEED_AFTER

# Deadline: no authentication ever appears.
rm -rf "$HOME/.code-factory" "$HOME/.ssh/ssh_auth_sock"
rm -f "$FIXTURE_DIR/ssh-add-calls"
: > "$TRACE_FILE"
if CODE_FACTORY_AUTH_WAIT_SECONDS=3 CODE_FACTORY_AUTH_POLL_SECONDS=1 \
  install_code_factory </dev/null >"$FIXTURE_DIR/wait-output" 2>&1; then
  fail "an exhausted authentication wait was reported as success"
fi
assert_contains "$FIXTURE_DIR/wait-output" "Timed out after 3s waiting for GitHub authentication" \
  "the exhausted wait did not produce the timeout error"
assert_contains "$FIXTURE_DIR/wait-output" "dotfiles-retry" \
  "the timeout error did not name the recovery command"
assert_not_contains "$TRACE_FILE" "code-factory-init" \
  "a failed wait still ran init.sh"

# An invalid wait knob fails fast like the 0 default instead of waiting
# forever: the captured value stays a clean integer.
rm -f "$FIXTURE_DIR/ssh-add-calls"
: > "$TRACE_FILE"
if CODE_FACTORY_AUTH_WAIT_SECONDS=abc \
  install_code_factory </dev/null >"$FIXTURE_DIR/wait-output" 2>&1; then
  fail "an invalid wait knob did not fail fast without a transport"
fi
assert_contains "$FIXTURE_DIR/wait-output" "no authenticated transport is available" \
  "an invalid wait knob did not take the fail-fast path"
assert_not_contains "$FIXTURE_DIR/wait-output" "Waiting up to" \
  "an invalid wait knob was treated as a wait budget"

# The unset (not just 0) wait knob keeps the library's fail-fast default:
# only the deferred worker opts into waiting by setting its own default.
: > "$TRACE_FILE"
if (unset CODE_FACTORY_AUTH_WAIT_SECONDS; install_code_factory </dev/null) \
  >"$FIXTURE_DIR/wait-output" 2>&1; then
  fail "the unset wait knob did not fail fast without a transport"
fi
assert_contains "$FIXTURE_DIR/wait-output" "no authenticated transport is available" \
  "the unset wait knob did not take the fail-fast path"
assert_not_contains "$FIXTURE_DIR/wait-output" "Waiting up to" \
  "the unset wait knob was treated as a wait budget"

# Immediate authentication: no wait is announced at all.
rm -rf "$HOME/.code-factory"
mkdir -p "$HOME/.ssh"
ln -s "$FIXTURE_DIR/ssh-agent.sock" "$HOME/.ssh/ssh_auth_sock"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
install_code_factory </dev/null \
  || fail "code-factory failed with a live agent and the fixture token"
assert_not_contains "$TRACE_FILE" "Waiting up to" \
  "a present authentication still announced a wait"
assert_contains "$TRACE_FILE" "ssh_auth_sock=$HOME/.ssh/ssh_auth_sock args=clone" \
  "an immediately present agent was not used for the clone"

# Interrupted clone: the first attempt fails, the partial directory is
# cleaned up, and the retry succeeds.
rm -rf "$HOME/.code-factory"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
TEST_CLONE_FAIL_FIRST=1 \
CODE_FACTORY_AUTH_WAIT_SECONDS=20 CODE_FACTORY_AUTH_POLL_SECONDS=1 \
  install_code_factory </dev/null \
  || fail "a transient clone failure was not retried"
clone_attempts="$(cat "$FIXTURE_DIR/clone-attempts")"
[ "$clone_attempts" = "2" ] \
  || fail "expected exactly two clone attempts, got $clone_attempts"
unset TEST_CLONE_FAIL_FIRST

# Permanent clone failure inside the wait: partial directories from the
# failed attempts must not survive the run.
rm -rf "$HOME/.code-factory"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
if FAIL_CODE_FACTORY_GIT=1 \
CODE_FACTORY_AUTH_WAIT_SECONDS=3 CODE_FACTORY_AUTH_POLL_SECONDS=1 \
  install_code_factory </dev/null; then
  fail "a permanently failing clone inside the wait was reported as success"
fi
[ ! -e "$HOME/.code-factory" ] \
  || fail "a partial clone survived a failed wait"
unset FAIL_CODE_FACTORY_GIT

# Live socket that lists no keys: no SSH probe leaves the machine at all.
rm -rf "$HOME/.code-factory"
rm -f "$FIXTURE_DIR/ssh-add-calls"
: > "$TRACE_FILE"
if TEST_SSH_ADD_FAILS=1 \
CODE_FACTORY_AUTH_WAIT_SECONDS=2 CODE_FACTORY_AUTH_POLL_SECONDS=1 \
  install_code_factory </dev/null; then
  fail "an agent without keys was treated as authenticated"
fi
assert_not_contains "$TRACE_FILE" "git-ls-remote" \
  "a keyless agent still triggered a network probe"
unset TEST_SSH_ADD_FAILS

# Deduplicated candidates: SSH_AUTH_SOCK pointing at the same socket as
# the fixer symlink probes exactly once.
rm -f "$FIXTURE_DIR/ssh-add-calls"
: > "$TRACE_FILE"
export SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock"
code_factory_ssh_available \
  || fail "a live duplicated agent socket was not accepted"
probe_count="$(grep -c 'git-ls-remote.*code-factory' "$TRACE_FILE" || true)"
[ "$probe_count" = "1" ] \
  || fail "expected one ls-remote probe for a deduplicated socket, got $probe_count"
unset SSH_AUTH_SOCK

# gh-authenticated HTTPS: the credential helper must reach the clone.
rm -rf "$HOME/.code-factory" "$HOME/.ssh/ssh_auth_sock"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
printf 'gh-token-value\n' > "$GH_TOKEN_FIXTURE"
: > "$TRACE_FILE"
install_code_factory </dev/null \
  || fail "the gh-authenticated HTTPS clone failed"
assert_contains "$TRACE_FILE" "credential.https://github.com.helper=!gh auth git-credential" \
  "the gh credential helper did not reach the HTTPS clone"
assert_contains "$TRACE_FILE" "clone https://github.com/rtfpessoa/code-factory.git" \
  "the clone did not use the HTTPS transport"
assert_contains "$TRACE_FILE" "timeout 30 git .* ls-remote https://github.com/rtfpessoa/code-factory.git HEAD" \
  "the HTTPS ls-remote probe was not bounded"

# Post-install hook: runs between the checkout and init.sh, only when the
# checkout exists, and never blocks the install on failure.
hook="$HOME/.config/dotfiles/code-factory-post-install.sh"
mkdir -p "$HOME/.config/dotfiles"
cat > "$hook" <<'EOF'
#!/usr/bin/env bash
printf 'code-factory-hook\n' >> "$TRACE_FILE"
EOF
chmod +x "$hook"
rm -rf "$HOME/.code-factory"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
install_code_factory </dev/null \
  || fail "a failing post-install hook was not made non-fatal"
hook_line="$(grep -n 'code-factory-hook' "$TRACE_FILE" | cut -d: -f1 || true)"
clone_line="$(grep -n 'git-clone-config' "$TRACE_FILE" | cut -d: -f1 || true)"
init_line="$(grep -n 'code-factory-init' "$TRACE_FILE" | cut -d: -f1 || true)"
[ -n "$hook_line" ] || fail "the post-install hook did not run"
[ "$clone_line" -lt "$hook_line" ] \
  || fail "the post-install hook ran before the clone completed"
[ "$hook_line" -lt "$init_line" ] \
  || fail "the post-install hook ran after init.sh"

# A clone failure must not run the hook.
rm -rf "$HOME/.code-factory"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
if FAIL_CODE_FACTORY_GIT=1 install_code_factory </dev/null; then
  fail "a failing clone with a hook present was reported as success"
fi
assert_not_contains "$TRACE_FILE" "code-factory-hook" \
  "the hook ran although the checkout failed"
unset FAIL_CODE_FACTORY_GIT

# A non-executable hook is silently skipped.
chmod -x "$hook"
rm -rf "$HOME/.code-factory"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
install_code_factory </dev/null \
  || fail "a non-executable hook broke the install"
assert_not_contains "$TRACE_FILE" "code-factory-hook" \
  "a non-executable hook ran anyway"
assert_not_contains "$TRACE_FILE" "post-install hook failed" \
  "a non-executable hook was reported as a failure"
rm -f "$hook"

# Deferred run with a failing environment step: code-factory still runs.
rm -rf "$HOME/.code-factory" "$HOME/.ssh/ssh_auth_sock"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
printf 'gh-token-value\n' > "$GH_TOKEN_FIXTURE"
: > "$TRACE_FILE"
if FAIL_CURL=1 bash "$REPO_DIR/install.sh" --deferred; then
  fail "the zsh plugin failure was hidden from the deferred status"
fi
assert_contains "$TRACE_FILE" "code-factory-init" \
  "a failing environment step prevented code-factory from running"
assert_contains "$DOTFILES_STATE_DIR/install.log" "zsh-history-substring-search setup failed; continuing with deferred setup" \
  "the zsh plugin failure did not warn and continue"
assert_contains "$DOTFILES_STATE_DIR/install.status" '"state":"failed"' \
  "the deferred failure was not persisted"
assert_contains "$DOTFILES_STATE_DIR/install.status" '"exit_code":1' \
  "the deferred step failure was not surfaced as the exit code"
unset FAIL_CURL

# The deferred worker's own wait default (1800s) engages when the knob is
# unset: the fresh-workspace scenario — no transport at provision time,
# the forwarded agent appearing a few polls in, clone over the fixer
# symlink — recovers without any explicit knob.
rm -rf "$HOME/.code-factory" "$HOME/.ssh/ssh_auth_sock"
rm -f "$GH_TOKEN_FIXTURE" "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
mkdir -p "$HOME/.ssh"
ln -s "$FIXTURE_DIR/ssh-agent.sock" "$HOME/.ssh/ssh_auth_sock"
: > "$TRACE_FILE"
env -u CODE_FACTORY_AUTH_WAIT_SECONDS \
  CODE_FACTORY_AUTH_POLL_SECONDS=1 TEST_SSH_ADD_SUCCEED_AFTER=2 \
  bash "$REPO_DIR/install.sh" --deferred \
  || fail "the deferred worker did not recover with its 1800s default"
assert_contains "$DOTFILES_STATE_DIR/install.log" "Waiting up to 1800s for authentication" \
  "the deferred worker did not wait with its own default"
assert_contains "$DOTFILES_STATE_DIR/install.status" '"state":"succeeded"' \
  "the recovered deferred run was not persisted as success"
assert_contains "$TRACE_FILE" "ssh_auth_sock=$HOME/.ssh/ssh_auth_sock args=clone git@github.com:rtfpessoa/code-factory.git" \
  "the deferred recovery clone did not ride the fixer-symlink agent socket"
unset TEST_SSH_ADD_SUCCEED_AFTER

printf 'PASS: foreground and deferred installations are isolated safely\n'
