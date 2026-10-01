#!/usr/bin/env bash
# Pins test/lib/harness.sh's four assertions and mktemp_dir, plus
# scripts/test's single-file mode.
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

# --- scripts/test <path>: single-file mode -----------------------------
#
# The .test.sh case below targets test/cli/check-links.test.sh rather than
# this file: pointing it at harness.test.sh itself made the suite invoke
# itself, and every mechanism tried for bounding that recursion turned out
# to be forgeable from the environment it runs in. This removes only the
# direct path, not recursion itself — if run_one ever regressed to
# ignoring its argument, any `scripts/test <path>` would fall back to the
# whole suite, which includes this file, which would invoke `scripts/test`
# again, one level deeper each time. That is accepted rather than bounded:
# it still ends in a correct failure, just a slow one, and a slow red is a
# different problem than the silent pass this file exists to catch.

# a .test.sh file other than this one (see above) — that file's line only
out=$("$repo_root/scripts/test" "test/cli/check-links.test.sh" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "scripts/test test/cli/check-links.test.sh should exit 0"
lines=$(printf '%s\n' "$out" | grep -cE '^(ok|FAIL)[[:space:]]')
[ "$lines" -eq 1 ] || fail "scripts/test test/cli/check-links.test.sh should print exactly one file's line, got $lines"
assert_contains "$out" "test/cli/check-links.test.sh" \
  "single-file run should report its own line" || fail "own line missing"

# a path that is not a test file: loud, not a silent fallback to everything
err=$("$repo_root/scripts/test" "test/lib/harness.sh" 2>&1 1>/dev/null)
rc=$?
[ "$rc" -ne 0 ] || fail "scripts/test with a non-test-file path should exit non-zero"
assert_contains "$err" "test/lib/harness.sh" \
  "the error should name the path that isn't a test file" || fail "path not named"

# --- TC-9 to TC-13: the assembled repository's shape ------------------------
#
# None of these pin one script's behaviour the way the rest of test/cli/ does
# — they check the assembled repository's own shape (frontmatter, vocabulary,
# the whole suite), so there is no more specific file to carry them. This file
# already exercises scripts/test on the real tree above; these run against the
# real tree too, never a synthetic fixture.

# frontmatter FILE — the YAML block between the first two '---' lines, or
# nothing if the file has none.
frontmatter() {
  awk 'NR==1 && $0=="---" {p=1; next} p && $0=="---" {exit} p' "$1"
}

# --- TC-9: scripts/check passes; disable-model-invocation on finish alone ---

check_out=$("$repo_root/scripts/check" 2>&1)
check_rc=$?
[ "$check_rc" -eq 0 ] || fail "TC-9: scripts/check should pass, got exit $check_rc: $check_out"

finish_seen=0
for f in "$repo_root"/skills/*/SKILL.md; do
  skill=$(basename "$(dirname "$f")")
  [ "$skill" != finish ] || finish_seen=1
  fm=$(frontmatter "$f")
  case "$skill" in
    finish)
      printf '%s' "$fm" | grep -qi 'disable-model-invocation' \
        || fail "TC-9: skills/finish/SKILL.md should carry disable-model-invocation" ;;
    *)
      ! printf '%s' "$fm" | grep -qi 'disable-model-invocation' \
        || fail "TC-9: skills/$skill/SKILL.md should carry no disable-model-invocation" ;;
  esac
done
[ "$finish_seen" -eq 1 ] || fail "TC-9: skills/finish/SKILL.md was not found"

# --- TC-10: no mention of Haiku anywhere the model is documented -----------

haiku_out=$(cd "$repo_root" && grep -ri haiku skills/ agents/ references/ README.md 2>/dev/null)
[ -z "$haiku_out" ] || fail "TC-10: expected no match for haiku, found: $haiku_out"

# --- TC-11: no retired 'Checkpoint N' or '| Segment |' outside the vocabulary

checkpoint_out=$(cd "$repo_root" && grep -rn 'Checkpoint [0-9]' skills/ 2>/dev/null)
[ -z "$checkpoint_out" ] || fail "TC-11: expected no match for 'Checkpoint N', found: $checkpoint_out"

segment_col_out=$(cd "$repo_root" && grep -rn '| Segment |' skills/ 2>/dev/null)
[ -z "$segment_col_out" ] || fail "TC-11: expected no match for '| Segment |', found: $segment_col_out"

# --- TC-13: no hooks, no skill scripts, no tool limits, the agents' models ---

[ ! -e "$repo_root/hooks" ] || fail "TC-13: the plugin ships no hooks/"
skill_scripts=$(cd "$repo_root" && find skills -type d -name scripts 2>/dev/null)
[ -z "$skill_scripts" ] || fail "TC-13: the plugin ships no skill scripts, found: $skill_scripts"
for f in "$repo_root"/agents/*.md; do
  ! frontmatter "$f" | grep -q '^tools:' || fail "TC-13: $(basename "$f") should carry no tools: line"
done
frontmatter "$repo_root/agents/implementer.md" | grep -qx 'model: sonnet' \
  || fail "TC-13: the implementer should run on sonnet"
frontmatter "$repo_root/agents/reviewer.md" | grep -qx 'model: opus' \
  || fail "TC-13: the reviewer should run on opus"
grep -q '(reviewer on Sonnet)' "$repo_root/skills/build/SKILL.md" \
  || fail "TC-13: build should send its later reviews on sonnet"
plugin_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$repo_root/.claude-plugin/plugin.json")
market_versions=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["metadata"]["version"], d["plugins"][0]["version"])' "$repo_root/.claude-plugin/marketplace.json")
assert_eq "$plugin_version $plugin_version" "$market_versions" "TC-13: both manifests carry one version" || fail "TC-13"

# --- TC-12: every other test file is green on its own ------------------------

self_path="test/cli/harness.test.sh"
ran=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  ran=$((ran + 1))
  out=$("$repo_root/scripts/test" "$f" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || fail "TC-12: scripts/test $f should be green, got exit $rc: $out"
done < <(
  cd "$repo_root" && find test -type f -name '*.test.sh' 2>/dev/null | LC_ALL=C sort | grep -vF "$self_path"
)
[ "$ran" -gt 0 ] || fail "TC-12: found no other test file to run"

# --- TC-14: the plan's statuses hand off cleanly across the skills that use them
#
# The plan file is the registry: its Status line and each phase's status are
# set and read by skills/plan, skills/build, skills/finish, skills/epic and
# agents/implementer.md. This pins the hand-off both ways: no skill sets or
# reads a status missing from skills/plan/SKILL.md's own Status list, no
# status in that list goes unset by every skill, and the phase status
# skills/plan, skills/build and agents/implementer.md use for a phase agree.

plan_skill="$repo_root/skills/plan/SKILL.md"
build_skill="$repo_root/skills/build/SKILL.md"
finish_skill="$repo_root/skills/finish/SKILL.md"
epic_skill="$repo_root/skills/epic/SKILL.md"
implementer_agent="$repo_root/agents/implementer.md"

# the plan template's own Status list: draft, approved, building, ...
plan_statuses=$(grep -m1 '^Status: <' "$plan_skill" \
  | sed -E 's/^Status: <([^>]+)>.*/\1/' | tr '|' '\n' | sed -E 's/^ +| +$//g')

has_plan_status() {
  printf '%s\n' "$plan_statuses" | grep -qxF "$1"
}

# every status a skill sets or reads on the plan's Status line, as it is
# phrased there, should be one skills/plan/SKILL.md names
for v in draft approved building "at the human gate" passed landed "a merge-request link"; do
  has_plan_status "$v" \
    || fail "TC-14: a skill sets/reads Status \`$v\`, missing from skills/plan/SKILL.md's Status list"
done

# skills/epic's own worked example sets a Status too — it should stay within
# that same list
epic_statuses=$(awk -F'|' '/^\| [0-9]+ \|/ { v=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v }' "$epic_skill")
while IFS= read -r v; do
  [ -n "$v" ] || continue
  has_plan_status "$v" \
    || fail "TC-14: skills/epic/SKILL.md's worked example sets Status \`$v\`, missing from skills/plan/SKILL.md's Status list"
done <<EOF
$epic_statuses
EOF

# every status in that list is set by some skill
while IFS= read -r v; do
  [ -n "$v" ] || continue
  case "$v" in
    draft)                  tr '\n' ' ' < "$plan_skill" | grep -q 'written with Status `draft`' ;;
    approved)               grep -q 'Status to `approved`' "$plan_skill" ;;
    building)               grep -q '`building`' "$build_skill" ;;
    "at the human gate")    grep -q 'Status to `at the human gate`' "$build_skill" ;;
    passed)                 grep -q 'Status to `passed`' "$build_skill" ;;
    "a merge-request link") grep -q 'a merge-request link' "$finish_skill" ;;
    landed)                 grep -q 'Status to `landed`' "$finish_skill" ;;
    *) false ;;
  esac || fail "TC-14: skills/plan/SKILL.md's Status list names \`$v\`, but no skill sets it"
done <<EOF
$plan_statuses
EOF

# the phase status each phase line carries: waiting, in progress, done
phase_statuses=$(grep -m1 -- '<n>\. <task>' "$plan_skill" \
  | sed -E 's/.*— `<([^>]+)>`.*/\1/' | tr '|' '\n' | sed -E 's/^ +| +$//g')

# skills/build sets it when a phase starts and finishes
while IFS= read -r v; do
  [ -n "$v" ] || continue
  case "$v" in
    "in progress") grep -qi 'mark it `in progress`' "$build_skill" ;;
    done)          grep -qi 'mark it `done`' "$build_skill" ;;
    waiting)       grep -qi 'mark it `waiting`' "$build_skill" ;;
    *) false ;;
  esac || fail "TC-14: skills/plan/SKILL.md's phase status list names \`$v\`, but skills/build/SKILL.md never sets it"
done <<EOF
$phase_statuses
EOF

# agents/implementer.md never sets a phase status of its own that disagrees
# with skills/plan/SKILL.md's phase list
implementer_phase_statuses=$(grep -oiE 'mark it `[^`]+`' "$implementer_agent" | grep -oE '`[^`]+`' | tr -d '`')
while IFS= read -r v; do
  [ -n "$v" ] || continue
  printf '%s\n' "$phase_statuses" | grep -qxF "$v" \
    || fail "TC-14: agents/implementer.md sets a phase status \`$v\` that disagrees with skills/plan/SKILL.md's phase list"
done <<EOF
$implementer_phase_statuses
EOF

echo "ok"
