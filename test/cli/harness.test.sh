#!/usr/bin/env bash
# Pins test/lib/harness.sh's four assertions and mktemp_dir, plus
# scripts/test's discovery and exit behavior.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

fail() {
  echo "harness.test.sh: $1" >&2
  exit 1
}

# --- assert_eq -------------------------------------------------------------

assert_eq a a "a should equal a" || fail "assert_eq a a should pass"

err=$(assert_eq a b "a should equal b" 2>&1)
rc=$?
[ "$rc" -ne 0 ] || fail "assert_eq a b should fail"
assert_contains "$err" "a should equal b" \
  "assert_eq failure should put its message on stderr" || fail "message missing"

# --- assert_contains ---------------------------------------------------------

assert_contains "abc" b "b should be found in abc" || fail "assert_contains abc b should pass"

err=$(assert_contains "abc" z "z should be found in abc" 2>&1)
rc=$?
[ "$rc" -ne 0 ] || fail "assert_contains abc z should fail"
assert_contains "$err" "z should be found in abc" \
  "assert_contains failure should put its message on stderr" || fail "message missing"

# --- assert_exit -------------------------------------------------------------

(exit 2)
assert_exit 2 "should have exited 2" || fail "assert_exit 2 after exit 2 should pass"

(exit 0)
assert_exit 2 "should have exited 2" 2>/dev/null
rc=$?
[ "$rc" -ne 0 ] || fail "assert_exit 2 after exit 0 should fail"

# --- mktemp_dir --------------------------------------------------------------

probe_dir=$(mktemp_dir)
probe="$probe_dir/probe.sh"
cat > "$probe" <<EOF
#!/usr/bin/env bash
set -euo pipefail
. "$repo_root/test/lib/harness.sh"
d1=\$(mktemp_dir)
d2=\$(mktemp_dir)
printf '%s\n%s\n' "\$d1" "\$d2"
EOF
chmod +x "$probe"

paths=$("$probe")
d1=$(printf '%s\n' "$paths" | sed -n '1p')
d2=$(printf '%s\n' "$paths" | sed -n '2p')

[ -n "$d1" ] && [ -n "$d2" ] || fail "mktemp_dir should print a path each time"
[ "$d1" != "$d2" ] || fail "mktemp_dir called twice should give two different paths"
[ ! -d "$d1" ] || fail "mktemp_dir's first directory should be removed once the sourcing process exits"
[ ! -d "$d2" ] || fail "mktemp_dir's second directory should be removed once the sourcing process exits"

# Exercise the runner with two tiny independent tests, including its failure reporting.
runner=$(mktemp_dir)
mkdir -p "$runner/scripts" "$runner/test/nested"
cp "$repo_root/scripts/test" "$runner/scripts/"
cat > "$runner/test/pass.test.sh" <<'PROBE'
#!/usr/bin/env bash
echo pass >> calls
PROBE
cat > "$runner/test/nested/fail.test.sh" <<'PROBE'
#!/usr/bin/env bash
echo fail >> calls
echo "fixture error" >&2
exit 2
PROBE
chmod +x "$runner/test/pass.test.sh" "$runner/test/nested/fail.test.sh"

out=$("$runner/scripts/test" test/pass.test.sh) || fail "single-file run should pass"
assert_eq "ok    test/pass.test.sh" "$out" || exit 1
assert_eq pass "$(cat "$runner/calls")" "single-file run executed another test" || exit 1
rm "$runner/calls"
err=$("$runner/scripts/test" test/missing.test.sh 2>&1)
assert_exit 1 "unknown path should fail" || exit 1
assert_contains "$err" "test/missing.test.sh" || exit 1
[ ! -e "$runner/calls" ] || fail "an unknown path ran a test"

out=$("$runner/scripts/test")
assert_exit 1 "a failed test fails the default run" || exit 1
assert_eq $'FAIL  test/nested/fail.test.sh\n      fixture error\nok    test/pass.test.sh' "$out" || exit 1
assert_eq $'fail\npass' "$(sort "$runner/calls")" "the default run runs each test once" || exit 1

# frontmatter FILE — the YAML block between the first two '---' lines, or
# nothing if the file has none.
frontmatter() {
  awk 'NR==1 && $0=="---" {p=1; next} p && $0=="---" {exit} p' "$1"
}

# --- TC-9: scripts/check passes; no skill carries disable-model-invocation

portable=$(mktemp_dir)
mkdir -p "$portable/scripts" "$portable/adapters" "$portable/bin"
cp "$repo_root/scripts/check" "$portable/scripts/"
printf 'print("CORE fixture passed")\n' > "$portable/scripts/check-links.py"
ln -s "$(command -v python3)" "$portable/bin/python3"
# Poison client names to catch accidental execution.
for client in claude codex qoder; do
  printf '#!/bin/sh\necho unexpected-client >> "%s"\nexit 99\n' "$portable/client-calls" > "$portable/bin/$client"
  chmod +x "$portable/bin/$client"
done
check_out=$(PATH="$portable/bin" "$portable/bin/python3" "$portable/scripts/check" 2>&1)
check_rc=$?
[ "$check_rc" -eq 0 ] || fail "validation#portable-default: default core check failed: $check_out"
[ ! -e "$portable/client-calls" ] || fail "validation#portable-default: default check called a client"
rm "$portable/bin/claude" "$portable/bin/codex" "$portable/bin/qoder"
check_out=$(PATH="$portable/bin" "$portable/bin/python3" "$portable/scripts/check" 2>&1)
[ "$?" -eq 0 ] || fail "validation#portable-default: missing clients: $check_out"
check_out=$(PATH="$portable/bin" "$portable/bin/python3" "$repo_root/scripts/check" 2>&1)
[ "$?" -eq 0 ] || fail "validation#portable-default: real shared checks without clients: $check_out"
[ ! -d "$portable/scripts/__pycache__" ] || fail "validation#portable-default: check leaves no bytecode artifacts"

for f in "$repo_root"/workflow/*/GUIDE.md; do
  skill=$(basename "$(dirname "$f")")
  fm=$(frontmatter "$f")
  ! printf '%s' "$fm" | grep -qi 'disable-model-invocation' \
    || fail "TC-9: workflow/$skill/GUIDE.md should carry no disable-model-invocation"
done

# --- TC-11: no retired 'Checkpoint N' or '| Segment |' outside the vocabulary

checkpoint_out=$(cd "$repo_root" && grep -rn 'Checkpoint [0-9]' workflow/ 2>/dev/null)
[ -z "$checkpoint_out" ] || fail "TC-11: expected no match for 'Checkpoint N', found: $checkpoint_out"

segment_col_out=$(cd "$repo_root" && grep -rn '| Segment |' workflow/ 2>/dev/null)
[ -z "$segment_col_out" ] || fail "TC-11: expected no match for '| Segment |', found: $segment_col_out"

# --- TC-13: no scripts/ under workflow/, no tool limits, models, one version --

skill_scripts=$(cd "$repo_root" && find workflow -type d -name scripts 2>/dev/null)
[ -z "$skill_scripts" ] || fail "TC-13: no scripts/ directory under workflow/, found: $skill_scripts"
for f in "$repo_root"/agents/*.md; do
  ! frontmatter "$f" | grep -q '^tools:' || fail "TC-13: $(basename "$f") should carry no tools: line"
done
for f in "$repo_root"/agents/*.md; do
  ! frontmatter "$f" | grep -q '^model:' || fail "run#executor-presets: TC-13: role must use the selected preset"
  grep -q 'AGENTS.md' "$f" || fail "TC-13: role must read shared rules"
done
caps_out=$(cd "$repo_root" && grep -rniE --exclude-dir=archive 'two fixes at most|one round per gate|fix [12]\b' workflow agents AGENTS.md README.md references docs 2>/dev/null)
[ -z "$caps_out" ] || fail "build#caps-in-code: TC-13: no cap in prose an agent reads, found: $caps_out"
grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+$' "$repo_root/VERSION" || fail "invalid Runweld version"

for f in land finish; do
  ! grep -qE 'git (reset|commit|merge|push|branch -D)|gh pr' "$repo_root/workflow/$f/GUIDE.md" \
    || fail "land#stops-to-user: workflow/$f runs git itself"
done

echo "ok"
