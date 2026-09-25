#!/usr/bin/env bash
# Pins test/lib/gitfixture.sh: the throwaway repository builder every later
# test/cli/*.test.sh in this segment is built on. If this file's own guard
# ever failed to refuse a fixture pointed at the repository under work, every
# later phase's tests would be able to write into it.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/lib/gitfixture.sh"

fail() {
  echo "gitfixture.test.sh: $1" >&2
  exit 1
}

# --- gitfixture_new: a real repository with one commit ---------------------

repo1=$(gitfixture_new)
[ -d "$repo1" ] || fail "gitfixture_new should hand back an existing directory"

top=$(git -C "$repo1" rev-parse --show-toplevel)
assert_eq "$repo1" "$top" "gitfixture_new's own path must be its git toplevel" \
  || fail "path/toplevel mismatch"

commits=$(git -C "$repo1" log --oneline | wc -l | tr -d ' ')
assert_eq "1" "$commits" "gitfixture_new should leave exactly one commit" \
  || fail "wrong commit count"

# --- two calls, two different repositories ----------------------------------

repo2=$(gitfixture_new)
[ "$repo1" != "$repo2" ] || fail "two gitfixture_new calls returned the same path"

# --- gitfixture_dirty: one staged path, one unstaged path -------------------

repo3=$(gitfixture_new)
gitfixture_dirty "$repo3"

staged=$(git -C "$repo3" diff --cached --name-only | wc -l | tr -d ' ')
unstaged=$(git -C "$repo3" diff --name-only | wc -l | tr -d ' ')
assert_eq "1" "$staged" "gitfixture_dirty should leave one staged path" \
  || fail "staged count"
assert_eq "1" "$unstaged" "gitfixture_dirty should leave one unstaged path" \
  || fail "unstaged count"

# --- a helper pointed at this repository's root: refused, nothing written --

before="$(cd "$repo_root" && git status --porcelain)"
gitfixture_dirty "$repo_root" 2>/dev/null
rc=$?
[ "$rc" -ne 0 ] || fail "gitfixture_dirty on this repository's root should have been refused"
after="$(cd "$repo_root" && git status --porcelain)"
assert_eq "$before" "$after" "a refused helper must leave this repository's root untouched" \
  || fail "the guard let something through"

# --- cleanup: both fixture paths are gone once their own process exits -----
#
# harness.sh's cleanup runs on that shell's own EXIT trap, so this has to be
# observed from outside the process that created the fixtures — a sourcing
# child process here, checked from this file after it has exited.

paths_dir=$(mktemp_dir)
paths_file="$paths_dir/paths.txt"
bash -c '
  . "'"$repo_root"'/test/lib/harness.sh"
  . "'"$repo_root"'/test/lib/gitfixture.sh"
  a=$(gitfixture_new)
  b=$(gitfixture_new)
  printf "%s\n%s\n" "$a" "$b"
' > "$paths_file"

while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ ! -e "$p" ] || fail "fixture path should be gone once its own process exited: $p"
done < "$paths_file"

echo "ok"
