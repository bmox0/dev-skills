#!/usr/bin/env bash
# The CLI's leftovers in pipeline.py: checks outside the lock, gate start's order, rounds and re-drive briefs, the port lock, the docstring.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "leftovers.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
. "$repo_root/test/cli/lifecycle.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# newrepo FULL [ISO_PORT]: a normal-level plan with one phase done, full = FULL (a TOML list body).
newrepo() {
  repo=$(cd "$(mktemp_dir)" && pwd -P)
  cd "$repo" || exit 1
  git init -q
  mkdir -p .runweld/workflow/plans skills/tdd src
  touch skills/tdd/SKILL.md
  echo a > src/a.txt
  git add -A && git commit -q -m base
  git tag v0
  plan=$repo/.runweld/workflow/plans/2026-11-16-l.md
  cat > "$plan" <<'P'
# Plan: l

Status: draft · branch `l` · base `<sha>`
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

## Spec

+ build — Build
  About: The build.
+ build#checks-by-code — Checks
  Why: a test
  Done: 1
P
  cp "$repo_root/skills/run-file/references/example.run.toml" "${plan%.md}.run.toml"
  python3 - "${plan%.md}.run.toml" "$1" "${2:-true}" <<'PY'
import sys, re
p, full, port = sys.argv[1:]
s = open(p).read()
s = re.sub(r'(?m)^full = .*$', f'full = [{full}]', s)
s = re.sub(r'(?m)^port = .*$', f'port = {port}', s)
if port == 'false':
    s = re.sub(r'(?m)^(dev|url) = .*\n', '', s)
open(p, "w").write(s)
PY
  approve_plan "$plan" >/dev/null || fail "approve"
  cli build start "$plan" --base v0 >/dev/null || fail "build start"
  cli phase start "$plan" 1 >/dev/null || fail "phase start"
  echo r > src/p.txt
  git add src && git commit -q -m p1 -- src
  report_phase "$plan" 1 --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "report"
  cli phase done "$plan" 1 >/dev/null || fail "phase done"
}
json() { cli status --json "$plan" | python3 -c "import json,sys; c=json.load(sys.stdin); $1"; }
commit() { echo "$1" >> src/a.txt; git commit -q -m "$1" -- src/a.txt; git rev-parse HEAD; }

# build#checks-by-code: the checks run outside the plan lock and each result is recorded as it ends
mark=$(mktemp_dir)/go
newrepo "\"echo first\", \"test -e $mark || sleep 23\""
cli gate start "$plan" >"$repo/gate.out" 2>&1 &
pid=$!
for _ in $(seq 100); do json 'sys.exit(0 if c["cycles"] and len(c["cycles"][0]["runs"][-1]["commands"]) == 1 else 1)' 2>/dev/null && break; sleep 0.1; done
out=$(perl -e 'alarm 10; exec @ARGV' python3 -B "$pipeline" note add "$plan" --text n --cause bug 2>&1); rc=$?
assert_eq 0 "$rc" "note add succeeds while the checks run: $out" || exit 1
out=$(cli gate start "$plan"); rc=$?
assert_eq 1 "$rc" "a second gate start refuses while the first one runs" || exit 1
assert_contains "$out" "checks-running" "the refusal's code" || exit 1
disown "$pid"; pkill -9 -P "$pid"; kill -9 "$pid"; pkill -9 -f "sleep 23"; sleep 0.3
out=$(cli status "$plan")
assert_contains "$out" "unfinished, 1 of 2 ran" "status shows the run unfinished" || exit 1
out=$(cli brief reviewer "$plan"); rc=$?
assert_eq 1 "$rc" "a brief that needs the run refuses" || exit 1
assert_contains "$out" "checks-unfinished" "the refusal's code" || exit 1
touch "$mark"
out=$(cli gate start "$plan"); rc=$?
assert_eq 0 "$rc" "the next gate start runs them again: $out" || exit 1
assert_contains "$out" "checks at" "it shows the run" || exit 1
case "$out" in *reused*|*unfinished*) fail "a fresh run, not a reused one: $out";; esac
json 'r=c["cycles"][0]["runs"]; assert len(r) == 1 and r[0]["done"] and len(r[0]["commands"]) == 2, r' || fail "one finished run replaces the unfinished one"

# gate start checks the run values before it commits anything
newrepo '"true"'
python3 - "${plan%.md}.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); del s["run"]
open(sys.argv[1], "w").write(json.dumps(s))
PY
before=$(git rev-parse HEAD)
out=$(cli gate start "$plan"); rc=$?
assert_eq 1 "$rc" "gate start without run values is refused" || exit 1
assert_contains "$out" "run-stale" "the missing approved snapshot invalidates consent" || exit 1
assert_eq "$before" "$(git rev-parse HEAD)" "nothing was committed" || exit 1
json 'assert not c["cycles"]' || fail "no cycle was opened"

# a round: both verdicts' notes, a round with no commit
newrepo '"true"'
cli gate start "$plan" >/dev/null || fail "gate start"
cli brief verify --cases 2 "$plan" >"$repo/b1.out" || fail "brief verify 1"
b1=$(cat "$repo/b1.out"); cp "$b1" "$repo/b1.keep"
cli brief verify --cases 2 "$plan" >"$repo/b2.out" || fail "brief verify 2"
b2=$(cat "$repo/b2.out")
[ "$b1" != "$b2" ] || fail "two verify briefs, two files"
cmp -s "$b1" "$repo/b1.keep" || fail "the first brief is unchanged"
grep -q '^2\. ' "$b2" || fail "the second brief holds case 2"
cli result "$plan" --case 1 --outcome passed --capture 'fixture output 1' >/dev/null || fail "fixture result 1"
cli result "$plan" --case 2 --outcome passed --capture 'fixture output 2' >/dev/null || fail "fixture result 2"
complete_review "$plan" || fail "complete review"
cli verdict round "$plan" --report r1 --note "first" bug --predicted round --predict p bug --engine claude >/dev/null || fail "verdict 1"
cli verdict round "$plan" --report r2 --note "second" feel-ui >/dev/null || fail "verdict 2"
out=$(cli round start "$plan"); rc=$?
assert_eq 0 "$rc" "round start: $out" || exit 1
assert_contains "$out" "takes notes 1, 2" "the round takes both verdicts' notes" || exit 1
json 'assert all(v["round"] == 1 for v in c["verdicts"]), c["verdicts"]' || fail "both verdicts point at the round"
cli round report "$plan" --became nothing >/dev/null || fail "round report without a commit"
b=$(cli brief reviewer "$plan") || fail "brief reviewer"
grep -q 'made no commit' "$b" || fail "the reviewer brief says the round made no commit: $(grep Range "$b")"
cli round done "$plan" >/dev/null || fail "round done"

# run#isolated: two build starts at once pick two ports; a merged plan gets none
repo=$(cd "$(mktemp_dir)" && pwd -P); cd "$repo" || exit 1
git init -q; mkdir -p .runweld/workflow/plans src; echo a > src/a.txt; git add -A; git commit -q -m base; git tag v0
for x in a b; do
  cat > .runweld/workflow/plans/2026-11-16-$x.md <<P
# Plan: $x

Status: draft · branch \`$x\` · base \`<sha>\`
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
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — x

## Done

1. a → b

## Spec

+ build — Build
  About: The build.
+ build#checks-by-code — Checks
  Why: a test
  Done: 1
P
  cp "$repo_root/skills/run-file/references/example.run.toml" .runweld/workflow/plans/2026-11-16-$x.run.toml
  approve_plan .runweld/workflow/plans/2026-11-16-$x.md >/dev/null || fail "approve $x"
done
cli build start --base v0 --worktree "$repo/wa" .runweld/workflow/plans/2026-11-16-a.md >/dev/null &
p1=$!
cli build start --base v0 --worktree "$repo/wb" .runweld/workflow/plans/2026-11-16-b.md >/dev/null &
p2=$!
wait "$p1"; wait "$p2"
pa=$(python3 -c 'import json; print(json.load(open(".runweld/workflow/plans/2026-11-16-a.json"))["alloc"]["port"])')
pb=$(python3 -c 'import json; print(json.load(open(".runweld/workflow/plans/2026-11-16-b.json"))["alloc"]["port"])')
[ -n "$pa" ] && [ "$pa" != "$pb" ] || fail "two plans started at once get two ports: $pa $pb"

newrepo '"true"' false
rm "${plan%.md}.json"
sed -i.bak 's/^Status: building/Status: merged/' "$plan"; rm "$plan.bak"
cli approve "$plan" >/dev/null || fail "adopt completed history"
sed -i.bak 's/^port = false/port = true/' "${plan%.md}.run.toml"; rm -f "${plan%.md}.run.toml.bak"
cli approve "$plan" >/dev/null || fail "compile completed history"
json 'assert "port" not in (c["alloc"] or {}), c["alloc"]' || fail "a merged plan gets no port"

# the docstring names every command --help lists
python3 - "$pipeline" <<'PY' || fail "the docstring names every command --help lists"
import re, subprocess, sys
src = sys.argv[1]
doc = re.search(r'"""(.*?)"""', open(src).read(), re.S)[1]
usage = doc.split("Usage:")[1].split("\n\n")[0].splitlines()
text = "\n".join(usage)
def help_of(*a):
    return subprocess.run([sys.executable, "-B", src, *a, "--help"], capture_output=True, text=True).stdout
groups = re.search(r"\{([^}]*)\}", help_of())[1].split(",")
missing = []
for g in groups:
    if not re.search(rf"pipeline\.py {g}\b", text):
        missing.append(g)
        continue
    m = re.search(rf"usage: pipeline\.py {g}(?: \[-h\])?\s+\{{([^}}]*)\}}", help_of(g))
    subs = m[1].split(",") if m else []
    lines = " ".join(l for l in usage if re.search(rf"\b{g}\b", l))
    missing += [f"{g} {s}" for s in subs if not re.search(rf"\b{s}\b", lines)]
assert not missing, missing
PY
echo ok
