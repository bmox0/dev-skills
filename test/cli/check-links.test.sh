#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

fail() {
  echo "check-links.test.sh: $1" >&2
  exit 1
}

tree=$(mktemp_dir)
mkdir -p "$tree/scripts" "$tree/skills/demo" "$tree/agents" "$tree/references"
cp "$repo_root/scripts/check-links.py" "$tree/scripts/"
: > "$tree/scripts/link-allow.txt"
printf -- '---\nname: demo\ndescription: a demo\n---\n\none two three four five\n' > "$tree/skills/demo/SKILL.md"
printf 'skills/demo/SKILL.md 20\n' > "$tree/scripts/word-budgets.txt"

run_check() {
  out=$(python3 "$tree/scripts/check-links.py" 2>&1)
  rc=$?
}

run_check
assert_eq 0 "$rc" "TC-1: a file within its budget passes" || fail "TC-1: $out"

printf 'skills/demo/SKILL.md 5\n' > "$tree/scripts/word-budgets.txt"
run_check
assert_eq 1 "$rc" "TC-2: a file over its budget fails" || fail "TC-2: $out"
assert_contains "$out" "over its budget of 5" "TC-2: the finding names the budget" || fail "TC-2"

printf 'skills/demo/SKILL.md 20\n' > "$tree/scripts/word-budgets.txt"
printf 'notes\n' > "$tree/references/NOTES.md"
run_check
assert_eq 1 "$rc" "TC-3: a file with no budget line fails" || fail "TC-3: $out"
assert_contains "$out" "references/NOTES.md: BUDGET no budget line" "TC-3: the finding names the file" || fail "TC-3"
rm "$tree/references/NOTES.md"

printf 'skills/demo/SKILL.md 20\nskills/gone/SKILL.md 10\n' > "$tree/scripts/word-budgets.txt"
run_check
assert_eq 1 "$rc" "TC-4: a budget line for a missing file fails" || fail "TC-4: $out"
assert_contains "$out" "skills/gone/SKILL.md: BUDGET line for a file that is not a budgeted markdown file" "TC-4" || fail "TC-4"

printf 'skills/demo/SKILL.md 40\n' > "$tree/scripts/word-budgets.txt"
printf -- '---\nname: demo\ndescription: a demo\n---\n\nDispatch gate-a after the build.\n' > "$tree/skills/demo/SKILL.md"
run_check
assert_eq 1 "$rc" "TC-5: a retired name fails" || fail "TC-5: $out"
assert_contains "$out" "R3 legacy token 'gate-a'" "TC-5: the finding names the token" || fail "TC-5"

printf -- '---\nname: demo\ndescription: a demo\n---\n\nSee [the notes](references/NOTES.md).\n' > "$tree/skills/demo/SKILL.md"
run_check
assert_eq 1 "$rc" "TC-6: a dangling link fails" || fail "TC-6: $out"
assert_contains "$out" "R1 dangling link 'references/NOTES.md'" "TC-6" || fail "TC-6"

printf -- '---\nname: demo\ndescription: a demo\n---\n\nfine\n' > "$tree/skills/demo/SKILL.md"
printf 'skills/demo/SKILL.md 40\nskills/demo/SKILL.md 90\n' > "$tree/scripts/word-budgets.txt"
run_check
assert_eq 1 "$rc" "TC-7: a second budget line for one file fails" || fail "TC-7: $out"
assert_contains "$out" "second line for skills/demo/SKILL.md" "TC-7" || fail "TC-7"

printf 'skills/demo/SKILL.md forty\n' > "$tree/scripts/word-budgets.txt"
run_check
assert_contains "$out" "malformed line" "TC-8: a malformed budget line is a finding" || fail "TC-8: $out"

printf 'skills/demo/SKILL.md 40\nREADME.md 10\n' > "$tree/scripts/word-budgets.txt"
printf 'readme\n' > "$tree/README.md"
run_check
assert_contains "$out" "README.md: BUDGET line for a file that is not a budgeted markdown file" "TC-9" || fail "TC-9: $out"
rm "$tree/README.md"

printf 'skills/demo/SKILL.md 40\n' > "$tree/scripts/word-budgets.txt"
printf -- '---\nname: demo\ndescription: "broken: [\n---\n\nbody\n' > "$tree/skills/demo/SKILL.md"
run_check
assert_eq 1 "$rc" "TC-10: an unbalanced quote in frontmatter fails" || fail "TC-10: $out"
assert_contains "$out" 'FRONT unbalanced "' "TC-10" || fail "TC-10"

printf -- '---\nname: demo\ndescription: [Red before green\n---\n\nbody\n' > "$tree/skills/demo/SKILL.md"
run_check
assert_contains "$out" "FRONT unbalanced [" "TC-10b: an open flow sequence fails" || fail "TC-10b: $out"

printf -- '---\nname: demo\ndescription: Use when: writing tests\n---\n\nbody\n' > "$tree/skills/demo/SKILL.md"
run_check
assert_contains "$out" "a plain value cannot hold" "TC-10c: a colon in a plain value fails" || fail "TC-10c: $out"

printf -- '---\n# a comment\nname: demo\n\ndescription: "Use when: writing tests"\ntools:\n  - Read\n  - Grep\n---\n\nbody\n' > "$tree/skills/demo/SKILL.md"
run_check
! printf '%s' "$out" | grep -q "FRONT " || fail "TC-10d: comments, blank lines, quoted colons and lists are valid: $out"

printf -- '---\nname: other\ndescription: a demo\n---\n\nbody\n' > "$tree/skills/demo/SKILL.md"
run_check
assert_contains "$out" "FRONT name is 'other', expected 'demo'" "TC-11: a name that is not the directory fails" || fail "TC-11: $out"

printf -- '---\nname: demo\ndescription: a demo\n---\n\nbody\n' > "$tree/skills/demo/SKILL.md"
printf -- '---\nname: helper\n---\n\nbody\n' > "$tree/agents/helper.md"
printf 'skills/demo/SKILL.md 40\nagents/helper.md 20\nreferences/VOCAB.md 20\n' > "$tree/scripts/word-budgets.txt"
printf 'See [x](missing.md).\n' > "$tree/references/VOCAB.md"
run_check
assert_contains "$out" "agents/helper.md: FRONT no description" "TC-12: an agent needs a description" || fail "TC-12: $out"
assert_contains "$out" "references/VOCAB.md:1: R1 dangling link" "TC-12: references/ is walked" || fail "TC-12: $out"

exit 0
