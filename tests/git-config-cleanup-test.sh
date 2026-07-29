#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$TEST_DIR/../lib.sh"

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

missing_sections="$FIXTURE_DIR/missing-sections"
git config --file "$missing_sections" user.name "Test User"

remove_git_config_section_if_present "$missing_sections" gpg.ssh
remove_git_config_section_if_present "$missing_sections" dd-gitsign

[ "$(git config --file "$missing_sections" user.name)" = "Test User" ] \
  || fail "an unrelated key changed when optional sections were absent"

prefix_collisions="$FIXTURE_DIR/prefix-collisions"
git config --file "$prefix_collisions" gpg.ssh.extra.program "keep-gpg-subsection"
git config --file "$prefix_collisions" dd-gitsign.extra.enabled "keep-dd-gitsign-subsection"

remove_git_config_section_if_present "$prefix_collisions" gpg.ssh
remove_git_config_section_if_present "$prefix_collisions" dd-gitsign

[ "$(git config --file "$prefix_collisions" gpg.ssh.extra.program)" = "keep-gpg-subsection" ] \
  || fail "a longer gpg.ssh subsection was changed"
[ "$(git config --file "$prefix_collisions" dd-gitsign.extra.enabled)" = "keep-dd-gitsign-subsection" ] \
  || fail "a longer dd-gitsign subsection was changed"

present_sections="$FIXTURE_DIR/present-sections"
git config --file "$present_sections" user.name "Test User"
git config --file "$present_sections" gpg.ssh.program "/usr/bin/ssh-keygen"
git config --file "$present_sections" dd-gitsign.enabled true

remove_git_config_section_if_present "$present_sections" gpg.ssh
remove_git_config_section_if_present "$present_sections" dd-gitsign

if git config --file "$present_sections" --get-regexp '^gpg\.ssh\.' >/dev/null; then
  fail "gpg.ssh was not removed"
fi
if git config --file "$present_sections" --get-regexp '^dd-gitsign\.' >/dev/null; then
  fail "dd-gitsign was not removed"
fi
[ "$(git config --file "$present_sections" user.name)" = "Test User" ] \
  || fail "an unrelated key changed while removing optional sections"

malformed_config="$FIXTURE_DIR/malformed"
printf '[broken\n' > "$malformed_config"
if remove_git_config_section_if_present "$malformed_config" gpg.ssh; then
  fail "a malformed Git config was treated as a missing section"
fi

printf 'PASS: optional Git config sections are removed safely\n'
