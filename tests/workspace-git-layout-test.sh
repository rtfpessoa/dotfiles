#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/workspace-git-layout.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
SCRIPT_DIR="$tmp/dotfiles"
source "$repo/lib.sh"

mkdir -p "$HOME/.config" "$SCRIPT_DIR/git/.config/git"
cp "$repo/git/.config/git/allowed_signers" "$SCRIPT_DIR/git/.config/git/"
cp "$repo/git/.gitconfig.portable" "$SCRIPT_DIR/git/"
printf '# Managed by workspaces\n' > "$HOME/.gitconfig"
cp "$repo/.gitignore" "$SCRIPT_DIR/"
git -C "$SCRIPT_DIR" init -q
git -C "$SCRIPT_DIR" add .gitignore git

# Reproduce the old layout with real Stow rather than mocking its folding.
stow -d "$SCRIPT_DIR" -t "$HOME" git
test -L "$HOME/.config/git"
printf '[user]\n\tname = Workspace User\n\temail = workspace@example.test\n' > "$tmp/identity"
printf '[include]\n\tpath = %s\n' "$tmp/identity" > "$HOME/.config/git/config"

export STOW_IGNORE_GITCONFIG=1
touch "$HOME/.config/git/config.lock"
touch "$SCRIPT_DIR/untracked-drift"
# Even the old wrapper's plain git clean must preserve the live state once
# it has fetched and reset to the generic revision containing this fix.
git -C "$SCRIPT_DIR" clean -fd >/dev/null
test ! -e "$SCRIPT_DIR/untracked-drift"
test -f "$HOME/.config/git/config"
test -f "$HOME/.config/git/config.lock"
if install_dotfiles git; then
  printf 'Expected the folded layout to remain unchanged while Git config is being edited\n' >&2
  exit 1
fi
test -L "$HOME/.config/git"
test -f "$HOME/.config/git/config"
rm "$HOME/.config/git/config.lock"

for run in migrate repeat; do
  install_dotfiles git
  test -d "$HOME/.config/git"
  test ! -L "$HOME/.config/git"
  test -L "$HOME/.config/git/allowed_signers"
  cmp "$HOME/.config/git/allowed_signers" "$repo/git/.config/git/allowed_signers"
  test ! -e "$SCRIPT_DIR/git/.config/git/config"
  test ! -L "$HOME/.gitconfig"
  test "$(git config --file "$HOME/.config/git/config" --includes user.email)" = workspace@example.test
done

# A fresh install must not introduce the directory symlink.
export HOME="$tmp/fresh"
mkdir "$HOME"
install_dotfiles git
test -d "$HOME/.config/git"
test ! -L "$HOME/.config/git"
test -L "$HOME/.config/git/allowed_signers"
test ! -e "$HOME/.config/git/config"
test ! -e "$HOME/.gitconfig"

printf 'PASS: workspace Stow layout preserves live Git config outside the checkout\n'
