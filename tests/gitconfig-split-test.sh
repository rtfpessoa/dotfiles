#!/usr/bin/env bash
#
# gitconfig-split-test.sh — the portable git layer, the workspaces include
# chain that consumes it, and the platform-owned ~/.gitconfig detection.
# Offline: fixture HOME, real git isolated from the machine's global config
# (which rewrites github.com URLs and would distort the routing assertion).

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fixture_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"
}

portable="$REPO_DIR/git/.gitconfig.portable"
root="$REPO_DIR/git/.gitconfig"

# --- the split ---------------------------------------------------------------

[ -f "$portable" ] || fail "git/.gitconfig.portable is missing"
fixture_git config --file "$portable" --list >/dev/null \
  || fail "the portable layer does not parse"
fixture_git config --file "$root" --list >/dev/null \
  || fail "the root gitconfig does not parse"

alias_count="$(fixture_git config --file "$portable" --get-regexp '^alias\.' | wc -l | tr -d ' ')"
[ "$alias_count" -ge 40 ] || fail "the portable layer lost aliases (got $alias_count)"
for alias_name in st co brdr; do
  fixture_git config --file "$portable" --get "alias.$alias_name" >/dev/null \
    || fail "alias.$alias_name is missing from the portable layer"
done

grep -qx 'path = ~/.gitconfig.portable' "$root" \
  || fail "the macOS root does not include the portable layer"

# Signing material, the hooks path and Darwin filesystem semantics stay in the
# root: a pull in ~/dotfiles goes live before the new stow target is linked, so
# losing the portable layer must cost aliases and tuning only — never signing
# or the Maat gate — and must never leak to Linux workspaces.
for key in \
  gpg.ssh.program gpg.ssh.allowedSignersFile user.signingkey \
  commit.gpgsign gpg.format tag.gpgsign \
  core.hooksPath core.ignorecase core.trustctime core.precomposeunicode; do
  fixture_git config --file "$root" --get "$key" >/dev/null \
    || fail "$key must stay in git/.gitconfig"
  if fixture_git config --file "$portable" --get "$key" >/dev/null; then
    fail "$key must not leak into the portable layer"
  fi
done

# --- the workspaces chain ----------------------------------------------------
# Mirrors the platform render: the user-layer node first (portable → extras →
# home → machine), then the managed Datadog config.

home="$FIXTURE_DIR/home"
mkdir -p "$home"
ln -s "$portable" "$home/.gitconfig.portable"
printf '[user]\n\tname = Extras Name\n\temail = extras@example.com\n' > "$home/.gitconfig.extras"
printf '[core]\n\texcludesfile = %s/workspace-ignore\n' "$home" > "$home/.gitconfig.home"
printf '[datadog]\n\tteam = team-rapidworkloads\n' > "$home/.gitconfig.machine"

node="$FIXTURE_DIR/user-node.gitconfig"
cat > "$node" <<EOF
[include]
	path = $home/.gitconfig.portable
[include]
	path = $home/.gitconfig.extras
[include]
	path = $home/.gitconfig.home
[include]
	path = $home/.gitconfig.machine
EOF

cat > "$home/.gitconfig" <<EOF
# Managed by workspaces
[include]
	path = $node
[user]
	name = Managed Name
	email = managed@datadoghq.com
	signingkey = key::ssh-ed25519 MANAGEDKEY
[commit]
	gpgsign = true
[core]
	hooksPath = /managed/hooks
[url "git@github.com:"]
	insteadOf = https://github.com/
[url "git@ddoghq.github.com:ddoghq/"]
	insteadOf = https://github.com/ddoghq/
EOF

chain_git() { HOME="$home" git config --global --includes "$@"; }

[ "$(chain_git --get alias.st)" = "status -sb" ] \
  || fail "the workspace chain does not resolve the portable aliases"
[ "$(chain_git --get user.email)" = "managed@datadoghq.com" ] \
  || fail "the managed identity must win over the extras layer"
[ "$(chain_git --get user.signingkey)" = "key::ssh-ed25519 MANAGEDKEY" ] \
  || fail "the managed signing key must win (the 1Password pin is macOS-only)"
[ "$(chain_git --get core.excludesfile)" = "$home/workspace-ignore" ] \
  || fail "the workspace gitignore must supersede the portable core.excludesfile"
[ "$(chain_git --get core.hooksPath)" = "/managed/hooks" ] \
  || fail "the managed hooksPath must win"
[ "$(chain_git --get datadog.team)" = "team-rapidworkloads" ] \
  || fail "the portable layer no longer carries the datadog team attribution"

routing="$(cd "$FIXTURE_DIR" && HOME="$home" git ls-remote --get-url https://github.com/ddoghq/dd-source)"
[ "$routing" = "git@ddoghq.github.com:ddoghq/dd-source" ] \
  || fail "ddoghq URL routing regressed (got: $routing)"

# The pre-clone state: the include target is missing, git stays silent.
missing="$FIXTURE_DIR/pre-clone"
mkdir -p "$missing"
cat > "$missing/.gitconfig" <<EOF
[include]
	path = $missing/.gitconfig.portable
EOF
if HOME="$missing" git config --global --includes --get alias.st 2>"$FIXTURE_DIR/stderr"; then
  fail "an absent portable layer must not resolve aliases"
fi
[ ! -s "$FIXTURE_DIR/stderr" ] \
  || fail "an absent include target must stay silent (got: $(cat "$FIXTURE_DIR/stderr"))"

# --- the macOS root ---------------------------------------------------------
# On macOS the root IS the home gitconfig, and a pull in the dotfiles checkout
# goes live before the new stow target is linked: signing and hooks must survive
# with the portable layer absent, and aliases must appear once it is stowed.
mac="$FIXTURE_DIR/macos"
mkdir -p "$mac"
cp "$root" "$mac/.gitconfig"
: > "$mac/.gitconfig.extras"
: > "$mac/.gitconfig.home"
: > "$mac/.gitconfig.machine"

if HOME="$mac" git config --global --includes --get alias.st >/dev/null 2>&1; then
  fail "the macOS root must not resolve aliases before the portable layer is stowed"
fi
[ "$(HOME="$mac" git config --global --includes --get commit.gpgsign)" = "true" ] \
  || fail "the macOS root must keep signing enabled without the portable layer"
[ "$(HOME="$mac" git config --global --includes --get gpg.format)" = "ssh" ] \
  || fail "the macOS root must keep the SSH signing format without the portable layer"
[ -n "$(HOME="$mac" git config --global --includes --get gpg.ssh.program)" ] \
  || fail "the macOS root must keep the 1Password signer without the portable layer"
[ -n "$(HOME="$mac" git config --global --includes --get core.hooksPath)" ] \
  || fail "the macOS root must keep the Maat hooks path without the portable layer"

ln -s "$portable" "$mac/.gitconfig.portable"
[ "$(HOME="$mac" git config --global --includes --get alias.st)" = "status -sb" ] \
  || fail "the macOS root does not resolve aliases once the portable layer is stowed"
[ "$(HOME="$mac" git config --global --includes --get user.signingkey)" = "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsIVmGXH+CLtcN2o+q057GdyVitr/ICmNT+OAAEuGBN" ] \
  || fail "the macOS default signing key changed"

# --- platform_owns_gitconfig -------------------------------------------------
# Extracted verbatim from install.sh so the decision the installer makes is
# exercised, not a copy of it.

detect="$FIXTURE_DIR/platform-detect.sh"
sed -n '/^platform_owns_gitconfig()/,/^}$/p' "$REPO_DIR/install.sh" > "$detect"
grep -q 'Managed by workspaces' "$detect" \
  || fail "could not extract platform_owns_gitconfig from install.sh"

detects() {
  HOME="$1" bash -c "set -u; . '$detect'; platform_owns_gitconfig"
}

platform="$FIXTURE_DIR/case-platform"
mkdir -p "$platform"
printf '# Managed by workspaces\n[user]\n\tname = x\n' > "$platform/.gitconfig"
detects "$platform" || fail "a platform-owned ~/.gitconfig was not detected"

symlinked="$FIXTURE_DIR/case-symlink"
mkdir -p "$symlinked"
ln -s "$platform/.gitconfig" "$symlinked/.gitconfig"
if detects "$symlinked"; then
  fail "a stow symlink must not count as a platform-owned ~/.gitconfig"
fi

plain="$FIXTURE_DIR/case-plain"
mkdir -p "$plain"
printf '[user]\n\tname = personal\n' > "$plain/.gitconfig"
if detects "$plain"; then
  fail "a hand-written ~/.gitconfig must keep the archive-and-stow path"
fi

empty="$FIXTURE_DIR/case-none"
mkdir -p "$empty"
if detects "$empty"; then
  fail "an absent ~/.gitconfig must not count as platform-owned"
fi

printf 'PASS: portable git layer, workspace chain and platform gitconfig detection\n'
