#!/usr/bin/env bash
# verdict, note, round, the caps and the early stop of pipeline.py, in throwaway repos.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "rounds.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# newrepo: a repo with a normal-level plan at the opened gate; $1 = "red" starts with a red check.
newrepo() {
  repo=$(cd "$(mktemp_dir)" && pwd -P)
  cd "$repo" || exit 1
  git init -q
  mkdir -p .ai-workflow/plans skills/tdd src
  touch skills/tdd/SKILL.md
  echo a > src/a.txt
  git add -A && git commit -q -m base
  git tag v0
  plan=$repo/.ai-workflow/plans/2026-11-16-r.md
  cat > "$plan" <<'P'
# Plan: r

Status: draft · branch `r` · base `<sha>`
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

- Gate: normal — x

## Done

1. a → b
2. c → d
3. e → f — you check

## Spec

+ build — Build
  About: The build.
+ build#caps-in-code — Caps
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
  cli approve "$plan" >/dev/null || fail "approve"
  cli build start "$plan" --base v0 >/dev/null || fail "build start"
  cli phase start "$plan" 1 >/dev/null || fail "phase start"
  if [ "${1:-}" = red ]; then echo r > src/red.txt; else echo r > src/p.txt; fi
  git add src && git commit -q -m p1 -- src
  cli phase report "$plan" 1 --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "report"
  cli phase done "$plan" 1 >/dev/null || fail "phase done"
  cli gate start "$plan" >/dev/null || fail "gate start"
}
json() { cli status --json "$plan" | python3 -c "import json,sys; c=json.load(sys.stdin); $1"; }
commit() { echo "$1" >> src/a.txt; git commit -q -m "$1" -- src/a.txt; git rev-parse HEAD; }
vfirst=(--predicted pass --predict n1 feel-ui --engine claude)

# build#judge-file-by-code, build#notes-in-their-words
newrepo
out=$(cli brief judge "$plan"); rc=$?
assert_eq 1 "$rc" "brief judge above small is refused while a case has no result" || exit 1
assert_contains "$out" "result-missing" "the refusal's code" || exit 1
cli result "$plan" --case 1 --outcome passed --capture shot1.png >/dev/null || fail "result 1"
cli result "$plan" --case 2 --outcome failed --detail "wrong" --capture shot2.png >/dev/null || fail "result 2"
cli fix start "$plan" >/dev/null || fail "fix start"
f1=$(commit fix1)
cli fix report "$plan" --became x --commit "$f1" >/dev/null || fail "fix report"
cli fix done "$plan" >/dev/null || fail "fix done"
cli finding "$plan" --kind convention --where src/a.txt:1 --source AGENTS.md --text "a convention" >/dev/null || fail "convention"
cli finding "$plan" --kind defect --where src/a.txt:2 --source plan --text "a defect" >/dev/null || fail "defect"
b=$(cli brief judge "$plan") || fail "brief judge"
for want in "$repo_root/skills/build/references/judge.md" "shot1.png" "shot2.png" "a convention" "Fix 1" "Open:" "$(git rev-parse --short "$f1")" "checks at"; do
  grep -q -- "$want" "$b" || fail "the gate's judge brief holds: $want"
done
gate_brief=$(cat "$b")
out=$(cli verdict pass "$plan" --report r "${vfirst[@]}"); rc=$?
assert_eq 1 "$rc" "a verdict leaving an entry undecided is refused" || exit 1
assert_contains "$out" "C1" "the refusal names the Convention" || exit 1
assert_contains "$out" "D1" "the refusal names the Open entry" || exit 1
cli verdict pass "$plan" --report "let through" --decide D1 let-through "minor" --decide C1 let-through "style" \
  --predicted round --predict "first note" feel-ui --predict "second" code-taste --engine claude | grep -q "verdict 1" || fail "verdict pass"
judge=$repo/.ai-workflow/plans/2026-11-16-r.judge.md
grep -q '^# Judge: r$' "$judge" || fail "judge file title"
grep -Eq "^Plan: \`2026-11-16-r\` · head \`$(git rev-parse --short HEAD)\` · [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z · engine claude$" "$judge" || fail "judge file header: $(sed -n 3p "$judge")"
grep -q "^P2\. second — code-taste$" "$judge" || fail "the Prediction"
keep=$repo/judge.keep; cp "$judge" "$keep"
cli verdict pass "$plan" --report "again" --decide D1 let-through x --decide C1 let-through y >/dev/null || fail "second verdict"
cmp -s "$judge" "$keep" || fail "a later verdict leaves the judge file byte for byte"
assert_eq "$gate_brief" "$(cat "$b")" "the gate brief stays" || exit 1

cli note add "$plan" --text "make the header bigger" --cause feel-ui >/dev/null || fail "note 1"
cli note add "$plan" --text "the label is wrong
second line" --cause bug >/dev/null || fail "note 2"
cli note add "$plan" --text "rework the approach" --cause task >/dev/null || fail "note 3"
notes=$repo/.ai-workflow/plans/2026-11-16-r.notes.md
python3 - "$notes" <<'PY' || fail "notes before a round: $(cat "$notes")"
import sys
t = open(sys.argv[1]).read()
assert t.index("## Open") < t.index("1. make the header bigger — feel-ui") < t.index("2. the label is wrong\nsecond line — bug") < t.index("## Tasks") < t.index("3. rework the approach — task"), t
PY
cli note edit "$plan" 1 --text "make the header much bigger" >/dev/null || fail "note edit"
cli round start "$plan" | grep -q "takes notes 1, 2" || fail "a round takes the open notes, not the task"
cli note edit "$plan" 1 --text x >/dev/null && fail "a note in a round is fixed"
rb=$(cli brief round "$plan") || fail "brief round"
grep -q "2026-11-16-r.notes.md" "$rb" && grep -q "much bigger" "$rb" || fail "brief round names the notes file and the notes"
c1=$(commit r1)
cli round report "$plan" --became x --commit "$c1" >/dev/null || fail "round report"
cli round done "$plan" >/dev/null && fail "round done needs a source for the user's notes"
cli note edit "$plan" 1 --source P1 >/dev/null || fail "source 1"
cli note edit "$plan" 2 --source missed >/dev/null || fail "source 2"
cli result "$plan" --case 1 --outcome passed --capture r1.png >/dev/null || fail "round result"
cli round done "$plan" | grep -q "round 1 done" || fail "round done"
grep -q "^## Round 1 · \`$(git rev-parse --short "$c1")\`$" "$notes" || fail "one-commit heading: $(cat "$notes")"
grep -q "much bigger — feel-ui — P1 — \`$(git rev-parse --short "$c1")\` — e2e: Done 1 passed" "$notes" || fail "a done note's line: $(cat "$notes")"

cli note add "$plan" --text "third" --cause bug >/dev/null || fail "note 4"
cli round start "$plan" >/dev/null || fail "round 2"
c2=$(commit r2); c3=$(commit r3)
cli round report "$plan" --became x --commit "$c2" --commit "$c3" >/dev/null || fail "round 2 report"
cli note edit "$plan" 4 --source missed >/dev/null || fail "source 4"
cli round done "$plan" >/dev/null || fail "round 2 done"
grep -q "^## Round 2 · \`$(git rev-parse --short "$c2")..$(git rev-parse --short "$c3")\`$" "$notes" || fail "range heading: $(cat "$notes")"

# build#judge-reads-the-round: a new file with the judge file, the round's notes and its re-check only
cli result "$plan" --case 1 --outcome passed --capture r2.png >/dev/null || fail "round 2 result"
rb2=$(cli brief judge "$plan") || fail "brief judge after a round"
[ "$rb2" != "$b" ] || fail "a new file after a round"
grep -q "2026-11-16-r.judge.md" "$rb2" && grep -q "third" "$rb2" && grep -q "r2.png" "$rb2" || fail "the round brief holds the judge file, the notes and the re-check"
grep -q "shot2.png\|c → d" "$rb2" && fail "the round brief holds no other Done result"
grep -q "Re-check verify: Done 1 passed" "$rb2" || fail "the round brief states the re-check's verify outcome: $(grep -i verify "$rb2")"
b=$(cli brief verify "$plan") || fail "brief verify on a round"
grep -q "no case to drive" "$b" || fail "a round re-check drives nothing unless named"
b=$(cli brief verify "$plan" --cases 1) || fail "brief verify --cases"
grep -q "1\. a → b" "$b" || fail "a round re-check drives the named case"
b=$(cli brief reviewer "$plan") || fail "brief reviewer on a round"
from=$(json "print(c['rounds'][1]['from'])")
grep -q "^Range: $from\.\.HEAD" "$b" || fail "the round reviewer's range starts where the round did: $(grep Range: "$b")"

# a judge's round takes only the judge's notes, in the judge's words, source judge
cli note add "$plan" --text "user waits" --cause bug >/dev/null || fail "note 5"
cli verdict round "$plan" --report r --note "judge note one" bug --note "judge note two" off-plan >/dev/null || fail "verdict round"
cli round start "$plan" | grep -q "(judge): takes notes 6, 7" || fail "the judge's round takes the judge's notes"
c4=$(commit r4)
cli round report "$plan" --became x --commit "$c4" >/dev/null || fail "round 3 report"
cli round done "$plan" >/dev/null || fail "a judge round needs no source"
grep -q "judge note one — bug — judge — \`$(git rev-parse --short "$c4")\`" "$notes" || fail "judge note line: $(cat "$notes")"
grep -q "^5\. user waits — bug$" "$notes" || fail "the user's note waits under Open"
out=$(cli status "$plan")
assert_contains "$out" "Round 3 (judge)" "status shows the rounds" || exit 1
rb3=$(cli brief judge "$plan") || fail "brief judge after round 3"
grep -q "Re-check verify: no case to drive" "$rb3" || fail "build#judge-reads-the-round: a round that touched no case says so: $(grep -i verify "$rb3")"
h=$(cli verdict --help)
for want in let-through question "first verdict"; do assert_contains "$h" "$want" "verdict --help holds: $want" || exit 1; done

# build#caps-in-code: the cap
newrepo
cli verdict round "$plan" --report r --note a1 bug --note a2 bug --note a3 bug "${vfirst[@]}" >/dev/null || fail "v1"
cli verdict round "$plan" --report r --note b1 bug --note b2 bug >/dev/null || fail "v2"
cli verdict round "$plan" --report r --note c1 bug >/dev/null || fail "v3"
out=$(cli verdict round "$plan" --report r --note d1 bug) || fail "a stopped verdict still records"
assert_contains "$out" "past the cap" "the cap stops the fourth"  || exit 1
assert_contains "$(cli status "$plan")" "Stopped: judge rounds are past the cap" "status shows the reason" || exit 1
json "assert c['rounds'] == [], c['rounds']" || fail "a stopped verdict opens no round"
grep -q "d1" "$repo/.ai-workflow/plans/2026-11-16-r.notes.md" && fail "build#caps-in-code: a stopped verdict's notes are not the user's open notes"
assert_contains "$(cli status "$plan")" "d1" "the stopped verdict's notes stay visible in status" || exit 1
cli note add "$plan" --text "user round" --cause bug >/dev/null
cli round start "$plan" | grep -q "(user)" || fail "after a stop the user's round is the user's"
c=$(commit u1)
cli round report "$plan" --became x --commit "$c" >/dev/null
cli note edit "$plan" 7 --source missed >/dev/null
cli round done "$plan" >/dev/null || fail "user round done"
out=$(cli verdict round "$plan" --report r --note e1 bug)
assert_contains "$out" "verdict 5: round at" "the count starts afresh after a user's round" || exit 1
case $out in *stopped*) fail "not stopped after a user's round";; esac

# build#caps-in-code: the first sign: rounds that leave no fewer new notes than they took, twice
newrepo
cli verdict round "$plan" --report r --note a1 bug "${vfirst[@]}" >/dev/null || fail "s1 v1"
cli verdict round "$plan" --report r --note b1 bug >/dev/null || fail "s1 v2"
out=$(cli verdict round "$plan" --report r --note c1 bug)
assert_contains "$out" "stopped converging" "the first sign" || exit 1

# build#caps-in-code: the second sign: a check fixed before is red again
newrepo red
cli fix start "$plan" >/dev/null || fail "s2 fix"
git rm -q src/red.txt && git commit -q -m fixred -- src/red.txt
cli fix report "$plan" --became x --commit "$(git rev-parse HEAD)" >/dev/null
cli fix done "$plan" | grep -q "checks at.*green" || fail "s2 green after the fix"
cli verdict round "$plan" --report r --note a1 bug "${vfirst[@]}" >/dev/null || fail "s2 v1"
cli round start "$plan" >/dev/null || fail "s2 round"
echo r > src/red.txt; git add src/red.txt; git commit -q -m again -- src/red.txt
cli round report "$plan" --became x --commit "$(git rev-parse HEAD)" >/dev/null
cli round done "$plan" | grep -q "red" || fail "s2 red again"
out=$(cli verdict round "$plan" --report r --note b1 bug --decide check-1 round x)
assert_contains "$out" "a check fixed before is red again" "the second sign" || exit 1

# build#caps-in-code: the third sign: a cycle's fixes are spent and a Defect stands
newrepo
cli finding "$plan" --kind defect --where src/a.txt:1 --source plan --text d1 >/dev/null
cli fix start "$plan" >/dev/null || fail "s3 fix 1"
c=$(commit s3a); cli fix report "$plan" --became x --commit "$c" >/dev/null; cli fix done "$plan" >/dev/null
cli finding "$plan" --kind defect --where src/a.txt:2 --source plan --text d2 >/dev/null
cli fix start "$plan" >/dev/null || fail "s3 fix 2"
c=$(commit s3b); cli fix report "$plan" --became x --commit "$c" >/dev/null; cli fix done "$plan" >/dev/null
cli finding "$plan" --kind defect --where src/a.txt:2 --source plan --text d2again --again D2 >/dev/null
out=$(cli verdict round "$plan" --report r --note a1 bug --decide D2 round x "${vfirst[@]}")
assert_contains "$out" "fixes are spent and a Defect stands: D2" "the third sign" || exit 1

# build#caps-in-code: the judge's rounds all ran, the stopped verdict's notes start no round
newrepo
for i in 1 2; do
  if [ $i = 1 ]; then cli verdict round "$plan" --report r --note "j$i" bug "${vfirst[@]}" >/dev/null; else cli verdict round "$plan" --report r --note "j$i" bug --note "k$i" bug --note "l$i" bug >/dev/null; fi
  cli round start "$plan" >/dev/null || fail "stop: round $i"
  c=$(commit "q$i"); cli round report "$plan" --became x --commit "$c" >/dev/null; cli round done "$plan" >/dev/null
done
cli verdict round "$plan" --report r --note "stopped note" bug --note s2 bug --note s3 bug | grep -q "round stopped" || fail "the third verdict stops converging"
cli round start "$plan" >/dev/null && fail "build#caps-in-code: a stopped verdict's notes start no round"

# build#caps-in-code: a dropped note does not crash the first round verdict or leave an empty judge file
newrepo
cli note add "$plan" --text u1 --cause bug >/dev/null; cli note add "$plan" --text u2 --cause bug >/dev/null
cli note drop "$plan" 1 >/dev/null
cli verdict round "$plan" --report r --note "judge says" bug "${vfirst[@]}" >/dev/null || fail "build#judge-file-by-code: a round verdict after a dropped note"
grep -q "judge says" "$repo/.ai-workflow/plans/2026-11-16-r.judge.md" || fail "build#judge-file-by-code: the judge file holds the verdict"

# build#findings-recorded, build#survivor-to-open: a check fixed and red again stays open
newrepo red
cli fix start "$plan" >/dev/null
git rm -q src/red.txt && git commit -q -m fixred -- src/red.txt
cli fix report "$plan" --became x --commit "$(git rev-parse HEAD)" >/dev/null
cli fix done "$plan" >/dev/null
cli finding "$plan" --kind defect --where src/a.txt:1 --source plan --text nd >/dev/null
cli fix start "$plan" >/dev/null
echo r > src/red.txt; git add src/red.txt; git commit -q -m again -- src/red.txt
cli fix report "$plan" --became x --commit "$(git rev-parse HEAD)" >/dev/null
cli fix done "$plan" >/dev/null
assert_contains "$(cli status "$plan")" "check-1 (open, survived fix 1)" "build#survivor-to-open: the check red again is open" || exit 1
cli result "$plan" --case 1 --outcome passed --capture a.png >/dev/null; cli result "$plan" --case 2 --outcome passed --capture b.png >/dev/null
out=$(cli verdict pass "$plan" --report r --decide D1 let-through x "${vfirst[@]}" 2>&1)
assert_contains "$out" "check-1 has no decision" "build#survivor-to-open: a verdict must decide the check red again" || exit 1

# build#findings-recorded: a result records its commit; status labels each cycle
newrepo
cli result "$plan" --case 1 --outcome passed --capture a.png >/dev/null
json "assert c['cycles'][0]['results'][0]['commit'] == '$(git rev-parse HEAD)', c['cycles'][0]['results']" || fail "build#findings-recorded: a result carries its commit"
cli finding "$plan" --kind observation --where src/a.txt:1 --source x --text "gate obs" >/dev/null
cli note add "$plan" --text n --cause bug >/dev/null
cli round start "$plan" >/dev/null
cli finding "$plan" --kind observation --where src/a.txt:1 --source x --text "round obs" >/dev/null
out=$(cli status "$plan")
assert_contains "$out" "Cycle gate" "status labels the gate's lists" || exit 1
assert_contains "$out" "Cycle round-1" "status labels the round's lists" || exit 1

# build#state-through-commands: the fix and round briefs carry the ruling command, the rules path and the Spec entries
b=$(cli brief round "$plan")
for want in "decision" "--by implementer" "build#caps-in-code" "carries its ID"; do grep -q -- "$want" "$b" || fail "the round brief holds: $want"; done
cli finding "$plan" --kind defect --where src/a.txt:1 --source plan --text d >/dev/null
cli fix start "$plan" >/dev/null || fail "fix start in a round"
b=$(cli brief fix "$plan")
for want in "decision" "--by implementer" "build#caps-in-code" "carries its ID"; do grep -q -- "$want" "$b" || fail "the fix brief holds: $want"; done
grep -q "^Rules: .*docs/spec" "$b" || fail "the brief header names where the rules live"

# build#judge-file-by-code: a judge after the user's answer is told so, and names the judge file
newrepo
cli result "$plan" --case 1 --outcome passed --capture a.png >/dev/null; cli result "$plan" --case 2 --outcome passed --capture b.png >/dev/null
cli verdict question "$plan" --report r --question "which colour?" "${vfirst[@]}" >/dev/null || fail "verdict question"
cli brief judge "$plan" >/dev/null && fail "an answer brief needs the answer"
b=$(cli brief judge --note "the user said blue" "$plan") || fail "brief judge after an answer"
grep -q "^Case: after the user's answer" "$b" && grep -q "2026-11-16-r.judge.md" "$b" && grep -q "which colour?" "$b" && grep -q "the user said blue" "$b" || fail "the answer brief names the case, the judge file, the question and the answer"
# the question and its answer stay in every judge brief until the next verdict is recorded
cli brief judge --note "the user said blue" "$plan" >/dev/null || fail "the same answer briefs again"
for n in "evidence recorded" ""; do
  if [ -n "$n" ]; then b=$(cli brief judge --note "$n" "$plan"); else b=$(cli brief judge "$plan"); fi || fail "a brief after the answer, note '$n'"
  grep -q "^Case: after the user's answer" "$b" && grep -q "which colour?" "$b" && grep -q "The user's answer: the user said blue" "$b" || fail "the question and the recorded answer stay in the brief, note '$n'"
done
cli verdict round "$plan" --report r --note "make it greener" feel-ui "${vfirst[@]}" >/dev/null || fail "a verdict after the answer"
cli round start "$plan" >/dev/null || fail "a round after the answer"
b=$(cli brief judge "$plan") || fail "a round brief after the next verdict needs no note"
! grep -q "Question asked" "$b" || fail "a brief after the next verdict does not print the old question"

# a stale base is the orchestrator's, not a fix item
newrepo
def=$(git branch --format='%(refname:short)' | grep -v '^r$' | head -1)
git checkout -q "$def"; mkdir -p docs/spec; echo "# x" > docs/spec/x.md; git add docs/spec/x.md; git commit -q -m "spec moved" -- docs/spec/x.md
git checkout -q r; git rebase -q "$def" >/dev/null 2>&1 || fail "rebase onto the moved default"
out=$(cli gate start "$plan")
assert_contains "$out" "plan base" "a stale base names the command that fixes it" || exit 1
json "assert 'spec' not in [i['id'] for i in c['cycles'][0]['list']], c['cycles'][0]['list']" || fail "a stale base is not an item for a fix"
# gate.md skips `fix start` with nothing open: the refusal fits an empty list
newrepo
out=$(cli fix start "$plan"); rc=$?
assert_eq 1 "$rc" "fix start with nothing open is refused" || exit 1
assert_contains "$out" "nothing-open" "the code" || exit 1
assert_contains "$out" "empty" "the fix says the list is empty" || exit 1
case "$out" in *"an item a fix took"*) fail "the hint for an empty list does not talk of items a fix took: $out";; esac
echo "rounds.test.sh: ok"
