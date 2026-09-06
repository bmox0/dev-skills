#!/usr/bin/env bash
# Pins hooks/branch-guard.sh: on the default branch in a `.branch-guard`
# repository, a write under docs/ (any filename, any depth) is allowed, a
# root CONTEXT.md is refused with a reason naming docs/ and .ai-workflow/ (and
# not CONTEXT.md), a git commit is allowed only when every staged path sits
# under docs/, and the guard still has no opinion with no .branch-guard file
# and off the default branch. TC-10 and TC-11 are gate-b: N/A and carry no
# seam — see the plan's Test seams section; they are not here.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/lib/gitfixture.sh"

hook="$repo_root/hooks/branch-guard.sh"

fail() {
  echo "branch-guard.test.sh: $1" >&2
  exit 1
}

# run_hook REPO TOOL FIELD VALUE — feeds the hook the JSON Claude Code would
# send, with cwd set to REPO. branch-guard.sh resolves its own git context
# either from the dirname of a Write/Edit path or, for the Bash arm, from cwd
# directly, so cwd has to sit inside the fixture for either arm to see it.
# Sets $out and $rc for the caller.
run_hook() {
  local repo="$1" tool="$2" field="$3" value="$4"
  out=$(cd "$repo" && printf '{"tool_name":"%s","tool_input":{"%s":"%s"}}' "$tool" "$field" "$value" | "$hook")
  rc=$?
}

assert_allowed() {
  local id="$1"
  assert_eq 0 "$rc" "$id: hook exits 0" || fail "$id"
  assert_eq "" "$out" "$id: write is allowed — nothing on stdout" || fail "$id"
}

assert_denied() {
  local id="$1"
  assert_eq 0 "$rc" "$id: hook exits 0" || fail "$id"
  assert_contains "$out" '"permissionDecision":"deny"' "$id: refused with a deny decision" || fail "$id"
}

repo=$(gitfixture_new)
touch "$repo/.branch-guard"

# TC-1: a Write of docs/CONTEXT.md is allowed.
run_hook "$repo" Write file_path "docs/CONTEXT.md"
assert_allowed "TC-1"

# TC-2: a Write of docs/LESSONS.md — a filename no pattern in the hook names
# — is allowed too: the exemption is the docs/ directory, not any filename.
run_hook "$repo" Write file_path "docs/LESSONS.md"
assert_allowed "TC-2"

# TC-3: a Write of docs/adr/0002-thing.md — what passed before still passes.
run_hook "$repo" Write file_path "docs/adr/0002-thing.md"
assert_allowed "TC-3"

# TC-4: a Write of CONTEXT.md at the repository root is refused; the reason
# names docs/ and .ai-workflow/ as the exempt places and never CONTEXT.md.
run_hook "$repo" Write file_path "CONTEXT.md"
assert_denied "TC-4"
assert_contains "$out" "docs/" "TC-4: reason names docs/" || fail "TC-4"
assert_contains "$out" ".ai-workflow/" "TC-4: reason names .ai-workflow/" || fail "TC-4"
case "$out" in
  *CONTEXT.md*) fail "TC-4: reason must not name CONTEXT.md" ;;
esac

# TC-5: a git commit whose staged paths are docs/CONTEXT.md and
# docs/adr/0002-thing.md, nothing else, is allowed.
mkdir -p "$repo/docs/adr"
printf 'context\n' > "$repo/docs/CONTEXT.md"
printf 'decision\n' > "$repo/docs/adr/0002-thing.md"
git -C "$repo" add docs/CONTEXT.md docs/adr/0002-thing.md
run_hook "$repo" Bash command "git commit -m record-it"
assert_allowed "TC-5"

# TC-6: the same commit, with src/app.ts staged alongside the docs/ paths —
# one non-exempt staged path is enough to refuse it.
mkdir -p "$repo/src"
printf 'app\n' > "$repo/src/app.ts"
git -C "$repo" add src/app.ts
run_hook "$repo" Bash command "git commit -m record-it"
assert_denied "TC-6"

# TC-7: a Write under .ai-workflow/ is allowed, unchanged.
run_hook "$repo" Write file_path ".ai-workflow/plans/2026-09-06-x.md"
assert_allowed "TC-7"

# TC-8: a repository with no .branch-guard file never has an opinion.
repo_no_guard=$(gitfixture_new)
run_hook "$repo_no_guard" Write file_path "src/app.ts"
assert_allowed "TC-8"

# TC-9: a .branch-guard repository standing on a branch that is not the
# default has no opinion either.
repo_branch=$(gitfixture_new)
touch "$repo_branch/.branch-guard"
gitfixture_branch "$repo_branch" "feature/x"
run_hook "$repo_branch" Write file_path "src/app.ts"
assert_allowed "TC-9"

# TC-12: docs/ is exempt as a whole path segment wherever it sits, not only
# at the repository root — a nested src/nested/docs/notes.md is allowed too.
run_hook "$repo" Write file_path "src/nested/docs/notes.md"
assert_allowed "TC-12"

# TC-13: mydocs/ only looks like the exempt segment — it is refused. This is
# the boundary that keeps TC-12's looseness bounded: docs/ is a whole path
# segment, never a prefix.
run_hook "$repo" Write file_path "mydocs/notes.md"
assert_denied "TC-13"

exit 0
