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
printf '%s\n' "https://github.com/rtfpessoa/code-factory.git" > "$HOME/.code-factory/.git/fixture-origin"

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
      *" config --local --null --get-all remote.origin.url "*)
        [ -f "$2/.git/fixture-origin" ] || exit 1
        while IFS= read -r origin; do
          printf '%s\0' "$origin"
        done < "$2/.git/fixture-origin"
        ;;
      *" ls-remote "*)
        printf 'git-ls-remote terminal_prompt=%s ssh_command=%s ssh_auth_sock=%s args=%s\n' \
          "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" "${SSH_AUTH_SOCK:-}" "$*" >> "$TRACE_FILE"
        case " $* " in
          *" git@github.com:rtfpessoa/code-factory.git "*|\
          *" git@github.com:ddoghq-sandbox/code-factory.git "*|\
          *" git@ddoghq.github.com:ddoghq-sandbox/code-factory.git "*)
            if [ "${FAIL_SSH_PROBE:-0}" = "1" ]; then
              exit 1
            fi
            ;;
          *" https://github.com/rtfpessoa/code-factory.git "*)
            if [ "${FAIL_HTTPS_PROBE:-0}" = "1" ]; then
              exit 1
            fi
            ;;
          *" https://github.com/ddoghq-sandbox/code-factory.git "*)
            # The mirror follows FAIL_HTTPS_PROBE unless a case sets
            # FAIL_MIRROR_PROBE on its own.
            if [ "${FAIL_MIRROR_PROBE:-${FAIL_HTTPS_PROBE:-0}}" = "1" ]; then
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
        printf '%s\n' "${@: -2:1}" > "$clone_target/.git/fixture-origin"
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
assert_contains "$TRACE_FILE" "tmux -L dotfiles-install -f /dev/null start-server ; set-option -gw remain-on-exit failed ; new-session -d" \
  "foreground installation did not launch an isolated, fail-sticky tmux worker"
assert_contains "$TRACE_FILE" " -e PATH=" \
  "tmux worker did not forward PATH into the new session"
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

tmux_session_from_trace() {
  awk '$1 == "tmux" { for (i = 1; i <= NF; i++) if ($i == "-s") { print $(i + 1); exit } }' "$1"
}

first_session="$(tmux_session_from_trace "$TRACE_FILE")"
[ -n "$first_session" ] \
  || fail "could not parse tmux session name from trace"
: > "$TRACE_FILE"
JAVA_HOME=/tmp/fake-jdk25 bash "$REPO_DIR/install.sh"

assert_contains "$TRACE_FILE" "tmux -L dotfiles-install -f /dev/null start-server ; set-option -gw remain-on-exit failed ; new-session -d" \
  "an explicit rerun did not launch an isolated deferred update"
assert_contains "$TRACE_FILE" " -e JAVA_HOME=/tmp/fake-jdk25 " \
  "explicit rerun did not forward JAVA_HOME into the tmux session"
second_session="$(tmux_session_from_trace "$TRACE_FILE")"
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
bash "$REPO_DIR/install.sh" --foreground-only
assert_not_contains "$TRACE_FILE" "tmux " "foreground-only launched a detached worker"
assert_not_contains "$TRACE_FILE" "sudo apt-get" "foreground-only ran deferred tasks"

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

cp "$DOTFILES_STATE_DIR/install.status" "$FIXTURE_DIR/last-status"
status=0
FLOCK_HELD=1 bash "$REPO_DIR/install.sh" --deferred --require-run || status=$?
[ "$status" -eq 1 ] || fail "a required run must fail on contention"
cmp -s "$DOTFILES_STATE_DIR/install.status" "$FIXTURE_DIR/last-status" \
  || fail "a rejected run replaced the previous install status"

: > "$TRACE_FILE"
status=0
FAIL_CODE_FACTORY=1 bash "$REPO_DIR/install.sh" --deferred --require-run || status=$?
[ "$status" -eq 42 ] || fail "required run hid the code-factory exit status"
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
assert_contains "$TRACE_FILE" "git-ls-remote terminal_prompt=0 ssh_command=ssh -o BatchMode=yes -o ConnectTimeout=15 ssh_auth_sock=$FIXTURE_DIR/ssh-agent.sock args=-C \. ls-remote git@github.com:rtfpessoa/code-factory.git HEAD" \
  "code-factory did not probe the authenticated SSH transport"
assert_contains "$TRACE_FILE" "timeout 10 ssh-add -l" \
  "the ssh-add socket gate was not bounded"
assert_contains "$TRACE_FILE" "timeout 30 git -C \. ls-remote git@github.com:rtfpessoa/code-factory.git HEAD" \
  "the SSH ls-remote probe was not bounded"
assert_contains "$TRACE_FILE" "git-clone-config global= nosystem= terminal_prompt=0 ssh_command=ssh -o BatchMode=yes -o ConnectTimeout=15 ssh_auth_sock=$FIXTURE_DIR/ssh-agent.sock args=clone git@github.com:rtfpessoa/code-factory.git" \
  "code-factory did not clone over non-interactive authenticated SSH"
assert_not_contains "$TRACE_FILE" "https://github.com/.*/code-factory.git" \
  "code-factory selected HTTPS after SSH authentication succeeded"
: > "$TRACE_FILE"
FAIL_HTTPS_PROBE=1 install_code_factory
assert_contains "$TRACE_FILE" "ssh_auth_sock=$FIXTURE_DIR/ssh-agent.sock args=-C $HOME/.code-factory pull --ff-only git@github.com:rtfpessoa/code-factory.git main" \
  "the SSH update did not pull from the SSH URL"

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
assert_not_contains "$TRACE_FILE" "ls-remote https://" \
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
code_factory_ssh_available "$CODE_FACTORY_SSH_REPO" . \
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

# Datadog workspace HTTPS: the gh token cannot read the personal repository
# but can read the internal mirror. The clone falls back to the mirror
# instead of waiting for an agent, and the next update pulls from it too.
rm -rf "$HOME/.code-factory" "$HOME/.ssh/ssh_auth_sock"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
FAIL_HTTPS_PROBE=1 FAIL_MIRROR_PROBE=0 \
CODE_FACTORY_AUTH_WAIT_SECONDS=20 CODE_FACTORY_AUTH_POLL_SECONDS=1 \
  install_code_factory </dev/null >"$FIXTURE_DIR/wait-output" 2>&1 \
  || fail "the HTTPS mirror fallback did not install code-factory"
personal_line="$(grep -n 'ls-remote https://github.com/rtfpessoa/code-factory.git' "$TRACE_FILE" | head -1 | cut -d: -f1 || true)"
mirror_line="$(grep -n 'ls-remote https://github.com/ddoghq-sandbox/code-factory.git' "$TRACE_FILE" | head -1 | cut -d: -f1 || true)"
[ -n "$personal_line" ] && [ -n "$mirror_line" ] && [ "$personal_line" -lt "$mirror_line" ] \
  || fail "the personal repository was not probed before the mirror"
assert_contains "$TRACE_FILE" "timeout 30 git .* ls-remote https://github.com/ddoghq-sandbox/code-factory.git HEAD" \
  "the mirror HTTPS probe was not bounded"
assert_contains "$TRACE_FILE" "credential.https://github.com.useHttpPath=true ls-remote https://github.com/ddoghq-sandbox/code-factory.git HEAD" \
  "the mirror probe did not send the repository path to the credential helper"
assert_contains "$TRACE_FILE" "credential.https://github.com.useHttpPath=true clone https://github.com/ddoghq-sandbox/code-factory.git" \
  "the mirror clone did not send the repository path to the credential helper"
assert_contains "$TRACE_FILE" "url.https://github.com/ddoghq-sandbox/.insteadOf=https://github.com/ddoghq-sandbox/ .* clone https://github.com/ddoghq-sandbox/code-factory.git" \
  "the mirror clone did not override the broad GitHub URL rewrite"
assert_not_contains "$FIXTURE_DIR/wait-output" "Waiting up to" \
  "the mirror fallback still waited for authentication"
assert_contains "$TRACE_FILE" "code-factory-init" \
  "the mirror clone did not run initialization"
# Once the checkout exists, a newly available personal credential must not
# change its repository. SSH can update the mirror installed over HTTPS.
: > "$TRACE_FILE"
SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock" install_code_factory </dev/null \
  || fail "forwarded SSH did not update the existing mirror"
assert_contains "$TRACE_FILE" "git-ls-remote.*args=-C $HOME/.code-factory ls-remote git@github.com:ddoghq-sandbox/code-factory.git HEAD" \
  "SSH did not probe from the existing mirror checkout"
assert_contains "$TRACE_FILE" "pull --ff-only git@github.com:ddoghq-sandbox/code-factory.git main" \
  "SSH did not pull from the existing mirror"
assert_not_contains "$TRACE_FILE" "rtfpessoa/code-factory.git" \
  "SSH probed or updated from the personal repository for a mirror checkout"

# The platform's SSH alias must be honored, and the same repository must
# be used for HTTPS when that SSH route is not available.
origin_file="$HOME/.code-factory/.git/fixture-origin"
printf '%s\n' 'git@ddoghq.github.com:ddoghq-sandbox/code-factory.git' > "$origin_file"
: > "$TRACE_FILE"
SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock" install_code_factory </dev/null \
  || fail "the existing mirror's SSH alias was not usable"
assert_contains "$TRACE_FILE" "pull --ff-only git@ddoghq.github.com:ddoghq-sandbox/code-factory.git main" \
  "SSH did not use the existing mirror's alias"
: > "$TRACE_FILE"
SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock" FAIL_SSH_PROBE=1 install_code_factory </dev/null \
  || fail "HTTPS did not update the existing mirror after SSH failed"
assert_contains "$TRACE_FILE" "ls-remote git@ddoghq.github.com:ddoghq-sandbox/code-factory.git HEAD" \
  "SSH did not probe the existing mirror's alias"
assert_contains "$TRACE_FILE" "git-ls-remote.*args=-C $HOME/.code-factory .*ls-remote https://github.com/ddoghq-sandbox/code-factory.git HEAD" \
  "HTTPS did not probe from the existing mirror checkout"
assert_contains "$TRACE_FILE" "pull --ff-only https://github.com/ddoghq-sandbox/code-factory.git main" \
  "HTTPS did not pull from the existing mirror"
assert_not_contains "$TRACE_FILE" "rtfpessoa/code-factory.git" \
  "HTTPS probed or updated from the personal repository for a mirror checkout"

# A failed update must not run the post-install hook or initialization.
hook="$HOME/.config/dotfiles/code-factory-post-install.sh"
mkdir -p "$HOME/.config/dotfiles"
cat > "$hook" <<'EOF'
#!/usr/bin/env bash
printf 'code-factory-hook\n' >> "$TRACE_FILE"
exit "${TEST_HOOK_EXIT:-0}"
EOF
chmod +x "$hook"

: > "$TRACE_FILE"
if SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock" FAIL_SSH_PROBE=1 FAIL_MIRROR_PROBE=1 \
  install_code_factory </dev/null; then
  fail "unreachable mirror was updated from a different repository"
fi
assert_not_contains "$TRACE_FILE" 'rtfpessoa/code-factory.git\|git-pull-config\|code-factory-hook\|code-factory-init' \
  "unreachable mirror triggered a personal probe, update, hook, or init"

# Opting into a wait retains retries, but an authenticated pull failure is
# still a Git error, not an authentication timeout.
: > "$TRACE_FILE"
if SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock" FAIL_CODE_FACTORY_GIT=1 \
  CODE_FACTORY_AUTH_WAIT_SECONDS=1 CODE_FACTORY_AUTH_POLL_SECONDS=1 \
  install_code_factory </dev/null > "$FIXTURE_DIR/update-output" 2>&1; then
  fail "a repeatedly failing pull was reported as success"
fi
[ "$(grep -c '^git-pull-config' "$TRACE_FILE")" -eq 2 ] \
  || fail "the failing update did not honor the configured retry budget"
assert_not_contains "$TRACE_FILE" 'rtfpessoa/code-factory.git\|code-factory-hook\|code-factory-init' \
  "a failed pull switched repositories or ran the hook or init"
assert_not_contains "$FIXTURE_DIR/update-output" 'waiting for GitHub authentication' \
  "the failed pull was misreported as an authentication timeout"
assert_contains "$FIXTURE_DIR/update-output" 'See the Git error above.' \
  "the final update diagnostic did not point to the Git error"

for invalid_origin in unknown missing multiple; do
  case "$invalid_origin" in
    unknown) printf '%s\n' 'git@github.com:someone-else/code-factory.git' > "$origin_file" ;;
    missing) rm "$origin_file" ;;
    multiple)
      # A second, empty config value still makes the origin ambiguous.
      printf '%s\n' 'https://github.com/ddoghq-sandbox/code-factory.git' '' > "$origin_file"
      ;;
  esac
  : > "$TRACE_FILE"
  if install_code_factory </dev/null; then
    fail "invalid code-factory origin was accepted ($invalid_origin)"
  fi
  assert_not_contains "$TRACE_FILE" 'git-ls-remote\|git-pull-config\|code-factory-hook\|code-factory-init' \
    "invalid code-factory origin triggered a probe, update, hook, or init ($invalid_origin)"
done

# Neither HTTPS URL is readable: no transport, so no clone is attempted.
rm -rf "$HOME/.code-factory"
: > "$TRACE_FILE"
if FAIL_HTTPS_PROBE=1 install_code_factory </dev/null >"$FIXTURE_DIR/wait-output" 2>&1; then
  fail "code-factory was installed although no HTTPS URL was readable"
fi
assert_contains "$TRACE_FILE" "ls-remote https://github.com/ddoghq-sandbox/code-factory.git HEAD" \
  "the mirror was not tried after the personal repository failed"
assert_not_contains "$TRACE_FILE" "git-clone-config" \
  "a clone ran although no HTTPS URL was readable"

# Post-install hook: runs between the checkout and init.sh, only when the
# checkout exists, and never blocks the install on failure.
rm -rf "$HOME/.code-factory"
rm -f "$FIXTURE_DIR/ssh-add-calls" "$FIXTURE_DIR/clone-attempts"
: > "$TRACE_FILE"
TEST_HOOK_EXIT=1 install_code_factory </dev/null \
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

# --- platform-owned ~/.gitconfig -----------------------------------------
# The workspaces platform writes ~/.gitconfig itself and re-includes the user
# layer, so archiving it would drop the managed config and the wmux
# includeIfs. The git package must be stowed with ~/.gitconfig ignored,
# and a clean install must not generate standalone identity/signing layers.
rm -f "$HOME/.gitconfig" "$HOME/.gitconfig.datadog" "$HOME/.gitconfig.extras" \
  "$HOME/.gitconfig.machine" "$HOME/.gitconfig.personal-signing"
printf '# Managed by workspaces\n[user]\n\temail = managed@datadoghq.com\n[core]\n\thooksPath = /managed/hooks\n' > "$HOME/.gitconfig"
cp "$HOME/.gitconfig" "$FIXTURE_DIR/platform.before"
: > "$TRACE_FILE"
GIT_AUTHOR_NAME='Test User' GIT_AUTHOR_EMAIL='test@example.com' \
  GIT_SIGNING_KEY='ssh-ed25519 TEST' bash "$REPO_DIR/install.sh"
grep -qF -- '--ignore=^\.gitconfig$' "$TRACE_FILE" \
  || fail "the platform-owned ~/.gitconfig was not excluded from the git stow"
cmp -s "$HOME/.gitconfig" "$FIXTURE_DIR/platform.before" \
  || fail "the platform-owned ~/.gitconfig was modified"
[ ! -e "$HOME/.gitconfig.datadog" ] \
  || fail "the installer archived a platform-owned ~/.gitconfig"
for layer in extras machine personal-signing; do
  [ ! -e "$HOME/.gitconfig.$layer" ] \
    || fail "the installer generated a standalone $layer layer on a managed workspace"
done

# On first provision, the Workspaces wrapper runs before the platform creates
# its root. With the explicit handoff, the renderer must see no stow symlink
# to follow and the installer must not create standalone signing layers.
rm -f "$HOME/.gitconfig"
: > "$TRACE_FILE"
DOTFILES_WORKSPACES_MANAGED=1 GIT_AUTHOR_NAME='Test User' \
  GIT_AUTHOR_EMAIL='test@example.com' GIT_SIGNING_KEY='ssh-ed25519 TEST' \
  bash "$REPO_DIR/install.sh"
grep -qF -- '--ignore=^\.gitconfig$' "$TRACE_FILE" \
  || fail "the first Workspaces install did not reserve the root for the renderer"
[ ! -e "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ] \
  || fail "the installer created a Git root before the Workspaces renderer"
for layer in extras machine personal-signing; do
  [ ! -e "$HOME/.gitconfig.$layer" ] \
    || fail "the first Workspaces install generated a standalone $layer layer"
done

# A hand-written ~/.gitconfig keeps the historical archive-and-stow path.
rm -f "$HOME/.gitconfig" "$HOME/.gitconfig.datadog"
printf '[user]\n\temail = personal@example.com\n' > "$HOME/.gitconfig"
: > "$TRACE_FILE"
bash "$REPO_DIR/install.sh"
if grep -qF -- '--ignore=^\.gitconfig$' "$TRACE_FILE"; then
  fail "a hand-written ~/.gitconfig was excluded from the git stow"
fi
[ -f "$HOME/.gitconfig.datadog" ] \
  || fail "a hand-written ~/.gitconfig is no longer archived to ~/.gitconfig.datadog"
grep -q 'personal@example.com' "$HOME/.gitconfig.datadog" \
  || fail "the archived ~/.gitconfig lost its content"

# An existing stow symlink (a machine already running these dotfiles) is not a
# platform render and must not be archived: archiving it would follow the link
# and rewrite the tracked git/.gitconfig's signing sections through it.
rm -f "$HOME/.gitconfig" "$HOME/.gitconfig.datadog"
mkdir -p "$FIXTURE_DIR/tracked"
tracked="$FIXTURE_DIR/tracked/.gitconfig"
printf '[user]\n\tsigningkey = key::ssh-ed25519 TRACKED\n[gpg "ssh"]\n\tprogram = tracked-signer\n' > "$tracked"
cp "$tracked" "$FIXTURE_DIR/tracked.before"
ln -s "$tracked" "$HOME/.gitconfig"
: > "$TRACE_FILE"
bash "$REPO_DIR/install.sh"
[ -L "$HOME/.gitconfig" ] \
  || fail "an existing ~/.gitconfig stow symlink was replaced"
[ "$(readlink "$HOME/.gitconfig")" = "$tracked" ] \
  || fail "the ~/.gitconfig stow symlink was retargeted"
cmp -s "$tracked" "$FIXTURE_DIR/tracked.before" \
  || fail "the installer rewrote the tracked gitconfig through the stow symlink"
[ ! -e "$HOME/.gitconfig.datadog" ] \
  || fail "an existing stow symlink was archived to ~/.gitconfig.datadog"

printf 'PASS: foreground and deferred installations are isolated safely\n'
