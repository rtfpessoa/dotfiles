#!/usr/bin/env bash
#
# tests/wmux-unsigned-test.sh — verifies upsert_wmux_unsigned_gitconfig:
#   - idempotent (no duplicated includeIf sections across re-runs)
#   - symlink-preserving (writes the stow target, never the symlink itself)
#   - includeIf sections land at the END of ~/.gitconfig (after wmux-style
#     hasconfig lines) and win the last-writer-wins race against a
#     git-auth-style layer setting commit.gpgsign = true
#   - scoped: delegate-shaped worktrees (name *--<hex12>) get
#     commit.gpgsign = false from ~/.gitconfig.wmux-unsigned; main checkouts
#     and plain worktrees keep signing
#   - reverse URL rules (SSH-form remotes -> HTTPS) reach the effective
#     delegate-worktree config
#
# The fixture mirrors the live workspace chain: ~/.gitconfig is a stow
# symlink into a clone, includes ~/.gitconfig.machine, then wmux-style
# includeIf hasconfig lines pulling a git-auth stub that sets
# commit.gpgsign = true (the observed live order: git-auth expands after
# the machine include).

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$TEST_DIR/../lib.sh"

FIXTURE_ROOT="$(mktemp -d)"
# gitdir: patterns match the REALPATH of the worktree's gitdir (git resolves
# symlinks in $GIT_DIR before matching); on macOS mktemp dirs live behind
# the /var -> /private/var symlink, so pin the fixture to its physical path
# for the ~-based pattern and the resolved gitdir to line up.
FIXTURE_ROOT="$(cd "$FIXTURE_ROOT" && pwd -P)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

home="$FIXTURE_ROOT/home"
clone_git="$FIXTURE_ROOT/dotfiles-clone/git"
stub="$FIXTURE_ROOT/gitauth/gitconfig-ddoghq"
mkdir -p "$home" "$clone_git" "$(dirname "$stub")"

printf '[gpg "ssh"]\n\tprogram = ssh-keygen\n' > "$home/.gitconfig.machine"

cat > "$stub" <<'EOF'
[user]
	signingKey = key::ssh-ed25519 AAAAStubGitAuthKey
[commit]
	gpgsign = true
EOF

{
  printf '[commit]\n\tgpgsign = true\n'
  printf '[gpg]\n\tformat = ssh\n'
  printf '[include]\n\tpath = ~/.gitconfig.machine\n'
  printf '[includeIf "hasconfig:remote.*.url:git@ddoghq.github.com:ddoghq/**"]\n\tpath = %s\n' "$stub"
  printf '[credential "https://github.com"]\n\thelper = !gh auth git-credential\n'
} > "$clone_git/.gitconfig"

ln -s "$clone_git/.gitconfig" "$home/.gitconfig"

# ~ in both the gitdir: pattern and the include path must expand to the
# fixture home for the probes below — export it for the whole test.
export HOME="$home"

count_include_sections() {
  git config --file "$clone_git/.gitconfig" --get-regexp '^includeIf\.gitdir:' \
    | wc -l | tr -d ' '
}

upsert_wmux_unsigned_gitconfig

# --- 1. symlink preserved; the writes landed in the clone target
[ -L "$home/.gitconfig" ] || fail "~/.gitconfig symlink was replaced by a plain file"
[ "$(readlink "$home/.gitconfig")" = "$clone_git/.gitconfig" ] || fail "~/.gitconfig symlink was retargeted"

# --- 2. both includeIf sections present, exactly once, at the END
[ "$(count_include_sections)" = "2" ] \
  || fail "expected 2 includeIf gitdir entries, got $(count_include_sections)"
expected_tail='[includeIf "gitdir:~/**/.git/worktrees/*--[0-9a-f]*"]
	path = ~/.gitconfig.wmux-unsigned
[includeIf "gitdir:/workspaces/**/.git/worktrees/*--[0-9a-f]*"]
	path = ~/.gitconfig.wmux-unsigned'
[ "$(tail -n 4 "$clone_git/.gitconfig")" = "$expected_tail" ] \
  || fail "the includeIf sections are not the canonical last 4 lines of ~/.gitconfig"

# --- 3. idempotency: re-run changes nothing structural
upsert_wmux_unsigned_gitconfig
[ "$(count_include_sections)" = "2" ] \
  || fail "re-run duplicated includeIf sections ($(count_include_sections))"
[ -L "$home/.gitconfig" ] || fail "re-run replaced the ~/.gitconfig symlink"

# --- 4. behavioral scope: delegate-shaped worktree vs everything else
src="$home/src/main-repo"
git init -q "$src"
git -C "$src" remote add origin git@ddoghq.github.com:ddoghq/fixture-repo.git
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  git -C "$src" -c user.name=t -c user.email=t@t \
  commit -q --allow-empty -m init

git -C "$src" worktree add -q --detach "$home/plain-wt"
git -C "$src" worktree add -q --detach "$home/spike--000000abcdef"

probe() {
  GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    git -C "$1" config commit.gpgsign
}

[ "$(probe "$src")" = "true" ] \
  || fail "main checkout lost commit signing"
[ "$(probe "$home/plain-wt")" = "true" ] \
  || fail "plain worktree lost commit signing (includeIf is over-broad)"
[ "$(probe "$home/spike--000000abcdef")" = "false" ] \
  || fail "delegate-shaped worktree did not get commit.gpgsign = false"

origin_line="$(GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$home/spike--000000abcdef" config --show-origin commit.gpgsign)"
[[ "$origin_line" == *'.gitconfig.wmux-unsigned'* ]] \
  || fail "delegate gpgsign=false did not come from ~/.gitconfig.wmux-unsigned (got: $origin_line)"

# --- 5. reverse URL rules reach the effective delegate config
reverse="$(GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$home/spike--000000abcdef" \
  config --get-all 'url.https://github.com/ddoghq/.insteadof')"
[[ "$reverse" == *'git@ddoghq.github.com:ddoghq:'* ]] \
  || fail "reverse ddoghq URL rule missing from effective delegate config"
reverse_sandbox="$(GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$home/spike--000000abcdef" \
  config --get-all 'url.https://github.com/ddoghq-sandbox/.insteadof')"
[[ "$reverse_sandbox" == *'git@ddoghq.github.com:ddoghq-sandbox:'* ]] \
  || fail "reverse ddoghq-sandbox URL rule missing from effective delegate config"

# --- 6. pristine HOME (no ~/.gitconfig at all) still works
home2="$FIXTURE_ROOT/home2"
mkdir -p "$home2"
HOME="$home2" upsert_wmux_unsigned_gitconfig
git config --file "$home2/.gitconfig" --get-regexp '^includeIf\.gitdir:' >/dev/null \
  || fail "pristine HOME: includeIf sections were not created"
[ -f "$home2/.gitconfig.wmux-unsigned" ] \
  || fail "pristine HOME: ~/.gitconfig.wmux-unsigned was not written"

printf 'PASS: wmux-unsigned gitconfig upsert is idempotent, end-positioned, and delegate-scoped\n'
