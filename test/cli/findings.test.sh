#!/usr/bin/env bash
# finding, result, fix and the briefs of pipeline.py, in a throwaway repo.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "findings.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
. "$repo_root/test/cli/lifecycle.sh"

repo=$(cd "$(mktemp_dir)" && pwd -P)
cd "$repo" || exit 1
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p .runweld/workflow/plans skills/tdd src
touch skills/tdd/SKILL.md
echo a > src/a.txt
git add -A && git commit -q -m base
git tag v0

plan=$repo/.runweld/workflow/plans/2026-11-16-f.md
cat > "$plan" <<'P'
# Plan: f

Status: draft · branch `f` · base `<sha>`
Prototype: none

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. One — `waiting`

Do one.
Territory: `src/`
Skills: `skills/tdd/SKILL.md`
Spec: none
Waits for: nothing

## Checks

- Gate: small — x

## Done

1. a → b
2. c → d
3. e → f — you check

## Spec

+ build — Build
  About: The build.
+ build#findings-recorded — Findings are recorded
  Why: a test
  Done: 1
P
cp "$repo_root/skills/run-file/references/example.run.toml" "${plan%.md}.run.toml"
python3 - "${plan%.md}.run.toml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'(?m)^full = .*$', 'full = ["test ! -e src/red.txt"]', s)
open(p, "w").write(s)
PY
approve_plan "$plan" >/dev/null || fail "approve"
cli build start "$plan" --base v0 >/dev/null || fail "build start"
cli phase start "$plan" 1 >/dev/null || fail "phase start"
echo r > src/red.txt
git add src/red.txt && git commit -q -m p1 -- src/red.txt
report_phase "$plan" 1 --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "report"
cli gate start "$plan" >/dev/null && fail "gate start with a phase open is refused"
cli gate start --note "early" "$plan" >/dev/null || fail "gate start --note opens the gate with a phase open"
assert_contains "$(cli status "$plan")" "early" "status shows the gate's note" || exit 1
cli phase done "$plan" 1 >/dev/null || fail "phase done"
mkdir -p docs/spec && echo x > docs/spec/other.md
git add docs/spec/other.md && git commit -q -m "spec by hand" -- docs/spec/other.md
cli gate start "$plan" >/dev/null || fail "gate start"

json() { cli status --json "$plan" | python3 -c "import json,sys; c=json.load(sys.stdin); $1"; }

# approve keeps the Done items and their marks
json "assert [(d['n'], d['you_check']) for d in c['done']] == [(1, False), (2, False), (3, True)], c['done']" || fail "done items"

# build#findings-recorded: the three lists and what could not be judged
cli finding "$plan" --kind defect --where src/a.txt:1 --source AGENTS.md --text "first defect" | grep -q 'finding: D1' || fail "finding id"
cli finding "$plan" --kind defect --where src/a.txt:2 --source plan --text "second defect" >/dev/null || fail "second defect"
cli finding "$plan" --kind convention --where src/a.txt:3 --source AGENTS.md --text "a convention" >/dev/null || fail "convention"
cli finding "$plan" --kind observation --where src/a.txt:4 --source plan --text "an observation" >/dev/null || fail "observation"
cli finding "$plan" --kind unjudged --text "the base is gone" >/dev/null || fail "unjudged"
cli finding "$plan" --kind defect --text "no place" >/dev/null && fail "a defect without file:line is refused"

# results: a capture is required for passed and failed
cli result "$plan" --case 1 --outcome passed >/dev/null && fail "a passed result without a capture is refused"
cli result "$plan" --case 1 --outcome passed --capture shot1.png >/dev/null || fail "result 1"
cli result "$plan" --case 2 --outcome failed --detail "saw the wrong thing" --capture shot2.png --width 390 >/dev/null || fail "result 2"
cli result "$plan" --case 3 --outcome not-reached --detail "needs a login" >/dev/null || fail "result 3"
cli result "$plan" --case 9 --outcome passed --capture x >/dev/null && fail "an unknown case is refused"

out=$(cli status "$plan")
assert_contains "$out" "D1 src/a.txt:1 — first defect (AGENTS.md)" "defects as review returns them" || exit 1
assert_contains "$out" "Conventions:" "conventions" || exit 1
assert_contains "$out" "Observations:" "observations" || exit 1
assert_contains "$out" "the base is gone" "what could not be judged" || exit 1
assert_contains "$out" "2. c → d — 390 — failed: saw the wrong thing — shot2.png" "a result in verify's line" || exit 1
assert_contains "$out" "3. e → f — - — not reached: needs a login" "a case not reached" || exit 1

# the one list: a spec refusal naming docs/spec/, the red check, both Defects and the failed case, nothing else
json "assert [i['id'] for i in c['cycles'][0]['list']] == ['spec', 'check-1', 'D1', 'D2', 'done-2'], c['cycles'][0]['list']" || fail "the one list"

# --cases at the gate before any fix: the listed cases are the brief
b=$(cli brief verify "$plan" --cases 2) || fail "brief verify --cases at the gate"
grep -q "2\. c → d" "$b" && ! grep -q "1\. a → b" "$b" || fail "at the gate --cases names only the listed cases"
grep -q "exactly as written, one shell call per case" "$b" || fail "verify says how to run a command"
b=$(cli brief verify "$plan") || fail "brief verify at the gate"
grep -q "1\. a → b" "$b" || fail "without --cases the gate drives every case"
b=$(cli brief reviewer "$plan") || fail "brief reviewer at the gate"
grep -q "python3 \"$pipeline\" finding $plan --kind" "$b" || fail "the reviewer's record command is printed in full"
sed -n '/## Record/,$p' "$b" | grep -q '\$' && fail "the reviewer's brief uses no shell variable"
grep -q "only when there is one" "$b" && grep -q "record nothing" "$b" || fail "the reviewer records an unjudged item only when there is one: $(grep unjudged "$b")"

# build#survivor-to-open: fix 1 takes everything open
complete_review "$plan" || fail "complete the gate review"
cli fix report "$plan" --became x --commit abc >/dev/null && fail "no fix to report on"
cli fix start "$plan" >/dev/null || fail "fix start"
cli fix start "$plan" >/dev/null && fail "a second fix while one is open is refused"
brief=$(cli brief fix "$plan") || fail "brief fix"
grep -q "src/a.txt:1" "$brief" || fail "the brief holds each item's file:line"
grep -q "second defect" "$brief" || fail "the brief holds each item's text"
grep -q "python3 \"$pipeline\" fix report $plan --became" "$brief" || fail "the fix brief's record command is printed in full"
sed -n '/## Record/,$p' "$brief" | grep -q '\$' && fail "the fix brief uses no shell variable"
cli fix done "$plan" >/dev/null && fail "fix done before a report is refused"
git rm -q src/red.txt docs/spec/other.md && git commit -q -m fix1 -- src/red.txt docs/spec/other.md
f1=$(git rev-parse HEAD)
cli fix report "$plan" --became "removed the red file" --commit "$f1" >/dev/null || fail "fix report"
out=$(cli fix done "$plan") || fail "fix done: $out"
assert_contains "$out" "green" "fix done re-runs the full checks at the new HEAD" || exit 1
json "c=c['cycles'][0]; assert c['runs'][-1]['head'] == '$(git rev-parse HEAD)' and len(c['runs']) == 3" || fail "the re-check run"
json "c=c['cycles'][0]; assert [i['id'] for i in c['list']] == ['D1', 'D2', 'done-2'] and c['fixes'][0]['survived'] == [], c['fixes']" || fail "after fix 1"

# each fix's re-check briefs have names of their own; the gate's stay
gb=$(cli brief reviewer "$plan") || fail "re-check reviewer"
gv=$(cli brief verify "$plan") || fail "re-check verify"
case "$gb" in *brief-reviewer-gate-fix-1.md) ;; *) fail "the re-check reviewer brief is named for the fix: $gb" ;; esac
case "$gv" in *brief-verify-gate-fix-1.md) ;; *) fail "the re-check verify brief is named for the fix: $gv" ;; esac
[ -f "${plan%.md}.brief-reviewer-gate.md" ] && [ -f "${plan%.md}.brief-verify-gate.md" ] || fail "the gate's briefs are not overwritten"

# Done 2 fails again, D2 is found again, and a new Defect: those two survive
cli result "$plan" --case 2 --outcome failed --detail "still wrong" --capture shot3.png >/dev/null || fail "result again"
cli finding "$plan" --kind defect --where src/a.txt:1 --source AGENTS.md --text "first again" --again D2 >/dev/null || fail "again"
cli finding "$plan" --kind defect --where src/a.txt:9 --source plan --text "new defect" | grep -q 'finding: D4' || fail "a finding found again takes an id of its own, so the new Defect is D4"
json "c=c['cycles'][0]; assert sorted(c['fixes'][0]['survived']) == ['D2', 'done-2'], c['fixes']" || fail "survivors"
out=$(cli status "$plan")
assert_contains "$out" "survived fix 1" "status shows the fate" || exit 1
assert_contains "$out" "taken by fix 1" "an item taken, not yet found again" || exit 1

# the next fix takes only the new Defect
complete_review "$plan" || fail "complete the first fix review"
cli fix start "$plan" >/dev/null || fail "fix 2"
json "c=c['cycles'][0]; assert c['fixes'][1]['items'] == ['D4'], c['fixes']" || fail "fix 2 takes the new Defect only"
cli fix report "$plan" --became y --commit deadbeef >/dev/null || fail "report with a commit"
cli fix done "$plan" >/dev/null && fail "fix done still refuses a given commit that is not on the branch"
cli fix report "$plan" --became y >/dev/null || fail "a fix that changed nothing reports with no commit"
cli fix done "$plan" >/dev/null || fail "fix done with no commit"

# build#caps-in-code: the cap
out=$(cli fix start "$plan"); rc=$?
assert_eq 1 "$rc" "fix start at the cap is refused" || exit 1
assert_contains "$out" "fixes-spent" "the refusal's code" || exit 1
out=$(cli status "$plan")
assert_contains "$out" "fix 2" "status shows each fix" || exit 1

# briefs after the fixes
b=$(cli brief verify "$plan" --cases 1) || fail "brief verify"
grep -q "2\. c → d" "$b" && grep -q "1\. a → b" "$b" || fail "verify names the failed case and the added one"
grep -q "3\. e" "$b" && fail "verify names nothing else"
b=$(cli brief reviewer "$plan") || fail "brief reviewer"
grep -q "made no commit" "$b" || fail "the re-check says the fix made no commit"
grep -q "Range: .*\.\." "$b" && fail "no empty range is printed"
grep -q "D4" "$b" || fail "the reviewer's brief names the items the fix took"
grep -q "Checks at\|checks at" "$b" || fail "the reviewer's brief holds the last check run"
cli result "$plan" --case 2 --outcome passed --capture ok.png >/dev/null || fail "result passed"
b=$(cli brief verify "$plan") || fail "brief verify with none"
grep -q "no case to drive" "$b" || fail "nothing failed, nothing to drive"
echo "findings.test.sh: ok"
