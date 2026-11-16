#!/usr/bin/env bash
# gate start and run show of pipeline.py, in a throwaway repo.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "gate.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }

repo=$(cd "$(mktemp_dir)" && pwd -P)
cd "$repo" || exit 1
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p .ai-workflow/plans skills/tdd src lib outside
touch skills/tdd/SKILL.md
echo a > src/a.txt
git add -A && git commit -q -m base
git tag v0

plan=$repo/.ai-workflow/plans/2026-11-16-g.md
cat > "$plan" <<'P'
# Plan: g

Status: draft · branch `g` · base `<sha>`
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

### 2. Two — `waiting`

Do two.
Territory: `lib/`
Skills: none
Spec: none
Waits for: 1

## Checks

- Gate: small — x

## Done

1. a → b

## Spec

+ build — Build
  About: The build.
+ build#gate-rule — The gate holds
  Why: a test
  Done: 1
P
cp "$repo_root/skills/run-file/references/example.run.toml" "${plan%.md}.run.toml"
python3 - "${plan%.md}.run.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
import re
s = re.sub(r'(?m)^full = .*$', 'full = ["true", "echo boom; echo second line; exit 3", "echo x >> src/a.txt", "test -n {port}"]', s)
open(p, "w").write(s)
PY
cli approve "$plan" >/dev/null || fail "approve"
cli build start "$plan" --base v0 >/dev/null || fail "build start"

# build#checks-by-code: refused before every phase is done, unless given a note
out=$(cli gate start "$plan"); rc=$?
assert_eq 1 "$rc" "gate start before the phases are done is refused" || exit 1
assert_contains "$out" "— fix:" "fix form" || exit 1

phase() { # phase N DIR
  cli phase start "$plan" "$1" >/dev/null || fail "phase start $1"
  echo "p$1" > "$2/f$1.txt"
  git add "$2/f$1.txt" && git commit -q -m "p$1" -- "$2/f$1.txt"
  cli phase report "$plan" "$1" --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "report $1"
  cli phase done "$plan" "$1" >/dev/null || fail "phase done $1"
}
phase 1 src
phase 2 lib
echo o > outside/o.txt
git add outside/o.txt && git commit -q -m outside -- outside/o.txt

# build#checks-by-code, build#level-from-diff
out=$(cli gate start "$plan"); rc=$?
assert_eq 0 "$rc" "gate start: $out" || exit 1
assert_contains "$out" "level normal" "the level is raised" || exit 1
assert_contains "$out" "outside/o.txt" "names the path that raised it" || exit 1
assert_eq "gate: 2026-11-16-g level normal, raised by outside/o.txt" "$(echo "$out" | head -1)" "docs/spec/ and territories are not counted" || exit 1
assert_contains "$out" "exit 0" "a passing command shows its exit code" || exit 1
assert_contains "$out" "exit 3" "a failing command shows its exit code" || exit 1
assert_contains "$out" "second line" "a red output shows its tail" || exit 1
assert_contains "$out" "changed the tree" "an editing command is red" || exit 1
git log -1 --name-only --format=%s | grep -q '^docs/spec/' || fail "the last commit is not docs/spec/ alone: $(git log -1 --name-only --format=%s)"
[ "$(git show --name-only --format= HEAD | grep -vc '^docs/spec/')" = 0 ] || fail "docs/spec/ is committed alone"
sha=$(git rev-parse --short HEAD)

# a run stands while HEAD and the checks stand

out=$(cli gate start "$plan")
assert_contains "$out" "reused" "nothing runs again" || exit 1
assert_contains "$out" "$sha" "the last run prints its SHA" || exit 1
assert_eq 1 "$(grep -c '^x$' src/a.txt)" "the editing command did not run again" || exit 1

# a new commit runs them
git commit -q --allow-empty -m next
out=$(cli gate start "$plan")
assert_contains "$out" "exit 3" "a new HEAD runs the checks again" || exit 1
case "$out" in *reused*) fail "no reuse at a new HEAD";; esac

# status shows the level and the last run
out=$(cli status "$plan")
assert_contains "$out" "Gate: normal" "status shows the level" || exit 1
assert_contains "$out" "Checks at" "status shows the last run" || exit 1

# the cycle and its runs are recorded per HEAD
python3 - "${plan%.md}.json" "$(git rev-parse HEAD)" <<'PY' || fail "the record"
import json, sys
c = json.load(open(sys.argv[1]))["cycles"][0]
assert c["kind"] == "gate" and c["level"] == "normal" and c["raised_by"] == ["outside/o.txt"], c
assert [r["head"] for r in c["runs"]][-1] == sys.argv[2] and len(c["runs"]) == 2, c["runs"]
r = c["runs"][-1]["commands"]
assert [x["exit"] for x in r] == [0, 3, 0, 0] and [x["red"] for x in r] == [False, True, True, False], r
PY

# run show prints the allocation on its own
out=$(cli run show "$plan")
assert_contains "$out" "Port: 43" "run show prints the port" || exit 1
assert_contains "$out" "Data dir: $repo/.ai-workflow/plans/2026-11-16-g.data" "run show prints the data directory" || exit 1
echo "gate.test.sh: ok"
