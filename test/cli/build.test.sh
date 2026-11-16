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
  cp "$repo_root/skills/run-file/references/example.run.toml" "${1%.md}.run.toml"
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
out=$(cli brief judge "$plan"); rc=$?
assert_eq 1 "$rc" "brief judge takes its case from a cycle, and none is open: $out" || exit 1
assert_contains "$out" "no-cycle" "the refusal's code" || exit 1

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

# run#isolated: a port and a data directory of the plan's own
first=$(python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import pipeline; print(pipeline.PORTS.start)' "$(dirname "$pipeline")")
python3 -c 'import socket,sys,time; s=socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(); time.sleep(60)' "$first" &
busy=$!
sleep 1
ports=""
for k in i1 i2; do
  pk=$repo/.ai-workflow/plans/2026-11-16-$k.md
  mkplan "$pk" '' $k
  cli approve "$pk" >/dev/null || fail "approve $k"
  wk=$(dirname "$repo")/$(basename "$repo")-$k
  out=$(cli build start "$pk" --base v0 --worktree "$wk"); rc=$?
  assert_eq 0 "$rc" "build start $k: $out" || exit 1
  pt=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["alloc"]["port"])' "${pk%.md}.json")
  assert_contains "$out" "port $pt" "the port is among the facts" || exit 1
  assert_contains "$out" "$k.data" "the data directory is among the facts" || exit 1
  [ -d "${pk%.md}.data" ] || fail "the data directory exists for $k"
  assert_contains "$(cli status "$pk")" "port $pt" "status shows the port" || exit 1
  assert_contains "$(cli status --json "$pk")" "\"port\": $pt" "status --json holds the allocation" || exit 1
  assert_contains "$(cli run show "$pk")" "--port $pt" "run show fills in {port}" || exit 1
  assert_contains "$(cli run show --json "$pk")" "localhost:$pt" "run show --json fills in {port}" || exit 1
  [ "$pt" != "$first" ] || fail "$k got the busy port"
  case " $ports " in *" $pt "*) fail "$k shares a port";; esac
  ports="$ports $pt"
  git worktree remove --force "$wk"
done
kill $busy 2>/dev/null

# run#isolated: a listener on [::1] holds its port; a one-sided allocation prints and shows only what it has
python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_INET6); s.bind(("::1", int(sys.argv[1]))); s.listen(); time.sleep(60)' "$first" &
busy6=$!
sleep 1
p6=$repo/.ai-workflow/plans/2026-11-16-v6.md
mkplan "$p6" '' v6
sed -i.bak 's/^data_dir = true/data_dir = false/; s/ --data {data_dir}//' "${p6%.md}.run.toml"
grep -q '^data_dir = false' "${p6%.md}.run.toml" || fail "v6 run file edited"
cli approve "$p6" >/dev/null || fail "approve v6"
w6=$(dirname "$repo")/$(basename "$repo")-v6
cli build start "$p6" --base v0 --worktree "$w6" >/dev/null || fail "build start v6"
kill $busy6 2>/dev/null
pt=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["alloc"]["port"])' "${p6%.md}.json")
[ "$pt" != "$first" ] || fail "a port listening on [::1] was counted free"
out=$(cli status "$p6"); rc=$?
assert_eq 0 "$rc" "status with a port and no data dir: $out" || exit 1
assert_contains "$out" "Run: port $pt" "status shows the port" || exit 1
case "$out" in *"data dir"*) fail "status invents a data dir: $out";; esac
git worktree remove --force "$w6"

# run#isolated: a host without IPv6 still has free ports; only "address in use" counts as busy
python3 -B - "$pipeline" "$p6" <<'PY' || fail "a host without IPv6 found no free port"
import errno, importlib.util, socket, sys
spec = importlib.util.spec_from_file_location("pipeline", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = socket.socket
class NoV6(real):
    def __init__(self, family=socket.AF_INET, *a, **k):
        if family == socket.AF_INET6:
            raise OSError(errno.EAFNOSUPPORT, "no IPv6")
        super().__init__(family, *a, **k)
socket.socket = NoV6
m.free_port(None, sys.argv[2])
PY

# run#isolated: a data directory without a port
pd=$repo/.ai-workflow/plans/2026-11-16-d1.md
mkplan "$pd" '' d1
sed -i.bak 's/^port = true/port = false/; s/ --port {port}//; s/{port}/1/' "${pd%.md}.run.toml"
cli approve "$pd" >/dev/null || fail "approve d1"
wd=$(dirname "$repo")/$(basename "$repo")-d1
cli build start "$pd" --base v0 --worktree "$wd" >/dev/null || fail "build start d1"
out=$(cli status "$pd"); rc=$?
assert_eq 0 "$rc" "status with a data dir and no port: $out" || exit 1
assert_contains "$out" "Run: data dir " "status shows the data dir" || exit 1
case "$out" in *"Run: port"*|*" port "*) fail "status invents a port: $out";; esac
git worktree remove --force "$wd"

# run#changes-through-approve: build start shows a changed run file, and keeps the approved values
pc=$repo/.ai-workflow/plans/2026-11-16-bd.md
mkplan "$pc" '' bd
cli approve "$pc" >/dev/null || fail "approve bd"
edit "${pc%.md}.run.toml" 'delete_backups = true' 'delete_backups = false'
wc=$(dirname "$repo")/$(basename "$repo")-bd
out=$(cli build start "$pc" --base v0 --worktree "$wc"); rc=$?
assert_eq 0 "$rc" "build start with a changed run file: $out" || exit 1
assert_contains "$out" "[finish] delete_backups" "build start names the drift: $out" || exit 1
git worktree remove --force "$wc"

# run#changes-through-approve: approve after build start allocates what isolation now asks for
pa=$repo/.ai-workflow/plans/2026-11-16-ia.md
mkplan "$pa" '' ia
sed -i.bak 's/^data_dir = true/data_dir = false/; s/ --data {data_dir}//' "${pa%.md}.run.toml"
cli approve "$pa" >/dev/null || fail "approve ia"
wa=$(dirname "$repo")/$(basename "$repo")-ia
cli build start "$pa" --base v0 --worktree "$wa" >/dev/null || fail "build start ia"
edit "${pa%.md}.run.toml" 'data_dir = false' 'data_dir = true'
edit "${pa%.md}.run.toml" '--port {port}' '--port {port} --data {data_dir}'
out=$(cli approve "$pa"); rc=$?
assert_eq 0 "$rc" "approve after build start: $out" || exit 1
assert_contains "$out" "data dir " "approve prints the new allocation: $out" || exit 1
[ -d "${pa%.md}.data" ] || fail "approve made the data directory"
assert_contains "$(cli run show "$pa")" "--data $(cd "$(dirname "$pa")" && pwd -P)/2026-11-16-ia.data" "run show fills in {data_dir}" || exit 1
git worktree remove --force "$wa"
# a plan with worktree = true needs --worktree, or a note
pw=$repo/.ai-workflow/plans/2026-11-16-wt.md
mkplan "$pw" '' wt
sed -i.bak 's/^worktree = false/worktree = true/' "${pw%.md}.run.toml"
cli approve "$pw" >/dev/null || fail "approve wt"
out=$(cli build start "$pw" --base v0); rc=$?
assert_eq 1 "$rc" "worktree = true without --worktree is refused" || exit 1
assert_contains "$out" "--worktree" "the fix names the flag: $out" || exit 1
cli build start "$pw" --base v0 --note "no room for a tree" >/dev/null || fail "build start with a note"
assert_contains "$(cli status "$pw")" "no room for a tree" "status shows the note" || exit 1
git switch -q mg

# run#secrets-as-written, build#brief-carries-spec
ps=$repo/.ai-workflow/plans/2026-11-16-sp.md
mkplan "$ps" '' sp
python3 - "$ps" <<'PY'
import sys
t = open(sys.argv[1]).read()
t = t.replace("1. a → b\n", "1. a → b\n2. c → d\n3. e → f\n")
t = t.replace("## Spec\n\nnone", "## Spec\n\n+ rr — The area\n  About: a thing\n+ rr#one — Rule one\n  Why: w1\n  Done: 1\n+ rr#two — Rule two\n  Why: w2\n  Done: 2, 3\n")
open(sys.argv[1], "w").write(t)
PY
cli approve "$ps" >/dev/null || fail "approve sp"
b=$(cat "$(cli brief implementer "$ps" 2)")
for w in 'phase = ["scripts/check"]' 'admin_pwd = "keychain:app/admin"' 'can_remove_tasks = false' 'quota = 20' "rr#one" "Rule two" "a → b" "c → d" "e → f"; do
  assert_contains "$b" "$w" "the brief holds $w" || exit 1
done
assert_eq 1 "$(printf '%s\n' "$b" | grep -c '^Territory:')" "Territory prints once" || exit 1

# an epic that is gone is a fact, not a traceback
pe=$repo/.ai-workflow/plans/2026-11-16-ep.md
mkplan "$pe" 'Epic: `.ai-workflow/epics/gone/e.md` · row 1' ep
cli approve "$pe" >/dev/null 2>&1
mkdir -p .ai-workflow/epics/gone && printf '## Plans\n\n| # | P | W | S |\n|---|---|---|---|\n| 1 | One | — | |\n' > .ai-workflow/epics/gone/e.md
cli approve "$pe" >/dev/null || fail "approve ep"
cli build start "$pe" --base v0 >/dev/null || fail "build start ep"
rm -rf .ai-workflow/epics/gone
out=$(cli phase start "$pe" 1 2>&1); rc=$?
assert_eq 0 "$rc" "phase start with the epic gone: $out" || exit 1
assert_contains "$out" "epic" "a line says the epic is missing" || exit 1
case "$out" in *Traceback*) fail "no traceback: $out";; esac
echo "build.test.sh: ok"
