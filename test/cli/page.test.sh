#!/usr/bin/env bash
# page and the rendered human gate, in throwaway repos.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "page.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# newrepo: a small plan with its phase done, the gate opened and a pass recorded.
newrepo() {
  repo=$(cd "$(mktemp_dir)" && pwd -P)
  cd "$repo" || exit 1
  git init -q
  mkdir -p .ai-workflow/plans skills/tdd src
  touch skills/tdd/SKILL.md
  echo a > src/a.txt
  git add -A && git commit -q -m base
  git tag v0
  plan=$repo/.ai-workflow/plans/2026-11-16-l.md
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

- Gate: small — x

## Done

1. a → b

## Spec

+ land — Land
  About: Land.
+ land#backup-first — Backup first
  Why: a test
  Done: 1
P
  cp "$repo_root/skills/run-file/references/example.run.toml" "${plan%.md}.run.toml"
  python3 - "${plan%.md}.run.toml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'(?m)^full = .*$', 'full = ["true"]', s)
open(p, "w").write(s)
PY
  sed -i.bak 's/^how = .*/how = "no-ff"/' "${plan%.md}.run.toml"
  cli approve "$plan" >/dev/null || fail "approve"
  cli build start "$plan" --base v0 >/dev/null || fail "build start"
  cli phase start "$plan" 1 >/dev/null || fail "phase start"
  echo 1 >> src/a.txt; git commit -q -m c1 -- src/a.txt
  echo b > src/b.txt; echo c > src/c.txt; git add src; git commit -q -m c2 -- src
  cli phase report "$plan" 1 --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "report"
  cli phase done "$plan" 1 >/dev/null || fail "phase done"
  cli gate start "$plan" >/dev/null || fail "gate start"
  [ "${1:-}" = nopass ] || cli verdict pass "$plan" --report ok --predicted pass --engine claude >/dev/null || fail "verdict"
  shape=${plan%.md}.shape.toml
}
# shape A B...: two commits, the first holding the paths of $1, the second the rest
write_shape() { # write_shape SINCE FIRSTPATHS... -- OTHERPATHS...
  python3 - "$shape" "$@" <<'PY'
import sys, json
shape, since, *rest = sys.argv[1:]
i = rest.index("--")
out = [f'since = {json.dumps(since)}'] if since else []
for n, ps in enumerate((rest[:i], rest[i + 1:]), 1):
    if ps:
        out += ["[[commit]]", f"paths = {json.dumps(ps)}", f'message = "feat: part {n}\\n\\nbody {n}"', f'walkthrough = "walk {n}"']
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PY
}
statuses() { cli status "$plan"; }


land1() { write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt "$@"; cli land "$plan" >/dev/null || fail "land"; }

# build#page-from-records: refused before a land, and without a message on no-ff
newrepo
out=$(cli page "$plan" --note "run it"); rc=$?
assert_eq 1 "$rc" "page before a land is refused" || exit 1
assert_contains "$out" "no-land" "the code" || exit 1
cli decision "$plan" --question "Q1" --from plan --answer "A1" --why "W1" --cost "C1" >/dev/null || fail "decision"
cli phase start "$plan" 1 --note "restarted for the page" >/dev/null || fail "phase start note"
cli result "$plan" --case 1 --outcome passed --capture out1 >/dev/null || fail "result"
cli finding "$plan" --kind observation --where src/a.txt:1 --source plan --text "an observation" >/dev/null || fail "finding"
land1
out=$(cli page "$plan" --note "run it"); rc=$?
assert_eq 1 "$rc" "no-ff needs a message" || exit 1
assert_contains "$out" "no-message" "the code" || exit 1
cli page "$plan" --note "open src and read" --message "feat: the merge" >/dev/null || fail "page"
assert_contains "$(statuses)" "Status: at the human gate" "status moved" || exit 1
python3 - "$plan" <<'PY' || fail "the page: $(sed -n '/^## Human gate/,$p' "$plan")"
import sys, re
t = open(sys.argv[1]).read()
g = t[t.index("## Human gate"):]
order = ["### How to try it", "open src and read", "### Ending", "a merge commit into `main`", "feat: the merge", "### Decided without you", "cost if wrong: C1", "restarted for the page",
         "### Open", "Verdict 1: pass", "an observation", "### E2E", "Level: small", "1. a → b — passed", "### The commits"]
at = 0
for w in order:
    i = g.find(w, at)
    assert i >= 0, w
    at = i
assert "Prediction" not in g and "User's verdict" not in g
assert "[taken on" not in g and "unknown commit" not in g, g
PY
cli status "$plan" | grep -q Drift && fail "no drift after page"

# build#page-from-records: a result taken before a later fix is flagged; the pre-land head is not; no commit is unknown
echo d > src/d.txt; git add src/d.txt; git commit -q -m round -- src/d.txt
cli result "$plan" --case 1 --outcome passed --capture out2 >/dev/null || fail "result 2"
cli finding "$plan" --kind observation --where src/a.txt:1 --source plan --text "second" >/dev/null
out=$(cli verdict pass "$plan" --report again) || fail "verdict 2: $out"
write_shape "d added" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/d.txt
cli land "$plan" >/dev/null || fail "re-land"
g=$(sed -n '/^## Human gate/,$p' "$plan")
assert_contains "$g" "1. a → b — passed — out2 — at" "the page draws the latest result" || exit 1
case "$(echo "$g" | grep 'out2')" in *"[taken on"*) fail "a result on the pre-land head is flagged: $g";; esac
assert_contains "$g" "Verdict 2: pass at" "the last verdict is listed" || exit 1
case "$g" in *"Verdict 1"*) fail "an earlier verdict is not repeated: $g";; esac
python3 - "${plan%.md}.json" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
st["cycles"][0]["results"].append({**st["cycles"][0]["results"][0], "commit": None, "capture": "nocommit"})
json.dump(st, open(sys.argv[1], "w"))
PY
cli plan status "$plan" "at the human gate" --note touch >/dev/null || fail "redraw"
assert_contains "$(sed -n '/^## Human gate/,$p' "$plan")" "unknown commit" "a record with no commit is flagged" || exit 1
first=$(git rev-parse backup/l-1)
python3 - "${plan%.md}.json" "$first" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
st["cycles"][0]["results"].append({**st["cycles"][0]["results"][0], "commit": sys.argv[2], "capture": "old"})
json.dump(st, open(sys.argv[1], "w"))
PY
cli plan status "$plan" "at the human gate" --note touch2 >/dev/null || fail "redraw 2"
assert_contains "$(sed -n '/^## Human gate/,$p' "$plan")" "[taken on \`${first:0:7}\`, not the tip's tree]" "a result before a later fix is flagged with its commit" || exit 1
# build#page-from-records: a hand edit is drift, and a plan with no land keeps its section
echo "my edit" >> "$plan"
out=$(cli phase start "$plan" 1 --note x); rc=$?
assert_eq 1 "$rc" "a hand edit to the page is refused" || exit 1
assert_contains "$out" "Human gate" "naming the section" || exit 1
assert_contains "$(statuses)" "Drift" "status shows the drift" || exit 1

newrepo
printf '\n## Human gate\n\nhand written: keep\n' >> "$plan"
cli plan status "$plan" "at the human gate" >/dev/null || fail "plan status"
python3 - "$plan" <<'PY' || fail "the hand-written section changed"
t = open(__import__("sys").argv[1]).read()
assert t.endswith("## Human gate\n\nhand written: keep\n"), t[-80:]
PY
# build#page-from-records: Open holds only what is open; a closed item shows once, under the round that took it; a flag names the paths changed since
newrepo nopass
cli finding "$plan" --kind convention --where src/a.txt:1 --source AGENTS.md --text "closed convention" >/dev/null || fail "C1"
cli finding "$plan" --kind convention --where src/a.txt:2 --source AGENTS.md --text "kept convention" >/dev/null || fail "C2"
cli finding "$plan" --kind observation --where src/a.txt:3 --source plan --text "an observation" >/dev/null || fail "O1"
cli verdict round "$plan" --report "first verdict report" --decide C1 round "fix it" --decide C2 let-through "style only" --note "the note text" bug --predicted pass --engine claude >/dev/null || fail "verdict round"
cli round start "$plan" >/dev/null || fail "round start"
echo r > src/r.txt; git add src/r.txt; git commit -q -m round -- src/r.txt
cli round report "$plan" --became "did the note" --commit "$(git rev-parse HEAD)" >/dev/null || fail "round report"
cli round done "$plan" >/dev/null || fail "round done"
cli verdict pass "$plan" --report "second verdict report" >/dev/null || fail "verdict pass"
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/r.txt
cli land "$plan" >/dev/null || fail "land"
cli page "$plan" --note "run it" --message "feat: m" >/dev/null || fail "page"
python3 - "$plan" <<'PY' || fail "the page: $(sed -n '/^## Human gate/,$p' "$plan")"
import sys, re
t = open(sys.argv[1]).read()
g = t[t.index("## Human gate"):]
op = g[g.index("### Open"):g.index("### E2E")]
assert "second verdict report" in op and "first verdict report" not in g, op
assert "C2" in op and "style only" in op and "kept convention" in op and "O1" in op, op
assert "C1" not in op and "closed convention" not in op, op
assert g.count("closed convention") == 1, g
com = g[g.index("### The commits"):]
r = com[com.index("Round 1"):]
assert "closed convention" in r and "the note text" in r, r
chk = [l for l in g.splitlines() if l.startswith("- Checks (gate)")][0]
assert "not the tip's tree] (changed since:" in chk and "src/r.txt" in chk, chk
assert "not the tip's tree" not in [l for l in g.splitlines() if l.startswith("- Checks (round-1)")][0]
PY
out=$(cli status "$plan")
assert_contains "$out" "C1 src/a.txt:1 — closed convention (AGENTS.md) [closed by round 1]" "status marks the finding with what closed it" || exit 1
case "$(echo "$out" | grep 'C2 src')" in *closed*) fail "an open finding is not marked closed";; esac

# run#changes-through-approve: page reports a run file changed after approval and records the approved ending
newrepo
land1
sed -i.bak 's/^how = .*/how = "ff-only"/' "${plan%.md}.run.toml"
out=$(cli page "$plan" --note "run it" --message "feat: m") || fail "page with drift: $out"
assert_contains "$out" "differs from the approved values" "drift is reported" || exit 1
assert_contains "$(sed -n '/^## Human gate/,$p' "$plan")" "a merge commit into" "the page names the approved ending" || exit 1
echo "page.test.sh: ok"
