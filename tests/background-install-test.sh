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
export HOME FAKE_BIN TRACE_FILE DOTFILES_STATE_DIR
export GIT_AUTHOR_NAME="Test User"
export GIT_AUTHOR_EMAIL="test@example.com"
export SHELL="/bin/bash"
unset SSH_AUTH_SOCK
mkdir -p "$HOME/.local/bin" "$HOME/.code-factory/.git" "$FAKE_BIN"

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
        printf 'git-ls-remote terminal_prompt=%s ssh_command=%s args=%s\n' \
          "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" "$*" >> "$TRACE_FILE"
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
        printf 'git-clone-config global=%s nosystem=%s terminal_prompt=%s ssh_command=%s args=%s\n' \
          "${GIT_CONFIG_GLOBAL:-}" "${GIT_CONFIG_NOSYSTEM:-}" \
          "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" "$*" >> "$TRACE_FILE"
        if [ "${FAIL_CODE_FACTORY_GIT:-0}" = "1" ]; then
          exit 1
        fi
        clone_target="${@: -1}"
        mkdir -p "$clone_target/.git"
        printf '%s\n' \
          '#!/usr/bin/env bash' \
          "printf 'code-factory-init\\n' >> \"\$TRACE_FILE\"" \
          > "$clone_target/init.sh"
        chmod +x "$clone_target/init.sh"
        ;;
      *" pull --ff-only "*)
        printf 'git-pull-config global=%s nosystem=%s terminal_prompt=%s ssh_command=%s args=%s\n' \
          "${GIT_CONFIG_GLOBAL:-}" "${GIT_CONFIG_NOSYSTEM:-}" \
          "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" "$*" >> "$TRACE_FILE"
        if [ "${FAIL_CODE_FACTORY_GIT:-0}" = "1" ]; then
          exit 1
        fi
        ;;
    esac
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

for command_name in uname id tmux git sudo stow curl vim nvim fc-cache fish cargo flock setsid nohup mcp-auth; do
  ln -s fake-command "$FAKE_BIN/$command_name"
done

export PATH="$FAKE_BIN:/usr/bin:/bin"

: > "$TRACE_FILE"
bash "$REPO_DIR/install.sh"

assert_contains "$TRACE_FILE" "stow -R" \
  "foreground installation did not stow dotfiles"
assert_contains "$TRACE_FILE" "tmux new-session" \
  "foreground installation did not launch a tmux worker"
assert_contains "$TRACE_FILE" "--deferred" \
  "tmux worker did not use the internal deferred mode"
assert_not_contains "$TRACE_FILE" "sudo apt-get" \
  "foreground installation ran heavyweight apt setup"
assert_not_contains "$TRACE_FILE" "code-factory-init" \
  "foreground installation ran code-factory synchronously"

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
assert_contains "$TRACE_FILE" "git-pull-config global= nosystem= terminal_prompt=0" \
  "code-factory update did not preserve Git config or disable prompts"
assert_contains "$TRACE_FILE" "url.https://github.com/rtfpessoa/" \
  "HTTPS code-factory update did not override the broad GitHub URL rewrite"
assert_not_contains "$TRACE_FILE" "global=/dev/null" \
  "code-factory update disabled the global Git config"
assert_not_contains "$TRACE_FILE" "nosystem=1" \
  "code-factory update disabled the system Git config"
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
[ "$apt_line" -lt "$code_factory_line" ] \
  || fail "code-factory ran before its apt dependencies"
[ "$code_factory_line" -lt "$vim_line" ] \
  || fail "code-factory did not run before Vim plugin setup"

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
assert_contains "$TRACE_FILE" "git-clone-config global= nosystem= terminal_prompt=0" \
  "code-factory clone did not preserve Git config or disable prompts"
assert_contains "$TRACE_FILE" "url.https://github.com/rtfpessoa/" \
  "HTTPS code-factory clone did not override the broad GitHub URL rewrite"
assert_not_contains "$TRACE_FILE" "global=/dev/null" \
  "code-factory clone disabled the global Git config"
assert_not_contains "$TRACE_FILE" "nosystem=1" \
  "code-factory clone disabled the system Git config"
assert_contains "$TRACE_FILE" "code-factory-init" \
  "fresh code-factory clone did not run initialization"

rm -rf "$HOME/.code-factory"
: > "$TRACE_FILE"
export SSH_AUTH_SOCK="$FIXTURE_DIR/ssh-agent.sock"
FAIL_HTTPS_PROBE=1 install_code_factory
assert_contains "$TRACE_FILE" "git-ls-remote terminal_prompt=0 ssh_command=ssh -o BatchMode=yes args=ls-remote git@github.com:rtfpessoa/code-factory.git HEAD" \
  "code-factory did not probe the authenticated SSH transport"
assert_contains "$TRACE_FILE" "git-clone-config global= nosystem= terminal_prompt=0 ssh_command=ssh -o BatchMode=yes args=clone git@github.com:rtfpessoa/code-factory.git" \
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
assert_contains "$TRACE_FILE" "git-clone-config global= nosystem= terminal_prompt=0" \
  "failed code-factory clone did not disable terminal prompts"
unset FAIL_SSH_PROBE FAIL_CODE_FACTORY_GIT SSH_AUTH_SOCK

mkdir -p "$HOME/.code-factory"
: > "$TRACE_FILE"
if install_code_factory; then
  fail "incomplete code-factory directory was treated as a valid checkout"
fi
assert_not_contains "$TRACE_FILE" "git-ls-remote" \
  "incomplete code-factory directory triggered a transport probe"

rm -f "$FAKE_BIN/mcp-auth"
rm -rf "$HOME/.code-factory"
: > "$TRACE_FILE"
if install_code_factory; then
  fail "code-factory continued without mcp-auth"
fi
assert_not_contains "$TRACE_FILE" "git-ls-remote" \
  "missing mcp-auth did not fail before transport probing"
assert_not_contains "$TRACE_FILE" "code-factory-init" \
  "missing mcp-auth still ran code-factory initialization"

printf 'PASS: foreground and deferred installations are isolated safely\n'
