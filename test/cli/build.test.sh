#!/usr/bin/env bash
# build start, phase start / report / done, owner, grant, decision and brief of
# pipeline.py, in throwaway repos.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "build.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }

repo=$(cd "$(mktemp_dir)" && pwd -P)
cd "$repo" || exit 1
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p .ai-workflow/plans .ai-workflow/epics docs/spec skills/tdd src lib other
touch skills/tdd/SKILL.md docs/spec/build.md
printf '# Epic\n\n## Plans\n\n| # | Plan | Waits for | Status |\n|---|---|---|---|\n| 1 | One | — | |\n' > .ai-workflow/epics/e.md
git commit -q --allow-empty -m base
git tag v0
v0=$(git rev-parse v0)
git commit -q --allow-empty -m later

mkplan() { # mkplan FILE [EPIC-LINE]
  cat > "$1" <<P
# Plan: x

Status: draft · branch \`$3\` · base \`<sha>\`
$2
Prototype: none

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. One — \`waiting\`

Do one.
Territory: \`src/\`
Skills: \`skills/tdd/SKILL.md\`
Spec: none
Waits for: nothing

### 2. Two — \`waiting\`

Do two.
Territory: \`lib/\`
Skills: \`skills/tdd/SKILL.md\`
Spec: \`docs/spec/build.md\`
Waits for: 1 — the src

### 3. Three — \`waiting\`

Territory: \`other/\`
Skills: none
Spec: none
Waits for: 2

## Checks

- Gate: small — x

## Done

1. a → b

## Spec

none
P
}

plan=$repo/.ai-workflow/plans/2026-11-16-x.md
mkplan "$plan" 'Epic: `.ai-workflow/epics/e.md` · row 1' x
cli approve "$plan" >/dev/null || fail "approve"

# build#base-is-named: build start refuses to run without --base
cli build start "$plan" 2>/dev/null; rc=$?
assert_eq 2 "$rc" "build start requires --base" || exit 1

# build#base-is-named, build#epic-row-follows
out=$(cli build start "$plan" --base v0); rc=$?
assert_eq 0 "$rc" "build start: $out" || exit 1
assert_contains "$out" "dirty" "reports the dirty tree" || exit 1
assert_eq "$v0" "$(git rev-parse x)" "the branch starts at the tag" || exit 1
assert_eq x "$(git branch --show-current)" "the branch is checked out" || exit 1
grep -q "^Status: building · branch \`x\` · base \`$v0\`$" "$plan" || fail "Status line: $(grep ^Status "$plan")"
assert_contains "$(sed -n 7p .ai-workflow/epics/e.md)" "building ·" "the epic row follows" || exit 1
assert_contains "$(cli status "$plan")" "Ready: 1" "phase 1 is ready" || exit 1
cli build start "$plan" --base v0 >/dev/null; rc=$?
assert_eq 1 "$rc" "a second build start is refused" || exit 1

# --worktree
planw=$repo/.ai-workflow/plans/2026-11-16-w.md
mkplan "$planw" '' w
cli approve "$planw" >/dev/null || fail "approve w"
wt=$(dirname "$repo")/$(basename "$repo")-wt
out=$(cli build start "$planw" --base v0 --worktree "$wt"); rc=$?
assert_eq 0 "$rc" "build start --worktree: $out" || exit 1
assert_eq w "$(git -C "$wt" branch --show-current)" "the worktree has the branch" || exit 1
assert_eq x "$(git branch --show-current)" "the main checkout stays" || exit 1
assert_contains "$(cli brief implementer "$planw" 1 | xargs cat)" "$wt" "the brief names the worktree" || exit 1
git worktree remove --force "$wt"

# build#phase-done-checked
cli phase done "$plan" 1 >/dev/null; rc=$?
assert_eq 1 "$rc" "phase done needs a started phase" || exit 1
cli phase start "$plan" 1 >/dev/null || fail "phase start 1"
out=$(cli phase done "$plan" 1); rc=$?
assert_eq 1 "$rc" "phase done needs a report" || exit 1
assert_contains "$out" "report" "names the missing report" || exit 1
echo a > src/a.txt; echo o > docs/out.txt
git add src/a.txt docs/out.txt && git commit -q -m "p1" -- src/a.txt docs/out.txt
c1=$(git rev-parse HEAD)
echo s > src/staged.txt; git add src/staged.txt
cli phase report "$plan" 1 --became "src exists" --skills "tdd" --interfaces "none" --checks "ok" --commit "$c1" >/dev/null || fail "report"
out=$(cli phase done "$plan" 1); rc=$?
assert_eq 1 "$rc" "phase done refuses: $out" || exit 1
assert_contains "$out" "docs/out.txt" "names the path outside the territory" || exit 1
assert_contains "$out" "src/staged.txt" "names the staged path" || exit 1
grep -q '^### 1. One — `in progress`$' "$plan" || fail "the phase stays in progress"

# owner and grants: a running phase owns its territory
assert_contains "$(cli owner "$plan" src/new.txt)" "phase 1" "owner names the running phase" || exit 1
assert_contains "$(cli owner "$plan" lib/x)" "none" "no owner for a waiting phase's path" || exit 1

# build#act-with-a-reason
out=$(cli phase start "$plan" 3); rc=$?
assert_eq 1 "$rc" "phase 3 before phase 2 is done is refused" || exit 1
assert_contains "$out" "— fix:" "fix form" || exit 1
cli phase start "$plan" 3 --note "ahead of 2 on purpose" >/dev/null || fail "phase start with a note"
assert_contains "$(cli status "$plan")" "ahead of 2 on purpose" "status shows the note" || exit 1
out=$(cli grant "$plan" 3 src/a.txt); rc=$?
assert_eq 1 "$rc" "a grant on another running phase's path is refused" || exit 1
assert_contains "$out" "phase 1" "names the owner" || exit 1

cli grant "$plan" 1 docs/out.txt >/dev/null || fail "grant"
git commit -q -m "staged" -- src/staged.txt
c2=$(git rev-parse HEAD)
cli phase report "$plan" 1 --became "src exists" --skills "tdd" --interfaces "none" --checks "ok" --commit "$c1" --commit "$c2" >/dev/null || fail "report again"
out=$(cli phase done "$plan" 1); rc=$?
assert_eq 0 "$rc" "phase done passes: $out" || exit 1
assert_contains "$out" "ready: 2" "phase 2 is ready" || exit 1
grep -q '^### 1. One — `done`$' "$plan" || fail "phase 1 is done"

# build#act-with-a-reason: a commit that is not on the branch after the base
cli phase start "$plan" 1 >/dev/null; rc=$?
assert_eq 1 "$rc" "starting a done phase needs a note" || exit 1
cli phase start "$plan" 1 --note "redo" >/dev/null || fail "backward with a note"
grep -q '^### 1. One — `in progress`$' "$plan" || fail "phase 1 is back"
python3 - "${plan%.md}.json" "$(git rev-parse HEAD)" <<'PY' || fail "the backward move records HEAD"
import json, sys
h = [e for e in json.load(open(sys.argv[1]))["history"] if e["note"] == "redo"][0]
assert h["sha"] == sys.argv[2] and h["from"] == "done" and h["to"] == "in progress", h
PY
cli phase report "$plan" 1 --became x --commit "$v0" >/dev/null
out=$(cli phase done "$plan" 1); rc=$?
assert_eq 1 "$rc" "a commit before the base is refused" || exit 1
cli phase report "$plan" 1 --became "src exists" --commit "$c1" --commit "$c2" >/dev/null
cli phase done "$plan" 1 >/dev/null || fail "done again"

# records: parallel decisions all land
for i in 1 2 3 4; do
  cli decision "$plan" --question "q$i?" --from "orchestrator" --answer "a$i" --why "w$i" --cost "c$i" --phase 1 >/dev/null &
done
wait
python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["decisions"]; assert sorted(x["question"] for x in d)==["q1?","q2?","q3?","q4?"], d' "${plan%.md}.json" || fail "every decision is recorded"
out=$(cli status "$plan")
for w in "q2?" "a2" "w2" "c2" "orchestrator"; do assert_contains "$out" "$w" "status lists the decision: $w" || exit 1; done

# briefs
out=$(cli brief implementer "$plan" 2 --note "mind the lib"); rc=$?
assert_eq 0 "$rc" "brief implementer: $out" || exit 1
[ -f "$out" ] || fail "the brief is a file: $out"
case "$out" in /*) ;; *) fail "the path is absolute: $out";; esac
b=$(cat "$out")
for w in "$plan" "$repo" "$pipeline" "$v0" "$(git rev-parse HEAD)" "lib/" "skills/tdd/SKILL.md" "src exists" "mind the lib" "Do two." "Branch: x"; do
  assert_contains "$b" "$w" "the brief holds $w" || exit 1
done
out=$(cli brief judge "$plan" --note "case: gate"); rc=$?
assert_eq 0 "$rc" "brief judge: $out" || exit 1
j=$(grep -o '/[^ `]*judge\.md' "$out" | head -1)
[ -f "$j" ] || fail "the judge.md path exists: $j"
assert_eq "$repo_root/skills/build/references/judge.md" "$j" "the plugin's judge.md" || exit 1

# build#pre-5-1-adopted: no command but approve runs on a plan with no state
old=$repo/.ai-workflow/plans/2026-11-10-old.md
mkplan "$old" '' old
sed -i.bak 's/^Status: draft · branch `old` · base `<sha>`/Status: building · branch `old` · base `abc1234`/; s/^### 1. One — `waiting`/### 1. One — `done`/' "$old"; rm "$old.bak"
out=$(cli phase start "$old" 2); rc=$?
assert_eq 1 "$rc" "phase start on a plan with no state is refused" || exit 1
assert_contains "$out" "pipeline.py approve" "the fix names approve" || exit 1
cli approve "$old" >/dev/null || fail "adopt"
grep -q '^### 1. One — `done`$' "$old" || fail "phase 1 stays done"
assert_contains "$(cli status "$old")" "Ready: 2" "phase 2 is ready" || exit 1

# build#base-is-named: the branch has a command when its name is taken
plany=$repo/.ai-workflow/plans/2026-11-16-y.md
mkplan "$plany" '' x
cli approve "$plany" >/dev/null || fail "approve y"
out=$(cli build start "$plany" --base v0); rc=$?
assert_eq 1 "$rc" "a taken branch is refused" || exit 1
assert_contains "$out" "build start --branch" "the fix is a command that exists" || exit 1
cli build start "$plany" --base v0 --branch y >/dev/null || fail "build start --branch"
grep -q "^Status: building · branch \`y\` · base \`$v0\`$" "$plany" || fail "Status line: $(grep ^Status "$plany")"
git switch -q x

# build#act-with-a-reason: an approved plan has no branch; phase start needs a note
planw2=$repo/.ai-workflow/plans/2026-11-16-w2.md
mkplan "$planw2" '' w2
cli approve "$planw2" >/dev/null || fail "approve w2"
out=$(cli phase start "$planw2" 1); rc=$?
assert_eq 1 "$rc" "phase start on an approved plan is refused" || exit 1
assert_contains "$out" "not-building:" "code form" || exit 1
cli phase start "$planw2" 1 --note "no branch yet" >/dev/null || fail "phase start with a note"

# a plan adopted mid-build gets the worktree where its branch is checked out
git branch adopt v0
wta=$(dirname "$repo")/$(basename "$repo")-adopt
git worktree add -q "$wta" adopt
plana=$repo/.ai-workflow/plans/2026-11-16-a.md
mkplan "$plana" '' adopt
sed -i.bak 's/^Status: draft · branch `adopt` · base `<sha>`/Status: building · branch `adopt` · base `'"$v0"'`/' "$plana"; rm "$plana.bak"
cli approve "$plana" >/dev/null || fail "adopt a"
assert_contains "$(cli status "$plana")" "Tree: $wta" "status prints the worktree" || exit 1
assert_contains "$(cli brief implementer "$plana" 1 | xargs cat)" "Tree: $wta" "the brief names the worktree" || exit 1

# reads report drift; a hand-edited phase heading is not a traceback
edit() { python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a in s, a; open(p, "w").write(s.replace(a, b, 1))' "$@"; }
edit "$plana" 'Do one.' 'Do one, differently.'
assert_contains "$(cli owner "$plana" src/x)" "Drift:" "owner reports drift" || exit 1
out=$(cli brief implementer "$plana" 1); rc=$?
assert_eq 1 "$rc" "brief refuses uncompiled phase text" || exit 1
assert_contains "$out" "drift:" "names the drift" || exit 1
edit "$plana" '### 1. One — `waiting`' '### 1 One'
out=$(cli brief implementer "$plana" 1 2>&1); rc=$?
assert_eq 1 "$rc" "brief refuses a hand-edited heading" || exit 1
case "$out" in *Traceback*) fail "no traceback: $out";; esac
assert_contains "$(cli brief judge "$plana" --note c | xargs cat)" "Drift:" "the judge brief reports drift" || exit 1
git worktree remove --force "$wta"

# a recorded tree that is gone: refuse cleanly, and the closing writes keep working
planz=$repo/.ai-workflow/plans/2026-11-16-z.md
mkplan "$planz" '' z
cli approve "$planz" >/dev/null || fail "approve z"
wtz=$(dirname "$repo")/$(basename "$repo")-z
cli build start "$planz" --base v0 --worktree "$wtz" >/dev/null || fail "build start z"
cli phase start "$planz" 1 >/dev/null || fail "phase start z"
git worktree remove --force "$wtz"
for c in "phase done $planz 1" "owner $planz src/a" "brief implementer $planz 1"; do
  out=$(cli $c 2>&1); rc=$?
  assert_eq 1 "$rc" "$c with the tree gone: $out" || exit 1
  assert_contains "$out" "tree-gone:" "$c: code form" || exit 1
  case "$out" in *Traceback*) fail "no traceback: $out";; esac
done
assert_contains "$(cli status "$planz")" "(gone)" "status says the tree is gone" || exit 1
cli plan status "$planz" "at the human gate" >/dev/null || fail "a write works without the tree"
cli plan status "$planz" merged >/dev/null || fail "merged works without the tree"

# phase done: a base that is not a commit is an error
planb=$repo/.ai-workflow/plans/2026-11-16-b.md
mkplan "$planb" '' b
cli approve "$planb" >/dev/null || fail "approve b"
cli build start "$planb" --base v0 >/dev/null || fail "build start b"
cli phase start "$planb" 1 >/dev/null || fail "phase start b"
mkdir -p src; echo b > src/b.txt; git add src/b.txt; git commit -q -m b -- src/b.txt
cli phase report "$planb" 1 --became b --commit "$(git rev-parse HEAD)" >/dev/null || fail "report b"
python3 -B - "$pipeline" "$planb" <<'PY'
import sys; sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
import pipeline
with pipeline.writing(sys.argv[2]) as st:
    st["base"] = "0" * 40
PY
out=$(cli phase done "$planb" 1); rc=$?
assert_eq 1 "$rc" "phase done refuses a base that is no commit" || exit 1
assert_contains "$out" "bad-base:" "names the base: $out" || exit 1
# build#phase-done-checked: a merge commit counts by what it brought into the branch
planm=$repo/.ai-workflow/plans/2026-11-16-m.md
mkplan "$planm" '' mg
cli approve "$planm" >/dev/null || fail "approve m"
cli build start "$planm" --base v0 >/dev/null || fail "build start m"
cli phase start "$planm" 1 >/dev/null || fail "phase start m"
mkdir -p src; echo m > src/m.txt; git add src/m.txt; git commit -q -m m1 -- src/m.txt
cm1=$(git rev-parse HEAD)
git switch -q -c side v0
mkdir -p docs; echo s > docs/side.txt; git add docs/side.txt; git commit -q -m side -- docs/side.txt
git switch -q mg
git merge -q --no-ff side -m merge
cmerge=$(git rev-parse HEAD)
cli phase report "$planm" 1 --became m --commit "$cm1" --commit "$cmerge" >/dev/null || fail "report m"
out=$(cli phase done "$planm" 1); rc=$?
assert_eq 1 "$rc" "a merge commit's paths are checked: $out" || exit 1
assert_contains "$out" "docs/side.txt" "names the path the merge brought in" || exit 1

# grants are stored relative to the tree, and a path outside it is refused
out=$(cli grant "$planm" 1 /etc/hosts); rc=$?
assert_eq 1 "$rc" "a grant outside the tree is refused" || exit 1
assert_contains "$out" "outside-tree:" "code form" || exit 1
assert_contains "$out" "— fix:" "fix form" || exit 1
out=$(cli grant "$planm" 1 ../elsewhere); rc=$?
assert_eq 1 "$rc" "a relative path out of the tree is refused" || exit 1
cli grant "$planm" 1 "$repo/docs/side.txt" >/dev/null || fail "grant by absolute path"
assert_contains "$(cli status "$planm")" "grants: docs/side.txt" "the grant is stored relative" || exit 1
out=$(cli phase done "$planm" 1); rc=$?
assert_eq 0 "$rc" "phase done passes with the grant: $out" || exit 1
echo "build.test.sh: ok"
