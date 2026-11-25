#!/usr/bin/env bash
# page and the rendered human gate, in throwaway repos.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "page.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
. "$repo_root/test/cli/lifecycle.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# newrepo: a small plan with its phase done, the gate opened and a pass recorded.
newrepo() {
  repo=$(cd "$(mktemp_dir)" && pwd -P)
  cd "$repo" || exit 1
  git init -q -b main
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
2. c → d — you check

## Spec

+ land — Land
  About: Land.
+ land#backup-first — Backup first
  Why: a test
  Done: 1
P
  if [ "${2:-}" = normal ]; then
    sed -i.bak 's/Gate: small/Gate: normal/' "$plan"
  fi
  if [ "${3:-}" = zero ]; then
    sed -i.bak 's/^1\. a → b/0. Confirm → visible — you check\n1. a → b/' "$plan"
  fi
  cp "$repo_root/skills/run-file/references/example.run.toml" "${plan%.md}.run.toml"
  python3 - "${plan%.md}.run.toml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'(?m)^full = .*$', 'full = ["true"]', s)
open(p, "w").write(s)
PY
  sed -i.bak 's/^how = .*/how = "no-ff"/' "${plan%.md}.run.toml"
  approve_plan "$plan" >/dev/null || fail "approve"
  cli build start "$plan" --base v0 >/dev/null || fail "build start"
  cli phase start "$plan" 1 >/dev/null || fail "phase start"
  echo 1 >> src/a.txt; git commit -q -m c1 -- src/a.txt
  echo b > src/b.txt; echo c > src/c.txt; git add src; git commit -q -m c2 -- src
  report_phase "$plan" 1 --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "report"
  cli phase done "$plan" 1 >/dev/null || fail "phase done"
  cli gate start "$plan" >/dev/null || fail "gate start"
  if [ "${1:-}" != nopass ]; then
    complete_review "$plan" || fail "complete review"
    cli verdict pass "$plan" --report ok --predicted pass --engine claude >/dev/null || fail "verdict"
  fi
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

guide() {
  printf '%s\n\n#### Checks\n\n- **Done 1** Read src/a.txt → The last line is 1.\n- **Done 2** Read src/b.txt → The file contains b.\n\n#### Decisions\n\n- —' "$1"
}

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
complete_review "$plan" || fail "complete review"
cli verdict pass "$plan" --report "current records reviewed" >/dev/null || fail "fresh judge"
land1
out=$(cli page "$plan" --note "run it"); rc=$?
assert_eq 1 "$rc" "no-ff needs a message" || exit 1
assert_contains "$out" "no-message" "the code" || exit 1
out=$(cli page "$plan" --note "open src and read" --message "feat: the merge"); rc=$?
assert_eq 1 "$rc" "build#human-check-guide: free text alone cannot open human review" || exit 1
assert_contains "$out" "bad-guide" "build#human-check-guide: the refusal names the guide" || exit 1
cli page "$plan" --guide "$(guide "open src and read")" --message "feat: the merge" >/dev/null || fail "page"
assert_contains "$(statuses)" "Status: at the human gate" "status moved" || exit 1
python3 - "$plan" <<'PY' || fail "the page: $(sed -n '/^## Human gate/,$p' "$plan")"
import sys, re
t = open(sys.argv[1]).read()
g = t[t.index("## Human gate"):]
order = ["### How to try it", "open src and read", "### Ending", "a merge commit into `main`", "feat: the merge", "### Decided without you", "cost if wrong: C1", "restarted for the page",
         "### Open", "Verdict 2: pass", "an observation", "### E2E", "Level: small", "1. a → b — passed", "### The commits"]
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
cli gate start "$plan" --note "fixture recheck" >/dev/null || fail "recheck"
complete_review "$plan" || fail "complete review"
out=$(cli verdict pass "$plan" --report again) || fail "verdict 2: $out"
write_shape "d added" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/d.txt
reviewed=$(git rev-parse HEAD)
cli land "$plan" >/dev/null || fail "re-land"
landed=$(git rev-parse HEAD)
[ "$reviewed" != "$landed" ] || fail "the fixture must rewrite history"
g=$(sed -n '/^## Human gate/,$p' "$plan")
assert_contains "$g" "1. a → b — passed — out2 — at" "the page draws the latest result" || exit 1
case "$(echo "$g" | grep 'out2')" in *"[taken on"*) fail "a result on the pre-land head is flagged: $g";; esac
assert_contains "$g" "Verdict 3: pass at" "the last verdict is listed" || exit 1
case "$g" in *"Verdict 1"*) fail "an earlier verdict is not repeated: $g";; esac
python3 - "${plan%.md}.json" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
st["cycles"][0]["results"].append({**st["cycles"][0]["results"][0], "commit": None, "capture": "nocommit"})
json.dump(st, open(sys.argv[1], "w"))
PY
out=$(cli brief judge "$plan") || fail "build#review-completion: the landed tip retains its review: $out"
assert_contains "$(cat "$out")" "Review complete (2 findings in cycle): gate $(git rev-parse v0)..$reviewed" "build#review-completion: the brief shows the authorized pre-land range" || exit 1
git commit -q --allow-empty -m 'unrelated same-tree rewrite' || fail "rewrite fixture history"
out=$(cli brief judge "$plan"); rc=$?
assert_eq 1 "$rc" "build#review-completion: a different same-tree tip needs its own review" || exit 1
assert_contains "$out" "review-missing" "build#review-completion: a different tip cannot reuse the pre-land review" || exit 1
out=$(cli verdict pass "$plan" --report "unrelated rewrite"); rc=$?
assert_eq 1 "$rc" "build#review-completion: verdict also rejects the unrelated tip" || exit 1
git reset -q --hard "$landed" || fail "restore authorized land"
cli verdict pass "$plan" --report "reviewed unknown capture provenance" >/dev/null || fail "judge unknown capture"
out=$(statuses | sed -n '/^Next:/,/^Gate:/p')
assert_contains "$out" 'render `page`' "build#workflow-progress: a provenance refresh asks for a page" || exit 1
cli page "$plan" --guide "$(guide "open src and read")" --message "feat: the merge" >/dev/null || fail "redraw"
assert_contains "$(sed -n '/^## Human gate/,$p' "$plan")" "unknown commit" "a record with no commit is flagged" || exit 1
out=$(statuses | sed -n '/^Next:/,/^Gate:/p')
assert_contains "$out" 'Review the current page' "build#workflow-progress: redrawing returns to human review" || exit 1
first=$(git rev-parse backup/l-1)
python3 - "${plan%.md}.json" "$first" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
st["cycles"][0]["results"].append({**st["cycles"][0]["results"][0], "commit": sys.argv[2], "capture": "old"})
json.dump(st, open(sys.argv[1], "w"))
PY
cli verdict pass "$plan" --report "reviewed older capture provenance" >/dev/null || fail "judge older capture"
cli page "$plan" --guide "$(guide "open src and read")" --message "feat: the merge" >/dev/null || fail "redraw 2"
assert_contains "$(sed -n '/^## Human gate/,$p' "$plan")" "[taken on \`${first:0:7}\`, not the tip's tree]" "a result before a later fix is flagged with its commit" || exit 1
# build#page-from-records: a hand edit is drift, and a plan with no land keeps its section
echo "my edit" >> "$plan"
out=$(cli phase start "$plan" 1 --note x); rc=$?
assert_eq 1 "$rc" "a hand edit to the page is refused" || exit 1
assert_contains "$out" "Human gate" "naming the section" || exit 1
assert_contains "$(statuses)" "Drift" "status shows the drift" || exit 1

newrepo
printf '\n## Human gate\n\nhand written: keep\n' >> "$plan"
cli plan status "$plan" "at the human gate" >/dev/null && fail "a hand-written gate cannot replace land"
python3 - "$plan" <<'PY' || fail "the hand-written section changed"
t = open(__import__("sys").argv[1]).read()
assert t.endswith("## Human gate\n\nhand written: keep\n"), t[-80:]
PY
# build#page-from-records: Open holds only what is open; a closed item shows once, under the round that took it; a flag names the paths changed since
newrepo nopass
out=$(cli verdict pass "$plan" --report 'Small gate without review' --predicted pass --engine fixture); rc=$?
assert_eq 1 "$rc" "build#review-completion: small still needs a completed review" || exit 1
assert_contains "$out" "review-missing" "build#review-completion: small names the missing review" || exit 1
cli finding "$plan" --kind convention --where src/a.txt:1 --source AGENTS.md --text "closed convention" >/dev/null || fail "C1"
cli finding "$plan" --kind convention --where src/a.txt:2 --source AGENTS.md --text "kept convention" >/dev/null || fail "C2"
cli finding "$plan" --kind observation --where src/a.txt:3 --source plan --text "an observation" >/dev/null || fail "O1"
complete_review "$plan" || fail "complete review"
cli verdict round "$plan" --report "first verdict report" --decide C1 round "fix it" --decide C2 let-through "style only" --note "the note text" bug --predicted pass --engine claude >/dev/null || fail "verdict round"
cli round start "$plan" >/dev/null || fail "round start"
echo r > src/r.txt; git add src/r.txt; git commit -q -m round -- src/r.txt
cli round report "$plan" --became "did the note" --commit "$(git rev-parse HEAD)" >/dev/null || fail "round report"
cli round done "$plan" >/dev/null || fail "round done"
complete_review "$plan" || fail "complete review"
cli verdict pass "$plan" --report "second verdict report" >/dev/null || fail "verdict pass"
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/r.txt
cli land "$plan" >/dev/null || fail "land"
cli page "$plan" --guide "$(guide "run it")" --message "feat: m" >/dev/null || fail "page"
assert_contains "$(sed -n '/^## Human gate/,$p' "$plan")" '1. a → b — you check' "build#review-completion: the small gate hands cases to the user" || exit 1
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
out=$(cli page "$plan" --note "run it" --message "feat: m"); rc=$?
assert_eq 1 "$rc" "page refuses stale run consent" || exit 1
assert_contains "$out" "run-stale" "renewed consent is required" || exit 1

# build#human-check-guide, build#required-transition-files: the shipped guide is validated at page.
newrepo
land1
input="${plan%.md}.guide.md"
example="$repo_root/skills/build/references/example.guide.md"
output="$repo/.ai-workflow/printed-guide"
render() { cli page "$plan" --guide-file "$input" --message "feat: guide"; }
st="${plan%.md}.json"
unchanged=$(git hash-object "$plan" "$st")
bad_guide() {
  out=$(render); rc=$?
  assert_eq 1 "$rc" "build#required-transition-files: page rejects $1" || exit 1
  assert_contains "$out" "bad-guide: $input" "the error names the guide path: $out" || exit 1
  assert_contains "$out" "$1" "the error identifies the problem: $out" || exit 1
  assert_contains "$out" "example.guide.md" "the error points to the example" || exit 1
  assert_eq "$unchanged" "$(git hash-object "$plan" "$st")" "a bad guide leaves the page and state unchanged" || exit 1
}
bad_guide "does not exist"
mkdir "$input"
bad_guide "readable regular file"
rmdir "$input"
printf '\377' > "$input"
bad_guide "not valid UTF-8"
printf ' \n' > "$input"
bad_guide "is empty"
sed '/\*\*Done 1\*\*/d' "$example" > "$input"
bad_guide "add the manual checks for Done 1"
sed 's/\*\*Done 2\*\*/**Done 1**/' "$example" > "$input"
bad_guide "Done 1 appears twice"
sed 's/\*\*Done 2\*\*/**Done 99**/' "$example" > "$input"
bad_guide "Done 99 is not in the plan"
sed '/\*\*Done 2\*\*/s/ → .*/ → /' "$example" > "$input"
bad_guide "action → visible result"
cp "$example" "$input"
render > "$output" || fail "build#human-check-guide: page rejects the shipped guide: $(cat "$output")"
cmp -s "$input" "$output" || fail "build#human-check-guide: the guide is the complete message"
python3 - "$plan" "$input" <<'PY' || fail "build#human-check-guide: page shows the verbatim guide"
import sys
from pathlib import Path
plan, guide = (Path(p).read_bytes() for p in sys.argv[1:])
assert b"### How to try it\n\n" + guide + b"\n\n### Ending" in plan
PY
rm "$input"
cli page "$plan" --show > "$output" || fail "recover the recorded guide without its input file"
cmp -s "$example" "$output" || fail "build#human-check-guide: a new coordinator retrieves the same message"
sed $'s/$/\r/' "$example" > "$input"
render > "$output" || fail "render a CRLF guide"
cmp -s "$input" "$output" || fail "preserve the guide's line endings"
cli page "$plan" --show > "$output" || fail "CRLF guide does not cause page drift"
cmp -s "$input" "$output" || fail "the recorded guide keeps its line endings"

# build#human-check-guide: a normal gate needs only the cases assigned to the human.
newrepo nopass normal
cli result "$plan" --case 1 --outcome passed --capture fixture >/dev/null || fail "verify the normal gate's automated case"
cli decision "$plan" --question "How should the CSV be ordered?" --from build --answer "Newest first" --why "Most recent entries matter first" --cost "Users may expect a different order" >/dev/null || fail "decision made during the build"
cli finding "$plan" --kind defect --where src/a.txt:1 --source review --text "Export stalls above 10000 rows" >/dev/null || fail "open defect"
complete_review "$plan" || fail "complete normal review"
cli verdict pass "$plan" --report "normal" --decide D1 let-through "The human can defer this" --predicted pass --engine fixture >/dev/null || fail "normal judge"
land1
input="${plan%.md}.guide.md"
output="$repo/.ai-workflow/printed-guide"
st="${plan%.md}.json"
unchanged=$(git hash-object "$plan" "$st")
sed '/\*\*Done 2\*\*/d' "$example" > "$input"
bad_guide "add the manual checks for Done 2"
sed '/\*\*Done 1\*\*/d' "$example" > "$input"
printf '%s' "$(cat "$input")" > "$input"
cli page "$plan" --guide "$(cat "$input")" --message "feat: guide" > "$output" || fail "normal page without the automated case: $(cat "$output")"
cmp -s "$input" "$output" || fail "inline guide was changed"
cli accept "$plan" --by user --words "Accept and defer D1" >/dev/null || fail "accept guide"
cli note add "$plan" --text "Show why export stops" --cause bug >/dev/null || fail "new feedback"
cli round start "$plan" >/dev/null || fail "start feedback round"
out=$(cli page "$plan" --show); rc=$?
assert_eq 1 "$rc" "build#human-check-guide: a round supersedes the previous guide" || exit 1
assert_contains "$out" "judge-stale" "the outdated guide cannot be relayed as current" || exit 1
echo r > src/r.txt
git add src/r.txt && git commit -q -m round -- src/r.txt || fail "commit feedback round"
cli round report "$plan" --became "show export limit" --commit "$(git rev-parse HEAD)" >/dev/null || fail "report feedback round"
cli note edit "$plan" 1 --source missed >/dev/null || fail "record note source"
cli round done "$plan" >/dev/null || fail "close feedback round"
complete_review "$plan" || fail "review feedback round"
cli verdict pass "$plan" --report "current result reviewed" >/dev/null || fail "judge feedback round"
write_shape "show export limit" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/r.txt
cli land "$plan" >/dev/null || fail "land feedback round"
cli plan status "$plan" passed >/dev/null && fail "the old page cannot authorize the new land"
out=$(cli finish "$plan"); rc=$?
assert_eq 1 "$rc" "the old approval cannot finish the new result" || exit 1
assert_contains "$out" "page-stale" "finish requires the new page" || exit 1
sed -i.bak 's/Open the worktree/Open the updated worktree/' "$input"
cli plan status "$plan" building >/dev/null || fail "prepare another page"
render > "$output" || fail "page after feedback round: $(cat "$output")"
cmp -s "$input" "$output" || fail "the new handoff describes the revised build"
cli plan status "$plan" passed >/dev/null && fail "the old acceptance cannot authorize a new page"
cli accept "$plan" --by user --words "Accept revised guide" >/dev/null || fail "accept revised guide"

# build#human-check-guide: historical plain-note records keep their valid acceptance.
python3 -B - "$pipeline" "$plan" <<'PY' || fail "prepare a historical page and acceptance"
import hashlib, importlib.util, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).resolve().parent))
spec = importlib.util.spec_from_file_location("pipeline", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with module.writing(sys.argv[2]) as state:
    state["page"]["note"] = "Historical instructions."
    page = json.dumps(state["page"], sort_keys=True, ensure_ascii=False).encode()
    state["acceptance"]["page"] = hashlib.sha256(page).hexdigest()
PY
out=$(cli page "$plan" --show) || fail "read historical instructions"
assert_eq "Historical instructions." "$out" "the original note is still readable" || exit 1
cli finish "$plan" >/dev/null || fail "finish historically accepted result"
assert_contains "$(statuses)" "Status: merged" "the historical approval still permits finish" || exit 1
assert_contains "$(cat "$plan")" "Historical instructions." "the historical note survives finish" || exit 1

# build#human-check-guide: Done 0 is a real plan case, including in a Russian guide.
newrepo pass small zero
land1
input="${plan%.md}.guide.md"
output="$repo/.ai-workflow/printed-guide"
cat > "$input" <<'GUIDE'
Откройте `src/a.txt` в рабочей копии.

#### Что проверить

- **Done 0** Подтвердите действие → Результат виден.
- **Done 1** Прочитайте `src/a.txt` → Последняя строка содержит 1.
- **Done 2** Прочитайте `src/b.txt` → Файл содержит b.

#### Что решить

- —
GUIDE
render > "$output" || fail "build#human-check-guide: page must accept Done 0: $(cat "$output")"
cmp -s "$input" "$output" || fail "build#human-check-guide: the Russian guide is unchanged"
sed -i.bak '/\*\*Done 0\*\*/d' "$input"
st="${plan%.md}.json"
unchanged=$(git hash-object "$plan" "$st")
bad_guide "add the manual checks for Done 0"

echo "page.test.sh: ok"
