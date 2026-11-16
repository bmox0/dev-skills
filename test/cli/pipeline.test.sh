#!/usr/bin/env bash
# approve, the state file, the render, status and the plan commands of pipeline.py,
# in a throwaway repo.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "pipeline.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
# edit FILE OLD NEW: replace one exact string
edit() { python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a in s, a; open(p, "w").write(s.replace(a, b, 1))' "$@"; }

repo=$(mktemp_dir)
cd "$repo" || exit 1
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git commit -q --allow-empty -m base
mkdir -p .ai-workflow/plans .ai-workflow/epics docs/spec skills/tdd
touch skills/tdd/SKILL.md docs/spec/build.md
printf '# Epic\n\n## Plans\n\n| # | Plan | Waits for | Status |\n|---|---|---|---|\n| 1 | One | — | |\n| 2 | Two | 1 | |\n' > .ai-workflow/epics/e.md
epic_before=$(sed -n 1,7p .ai-workflow/epics/e.md)

plan=.ai-workflow/plans/2026-11-16-x.md
cat > "$plan" <<'P'
# Plan: x

Status: draft · branch `x` · base `<sha>`
Epic: `.ai-workflow/epics/e.md` · row 1
Prototype: none

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. One — `waiting`

Do.
Territory: `src/`, `a.txt`
Skills: `skills/tdd/SKILL.md`
Spec: none
Waits for: nothing

### 2. Two — `waiting`

Do.
Territory: `src/b/`
Skills: `skills/tdd/SKILL.md`, `skills/nope/SKILL.md`
Spec: `docs/spec/build.md`
Waits for: 9 — a thing

### 3. Three — `waiting`

Territory: `src/c`
Skills: none
Spec: none
Waits for: 1

## Checks

- Gate: normal — logic

## Done

1. a → b

## Spec

none
P

# build#state-through-commands: a broken plan gives one line per problem and no JSON
out=$(cli approve "$plan"); rc=$?
assert_eq 1 "$rc" "approve refuses a broken plan" || exit 1
assert_eq 3 "$(printf '%s\n' "$out" | grep -c "^$plan:[0-9]*: ")" "one line per problem: $out" || exit 1
assert_contains "$out" "phase 2 waits for phase 9" "names the missing phase" || exit 1
assert_contains "$out" "skills/nope/SKILL.md does not exist" "names the missing skill" || exit 1
assert_contains "$out" "phases 1 and 2 both change" "names the unordered overlap" || exit 1
[ ! -e "${plan%.md}.json" ] || fail "no JSON after a refusal"

edit "$plan" 'Waits for: 9 — a thing' 'Waits for: 1 — a thing'
edit "$plan" ', `skills/nope/SKILL.md`' ''
draft=$(cat "$plan")
out=$(cli approve "$plan"); rc=$?
assert_eq 0 "$rc" "approve passes: $out" || exit 1
last=$(printf '%s\n' "$out" | tail -1)
[[ "$last" =~ ^"1 → 2 ∥ 3 · normal · "[0-9]+" words"$ ]] || fail "the last line: $last"
[ -f "${plan%.md}.json" ] || fail "the JSON exists"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${plan%.md}.json" || fail "the JSON parses"
changed=$(diff <(printf '%s\n' "$draft") "$plan" | grep '^[<>]' | cut -c1-17)
assert_eq "$(printf '< Status: draft ·\n> Status: approve\n> Rendered from `')" "$changed" "the render touches only Status and its line: $changed" || exit 1
assert_eq "approved · \`.ai-workflow/plans/2026-11-16-x.md\`" "$(sed -n 7p .ai-workflow/epics/e.md | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')" "the epic row follows approve" || exit 1
assert_eq "$(sed -n 1,6p .ai-workflow/epics/e.md)" "$(printf '%s\n' "$epic_before" | sed -n 1,6p)" "the epic is otherwise untouched" || exit 1
assert_eq "| 2 | Two | 1 | |" "$(sed -n 8p .ai-workflow/epics/e.md)" "the other row is untouched" || exit 1

# build#state-through-commands: status, base and the epic row
cli plan status "$plan" building --note "start" >/dev/null || fail "plan status"
cli plan base "$plan" HEAD >/dev/null || fail "plan base"
sha=$(git rev-parse HEAD)
grep -q "^Status: building · branch \`x\` · base \`$sha\`$" "$plan" || fail "the Status line follows the commands"
assert_contains "$(sed -n 7p .ai-workflow/epics/e.md)" "building ·" "the epic row follows" || exit 1
out=$(cli status "$plan")
assert_contains "$out" "Ready: 1" "phase 1 is ready" || exit 1
assert_contains "$out" "start" "the note shows" || exit 1
out=$(cli plan status "$plan" nonsense); rc=$?
assert_eq 1 "$rc" "a value outside the list is refused" || exit 1
assert_contains "$out" "bad-status:" "code form" || exit 1
assert_contains "$out" "— fix:" "fix form" || exit 1

# build#state-through-commands: a hand edit of a code-owned line: writes refuse naming the command, status still prints
edit "$plan" 'Status: building' 'Status: passed'
out=$(cli plan status "$plan" merged); rc=$?
assert_eq 1 "$rc" "a write refuses on drift" || exit 1
assert_contains "$out" "drift:" "drift code" || exit 1
assert_contains "$out" "pipeline.py plan status" "names the command" || exit 1
out=$(cli status "$plan"); rc=$?
assert_eq 0 "$rc" "status prints on drift" || exit 1
assert_contains "$out" "Drift:" "status shows the drift" || exit 1
out=$(cli approve "$plan"); rc=$?
assert_eq 1 "$rc" "approve refuses an edited code-owned line" || exit 1
assert_contains "$out" "pipeline.py plan status" "approve names the command" || exit 1
edit "$plan" 'Status: passed' 'Status: building'

# build#state-through-commands: a text edit: writes refuse, approve recompiles and keeps the statuses
edit "$plan" '1. a → b' '1. a → b
2. c → d'
out=$(cli plan status "$plan" passed); rc=$?
assert_eq 1 "$rc" "a write refuses after a text edit" || exit 1
assert_contains "$out" "pipeline.py approve" "names approve" || exit 1
cli approve "$plan" >/dev/null || fail "approve recompiles"
grep -q '^Status: building · ' "$plan" || fail "the status is kept"
cli plan status "$plan" passed >/dev/null || fail "writes work again"
cli plan status "$plan" building >/dev/null

# the lock: parallel writers all land
for i in 1 2 3 4 5 6; do git commit -q --allow-empty -m "c$i"; git tag "t$i"; done
for i in 1 2 3 4 5 6; do cli plan base "$plan" "t$i" --note "w$i" >/dev/null & done
wait
python3 - "${plan%.md}.json" <<'PY' || fail "every parallel write is recorded"
import json, sys
notes = [e["note"] for e in json.load(open(sys.argv[1]))["history"] if e["note"] and e["note"].startswith("w")]
assert sorted(notes) == ["w1", "w2", "w3", "w4", "w5", "w6"], notes
PY
grep -q '^Status: building' "$plan" || fail "the plan is still rendered"

# a started phase may not vanish
python3 -B - "$pipeline" "$plan" <<'PY'
import sys; sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
import pipeline
plan = sys.argv[2]
with pipeline.writing(plan) as st:
    pipeline.set_phase(plan, st, 1, "done", "test")
    print("ready", pipeline.ready_phases(st))
PY
grep -q '^### 1. One — `done`$' "$plan" || fail "set_phase renders the heading"
cp "$plan" "$plan.bak"
python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); i=s.index("### 1."); j=s.index("### 2."); open(p,"w").write(s[:i]+s[j:])' "$plan"
edit "$plan" '### 2. Two' '### 1. Two'
edit "$plan" '### 3. Three' '### 2. Three'
edit "$plan" 'Waits for: 1 — a thing' 'Waits for: nothing'
out=$(cli approve "$plan"); rc=$?
assert_eq 1 "$rc" "approve refuses a renumbered started phase" || exit 1
assert_contains "$out" "phase-gone:" "refused as gone: $out" || exit 1
case "$out" in *"edited by hand"*) fail "not a hand-edit refusal: $out";; esac
cp "$plan.bak" "$plan"; rm "$plan.bak"

# build#pre-5-1-adopted: a plan with no state is adopted as its file stands
old=.ai-workflow/plans/2026-11-10-old.md
cat > "$old" <<'P'
# Plan: old

Status: building · branch `old` · base `abc1234`

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. First — `done`

Territory: `src/`
Skills: none
Spec: none
Waits for: nothing

### 2. Second — `in progress`

Territory: `lib/`
Skills: none
Spec: none
Waits for: 1

### 3. Third — `waiting`

Territory: `src/`
Skills: none
Spec: none
Waits for: 1, 2

## Checks

- Gate: small — looks

## Done

1. a → b

## Spec

none
P
out=$(cli plan status "$old" passed); rc=$?
assert_eq 1 "$rc" "a plan with no state is refused" || exit 1
assert_contains "$out" "pipeline.py approve" "the fix names approve" || exit 1
out=$(cli approve "$old"); rc=$?
assert_eq 0 "$rc" "approve adopts: $out" || exit 1
assert_contains "$out" "overlaps 2026-11-16-x (building): src/" "names the overlapping plan" || exit 1
grep -q '^### 1. First — `done`$' "$old" || fail "phase 1 stays done"
grep -q '^Status: building · branch `old` · base `abc1234`$' "$old" || fail "status is kept"
out=$(cli status "$old")
assert_contains "$out" "Ready: none" "phase 3 waits for phase 2" || exit 1
case "$out" in *None*) fail "an unset previous value prints as a dash: $out";; esac
assert_contains "$out" "phase 2 — → in progress" "an unset previous value prints as a dash" || exit 1
cli status | grep -q "2026-11-10-old — building" || fail "status of all plans"

# the Human gate part of the file is not touched
printf '\n## Human gate\n\nwritten by hand\n' >> "$old"
cli plan status "$old" "at the human gate" >/dev/null || fail "a hand-written gate is not drift"
tail -2 "$old" | grep -q 'written by hand' || fail "the gate stays as written"

# status lists plans only: no briefs or gate logs, and no approve fix for a merged plan without state
plans=.ai-workflow/plans
printf 'x\n' > "$plans/2026-11-16-x.brief-judge.md"
printf 'x\n' > "$plans/2026-11-16-x.brief-implementer-1.md"
printf 'x\n' > "$plans/2026-11-10-old.gate-log.md"
printf '# Plan: m\n\nStatus: merged · branch `m` · base `abc1234`\n' > "$plans/2026-11-01-m.md"
out=$(cli status)
case "$out" in *brief*|*gate-log*) fail "status lists only plans: $out";; esac
case "$out" in *2026-11-01-m*) fail "status leaves out a merged plan: $out";; esac
printf '# Plan: nb\n\nStatus: building · branch `nb` · base `abc1234`\n' > "$plans/2026-11-02-nb.md"
printf '# Plan: dr\n\nStatus: draft · branch `dr` · base `<sha>`\n' > "$plans/2026-11-03-dr.md"
out=$(cli status)
assert_contains "$out" "2026-11-02-nb — no state — fix: run \`pipeline.py approve\`" "a building plan without state shows with its fix" || exit 1
case "$out" in *2026-11-03-dr*) fail "status leaves out a draft plan: $out";; esac
cli status --json | python3 -c 'import json,sys; n=[r["plan"] for r in json.load(sys.stdin)]; assert "2026-11-01-m" not in n and "2026-11-03-dr" not in n, n' || fail "--json lists the same plans"

# a small valid plan: mkp FILE BRANCH EPIC-LINE [APPROACH-EXTRA]
mkp() {
  set -- "$1" "$2" "${3:-}" "${4:-}" "${5:-}"
  cat > "$1" <<P
# Plan: $2

Status: draft · branch \`$2\` · base \`<sha>\`
$3

## Result

R.

## Approach

A.
$4

## Out of scope

- n

## Phases

### 1. One — \`waiting\`

Do one.
$5
Territory: \`src/\`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — x

## Done

1. a → b

## Spec

none
P
}

# status without a plan lists building to passed; a named plan always shows
mkp "$plans/2026-11-04-ap.md" ap ''
cli approve "$plans/2026-11-04-ap.md" >/dev/null || fail "approve ap"
case "$(cli status)" in *2026-11-04-ap*) fail "status leaves out an approved plan";; esac
assert_contains "$(cli status "$plans/2026-11-04-ap.md")" "approved" "a named plan shows" || exit 1
assert_contains "$(cli status --help)" "building" "--help says which plans" || exit 1

# build#epic-row-follows: the row sits in the Plans table, keeps its cell format, and parallel plans of one epic both land
cat > .ai-workflow/epics/e2.md <<'E'
# Epic

| # | Note |
|---|---|
| 1 | not the plans table |

## Plans

| # | Plan | Waits for | Status |
|---|---|---|---|
| 1 | One | — | |
| 2 | Two | 1 | building · `.ai-workflow/plans/old.md` |
| 3 | Three | 2 | |
E
e2=.ai-workflow/epics/e2.md
mkp "$plans/2026-11-05-p1.md" p1 'Epic: `.ai-workflow/epics/e2.md` · row 1'
mkp "$plans/2026-11-05-p2.md" p2 'Epic: `.ai-workflow/epics/e2.md` · row 2'
cli approve "$plans/2026-11-05-p1.md" >/dev/null || fail "approve p1"
cli approve "$plans/2026-11-05-p2.md" >/dev/null || fail "approve p2"
assert_contains "$(cat $e2)" '| 1 | not the plans table |' "a row outside the Plans table is untouched" || exit 1
assert_contains "$(cat $e2)" '| 1 | One | — | approved · `.ai-workflow/plans/2026-11-05-p1.md` |' "an empty cell gets the epic's shape" || exit 1
assert_contains "$(cat $e2)" '| 2 | Two | 1 | approved · `.ai-workflow/plans/2026-11-05-p2.md` |' "a filled cell keeps its shape" || exit 1
for s in building "at the human gate" passed building "at the human gate" passed building passed; do
  cli plan status "$plans/2026-11-05-p1.md" "$s" >/dev/null &
  cli plan status "$plans/2026-11-05-p2.md" "$s" >/dev/null &
  wait
  assert_contains "$(cat $e2)" "| 1 | One | — | $s · " "row 1 holds $s" || exit 1
  assert_contains "$(cat $e2)" "| 2 | Two | 1 | $s · " "row 2 holds $s" || exit 1
done

# the row names the plan relative to the tree, also through a symlinked path
link=$(mktemp_dir)/link
ln -s "$(pwd -P)" "$link"
mkp "$plans/2026-11-05-p3.md" p3 'Epic: `.ai-workflow/epics/e2.md` · row 3'
cli approve "$link/.ai-workflow/plans/2026-11-05-p3.md" >/dev/null || fail "approve p3 through a link"
assert_contains "$(cat $e2)" '| 3 | Three | 2 | approved · `.ai-workflow/plans/2026-11-05-p3.md` |' "the row path is relative through a symlink" || exit 1

# fenced blocks are text: a heading or Status line in one is neither parsed nor rewritten
fence='
```text
### 2. Fake — `waiting`
Territory: `nowhere/`
### 1. One — `waiting`
```'
pf="$plans/2026-11-06-pf.md"
mkp "$pf" pf '' "$fence" "$fence"
out=$(cli approve "$pf"); rc=$?
assert_eq 0 "$rc" "approve ignores a fenced phase heading: $out" || exit 1
python3 -B - "$pipeline" "$pf" <<'PY' || fail "set_phase"
import sys; sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
import pipeline
with pipeline.writing(sys.argv[2]) as st:
    pipeline.set_phase(sys.argv[2], st, 1, "done", "test")
PY
assert_eq 2 "$(grep -c '^### 1. One — `waiting`$' "$pf")" "the fenced heading copies keep their text" || exit 1
edit "$pf" 'Do one.' 'Do one, again.'
out=$(cli plan status "$pf" passed); rc=$?
assert_eq 1 "$rc" "a text edit refuses the write" || exit 1
case "$out" in *"edited by hand"*) fail "a fenced heading is not a hand edit: $out";; esac
assert_contains "$out" "pipeline.py approve" "the fix is approve" || exit 1
echo "pipeline.test.sh: ok"
