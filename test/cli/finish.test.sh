#!/usr/bin/env bash
# finish: the run file's ending, local and by forge, in throwaway repos. Nothing leaves the machine:
# pushes land in a local bare repo and `gh` is a stand-in on PATH.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "finish.test.sh: $1" >&2; exit 1; }
cli() { python3 -B "$pipeline" "$@"; }
. "$repo_root/test/cli/lifecycle.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

bin=$(cd "$(mktemp_dir)" && pwd -P)
cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
dir=$(dirname "$0")
{ echo "--call"; printf '%s\n' "$@"; } >> "$dir/gh.log"
case "$1 $2" in
  "pr create") [ ! -f "$dir/create-fails" ] || { echo 'create unavailable' >&2; exit 1; }; echo "https://github.com/o/r/pull/7" ;;
  "pr view") echo "{\"state\":\"$(cat "$dir/state")\"}" ;;
esac
GH
chmod +x "$bin/gh"
export PATH="$bin:$PATH"

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

# newrepo HOW DELETE_BACKUPS WORKTREE(yes|no) [FULL]: a plan landed twice, its page made, at the human gate.
newrepo() {
  how=$1; del=$2; wt=$3; full=${4:-true}; tgt=${5:-main}
  repo=$(cd "$(mktemp_dir)" && pwd -P)
  cd "$repo" || exit 1
  git init -q -b main
  mkdir -p .ai-workflow/plans .ai-workflow/epics skills/tdd src
  touch skills/tdd/SKILL.md
  printf '# Epic\n\n## Plans\n\n| # | Plan | Waits for | Status |\n|---|---|---|---|\n| 1 | One | — | |\n' > .ai-workflow/epics/e.md
  echo a > src/a.txt
  git add -A && git commit -q -m base
  git tag v0
  plan=$repo/.ai-workflow/plans/2026-11-16-l.md
  cat > "$plan" <<'P'
# Plan: l

Status: draft · branch `l` · base `<sha>`
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
  rf=${plan%.md}.run.toml
  cp "$repo_root/skills/run-file/references/example.run.toml" "$rf"
  python3 - "$rf" "$how" "$del" "$wt" "$full" "$tgt" <<'PY'
import sys, re
p, how, dele, wt, full, tgt = sys.argv[1:]
s = open(p).read()
s = re.sub(r'(?m)^full = .*$', f'full = ["{full}"]', s)
s = re.sub(r'(?m)^how = .*$', f'how = "{how}"', s)
s = re.sub(r'(?m)^target = .*$', f'target = "{tgt}"', s)
s = re.sub(r'(?m)^delete_backups = .*$', f'delete_backups = {dele}', s)
open(p, "w").write(s)
PY
  [ "$tgt" = main ] || git branch "$tgt" v0
  approve_plan "$plan" >/dev/null || fail "approve"
  tree=$repo
  if [ "$wt" = yes ]; then
    wtdir=$(cd "$(mktemp_dir)" && pwd -P)/wt
    cli build start "$plan" --base v0 --worktree "$wtdir" >/dev/null || fail "build start"
    tree=$wtdir
  else
    cli build start "$plan" --base v0 >/dev/null || fail "build start"
  fi
  cli phase start "$plan" 1 >/dev/null || fail "phase start"
  echo 1 >> "$tree/src/a.txt"; git -C "$tree" commit -q -m c1 -- src/a.txt
  echo b > "$tree/src/b.txt"; echo c > "$tree/src/c.txt"; git -C "$tree" add src; git -C "$tree" commit -q -m c2 -- src
  report_phase "$plan" 1 --became x --commit "$(git -C "$tree" rev-parse HEAD)" >/dev/null || fail "report"
  cli phase done "$plan" 1 >/dev/null || fail "phase done"
  cli gate start "$plan" >/dev/null || fail "gate start"
  complete_review "$plan" || fail "complete review"
  cli verdict pass "$plan" --report ok --predicted pass --engine claude >/dev/null || fail "verdict"
  shape=${plan%.md}.shape.toml
  spec="docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md"
  write_shape "" src/a.txt $spec -- src/b.txt src/c.txt
  cli land "$plan" >/dev/null || fail "land 1"
  echo d > "$tree/src/d.txt"; git -C "$tree" add src/d.txt; git -C "$tree" commit -q -m round -- src/d.txt
  cli gate start "$plan" >/dev/null || fail "recheck second land"
  complete_review "$plan" || fail "complete review"
  cli verdict pass "$plan" --report again >/dev/null || fail "verdict 2"
  write_shape "d added" src/a.txt $spec -- src/b.txt src/c.txt src/d.txt
  cli land "$plan" >/dev/null || fail "land 2"
  git -C "$tree" branch backup/l-old; git -C "$tree" branch backup/other-1
  cli page "$plan" --guide "$finish_guide" --message "feat: the merge" >/dev/null || fail "page"
}
finish_guide=$'Open src/a.txt.\n\n#### Checks\n\n- **Done 1** Read the last line → It is 1.\n\n#### Decisions\n\n- —'
passed() { cli accept "$plan" --by user --words 'Fixture acceptance' >/dev/null || fail "accept"; }
status_is() { assert_contains "$(cli status "$plan" | sed -n 2p)" "Status: $1" "$2"; }
backups() { git -C "$repo" branch --list 'backup/*' --format='%(refname:short)' | tr '\n' ' '; }

# finish#by-run-file, finish#backups-delete-asks: ff-only keeps the backups; refused at the gate and when main moved on
newrepo ff-only false no
out=$(cli finish "$plan"); rc=$?
assert_eq 1 "$rc" "refused at the human gate" || exit 1
assert_contains "$out" "bad-status" "the code" || exit 1
passed
moved=$(git -C "$repo" commit-tree main^{tree} -p main -m moved)
git -C "$repo" update-ref refs/heads/main "$moved"
out=$(cli finish "$plan"); rc=$?
assert_eq 1 "$rc" "ff-only refused with main moved on" || exit 1
assert_contains "$out" "merge-refused" "the code" || exit 1
assert_eq "$moved" "$(git -C "$repo" rev-parse main)" "main is as it was" || exit 1
assert_eq l "$(git -C "$repo" branch --show-current)" "the tree is back on the branch" || exit 1
status_is passed "Status stays passed" || exit 1
git -C "$repo" update-ref refs/heads/main v0
out=$(cli finish "$plan") || fail "finish ff-only: $out"
assert_eq "$(git -C "$repo" rev-parse l)" "$(git -C "$repo" rev-parse main)" "main at the tip" || exit 1
status_is merged "Status merged" || exit 1
assert_contains "$(sed -n 7p "$repo/.ai-workflow/epics/e.md")" "merged ·" "the epic row follows" || exit 1
assert_contains "$out" "nothing was pushed" "says nothing was pushed" || exit 1
assert_contains "$(backups)" "backup/l-1 backup/l-2" "both backups kept" || exit 1
git -C "$repo" rev-parse --verify -q l >/dev/null || fail "the branch is kept"
cli plan status "$plan" merged --note touch >/dev/null || fail "the page redraws after finish"
cli status "$plan" | grep -q Drift && fail "no drift after finish"

# finish#backups-delete-asks, finish#by-run-file: no-ff with a worktree and a data directory: a conflict aborts; then the merge commit, backups gone, worktree and data directory removed
newrepo no-ff true yes
passed
data=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['alloc']['data_dir'])" "${plan%.md}.json")
[ -d "$data" ] || fail "the data directory exists before finish"
echo other > "$repo/src/a.txt"; git -C "$repo" commit -q -m other -- src/a.txt
out=$(cli finish "$plan"); rc=$?
assert_eq 1 "$rc" "a conflicting main is refused" || exit 1
assert_contains "$out" "src/a.txt" "the conflicting path is printed" || exit 1
assert_eq "" "$(git -C "$repo" status --porcelain -- . ':(exclude).ai-workflow')" "the target tree is clean" || exit 1
[ -d "$wtdir" ] || fail "the worktree stays after a refusal"
status_is passed "Status stays passed" || exit 1
git -C "$repo" reset -q --hard v0
out=$(cli finish "$plan") || fail "finish no-ff: $out"
assert_eq "feat: the merge" "$(git -C "$repo" log -1 --format=%s main)" "the merge commit has the page's message" || exit 1
assert_eq 2 "$(git -C "$repo" log -1 --format=%p main | wc -w | tr -d ' ')" "a merge commit" || exit 1
assert_eq "backup/l-old backup/other-1 " "$(backups)" "this plan's numbered backups are gone, the others kept" || exit 1
[ -d "$wtdir" ] && fail "the worktree is removed"
[ -d "$data" ] && fail "the data directory is removed"
git -C "$repo" rev-parse --verify -q l >/dev/null || fail "the branch is kept"
cli plan status "$plan" merged --note touch >/dev/null || fail "the page redraws once the worktree is gone"
assert_contains "$(sed -n '/^## Human gate/,$p' "$plan")" "### The commits" "the page still renders" || exit 1
cli status "$plan" | grep -q Drift && fail "no drift once the worktree is gone"

# finish#request-by-forge, finish#push-only-for-request: GitHub
newrepo merge-request false no
passed
bare=$(cd "$(mktemp_dir)" && pwd -P); git init -q --bare "$bare"
git -C "$repo" remote add origin https://github.com/o/r.git
git -C "$repo" config "url.$bare.pushInsteadOf" https://github.com/o/r.git
before=$(git -C "$repo" rev-parse main)
out=$(cli finish "$plan") || fail "finish github: $out"
assert_eq "$(git -C "$repo" rev-parse l)" "$(git -C "$bare" rev-parse l)" "the branch was pushed" || exit 1
assert_eq "l" "$(git -C "$bare" branch --list --format='%(refname:short)' | tr -d ' \n')" "only the plan's branch was pushed" || exit 1
log=$(cat "$bin/gh.log")
assert_contains "$log" "--base
main" "gh pr create with the base" || exit 1
assert_contains "$log" "--title
feat: the merge" "the message is the title" || exit 1
assert_contains "$log" "### How to try it" "the page is the body" || exit 1
status_is "https://github.com/o/r/pull/7" "Status is the printed link" || exit 1
assert_eq "$before" "$(git -C "$repo" rev-parse main)" "main untouched" || exit 1
echo OPEN > "$bin/state"
out=$(cli finish "$plan") || fail "finish open: $out"
assert_contains "$out" "open" "says the request is open" || exit 1
status_is "https://github.com/o/r/pull/7" "still the link" || exit 1
echo MERGED > "$bin/state"
cli finish "$plan" >/dev/null || fail "finish merged"
status_is merged "gh says merged" || exit 1

# finish#request-by-forge: a failed request creation retains the authorized manual handoff.
newrepo merge-request false no
passed
bare=$(cd "$(mktemp_dir)" && pwd -P); git init -q --bare "$bare"
git -C "$repo" remote add origin https://github.com/o/r.git
git -C "$repo" config "url.$bare.pushInsteadOf" https://github.com/o/r.git
touch "$bin/create-fails"
out=$(cli finish "$plan"); rc=$?
assert_eq 1 "$rc" "request creation failure is reported" || exit 1
assert_contains "$out" "gh-failed" "the push and request failure remain visible" || exit 1
rm "$bin/create-fails"
cli plan status "$plan" https://github.com/o/r/pull/8 >/dev/null || fail "record manual link after successful push"
cli finish --merged "$plan" >/dev/null || fail "finish manual recovery"

# finish#merge-needs-land: a changed submitted contract needs renewed evidence too.
newrepo merge-request false no
passed
bare=$(cd "$(mktemp_dir)" && pwd -P); git init -q --bare "$bare"
git -C "$repo" remote add origin https://github.com/o/r.git
git -C "$repo" config "url.$bare.pushInsteadOf" https://github.com/o/r.git
cli finish "$plan" >/dev/null || fail "finish opens request"
sed -i.bak 's/^how = .*/how = "ff-only"/' "${plan%.md}.run.toml"
out=$(cli finish --merged "$plan"); rc=$?
assert_eq 1 "$rc" "request follow-up refuses stale consent" || exit 1
assert_contains "$out" "run-stale" "names stale consent" || exit 1
status_is "https://github.com/o/r/pull/7" "request link remains readable" || exit 1

# finish#merge-needs-land: reverting the last land blocks acceptance and finish.
for how in merge-request ff-only no-ff; do
  newrepo "$how" false no
  before=$(git -C "$repo" rev-parse main)
  cli land revert "$plan" >/dev/null && cli land revert "$plan" >/dev/null || fail "land revert ($how)"
  python3 -c "import json,sys; assert 'page' not in json.load(open(sys.argv[1]))" "${plan%.md}.json" || fail "page cleared"
  out=$(cli accept "$plan" --by user --words yes); rc=$?
  assert_eq 1 "$rc" "$how: acceptance without a land refuses" || exit 1
  assert_contains "$out" "no-land" "$how: no land" || exit 1
  cli plan status "$plan" passed --note shortcut >/dev/null && fail "status cannot replace land"
  cli finish "$plan" >/dev/null && fail "finish cannot replace land"
  assert_eq "$before" "$(git -C "$repo" rev-parse main)" "$how: target unmoved" || exit 1
done

# finish#request-by-forge, finish#push-only-for-request: GitLab: one push with the create, target and title options; its link is the Status
newrepo merge-request false no
passed
bare=$(cd "$(mktemp_dir)" && pwd -P); git init -q --bare "$bare"
git -C "$bare" config receive.advertisePushOptions true
cat > "$bare/hooks/post-receive" <<'H'
#!/usr/bin/env bash
echo "--push" >> "$GIT_DIR/opts"
for i in $(seq 0 $((GIT_PUSH_OPTION_COUNT - 1))); do v="GIT_PUSH_OPTION_$i"; echo "${!v}" >> "$GIT_DIR/opts"; done
echo "remote: View merge request: https://gitlab.example.com/g/p/-/merge_requests/3" >&2
H
chmod +x "$bare/hooks/post-receive"
git -C "$repo" remote add origin git@gitlab.example.com:g/p.git
git -C "$repo" config "url.$bare.pushInsteadOf" git@gitlab.example.com:g/p.git
out=$(cli finish "$plan") || fail "finish gitlab: $out"
opts=$(cat "$bare/opts")
assert_eq 1 "$(grep -c -- --push "$bare/opts")" "one push" || exit 1
assert_contains "$opts" "merge_request.create" "create" || exit 1
assert_contains "$opts" "merge_request.target=main" "target" || exit 1
assert_contains "$opts" "merge_request.title=feat: the merge" "title" || exit 1
status_is "https://gitlab.example.com/g/p/-/merge_requests/3" "Status is the printed link" || exit 1
out=$(cli finish "$plan") || fail "finish gitlab again: $out"
status_is "https://gitlab.example.com/g/p/-/merge_requests/3" "unchanged without --merged" || exit 1
cli finish --merged "$plan" >/dev/null || fail "finish --merged"
status_is merged "merged on the agent's word" || exit 1

# finish#request-by-forge, finish#push-only-for-request: a GitLab push that prints no link is recorded; a second finish does not push again
newrepo merge-request false no
passed
bare=$(cd "$(mktemp_dir)" && pwd -P); git init -q --bare "$bare"
git -C "$bare" config receive.advertisePushOptions true
git -C "$repo" remote add origin git@gitlab.example.com:g/p.git
git -C "$repo" config "url.$bare.pushInsteadOf" git@gitlab.example.com:g/p.git
out=$(cli finish "$plan" 2>&1) || fail "finish gitlab with no link: $out"
assert_contains "$out" "plan status" "it says to record the link" || exit 1
status_is passed "Status stays passed" || exit 1
git -C "$bare" update-ref -d refs/heads/l
out=$(cli finish "$plan" 2>&1); rc=$?
assert_eq 1 "$rc" "a second finish refuses" || exit 1
assert_contains "$out" "plan status" "it says to record the link with plan status" || exit 1
assert_eq "" "$(git -C "$bare" branch --list)" "nothing was pushed again" || exit 1
cli plan status "$plan" https://gitlab.example.com/g/p/-/merge_requests/4 >/dev/null || fail "record the link"
cli finish --merged "$plan" >/dev/null || fail "finish --merged"
status_is merged "merged" || exit 1

# finish: a target other than main is named in the lines
newrepo merge-request false no true dev
passed
bare=$(cd "$(mktemp_dir)" && pwd -P); git init -q --bare "$bare"
git -C "$repo" remote add origin https://github.com/o/r.git
git -C "$repo" config "url.$bare.pushInsteadOf" https://github.com/o/r.git
out=$(cli finish "$plan") || fail "finish into dev: $out"
assert_contains "$out" "dev is untouched" "the line names the target" || exit 1
case "$out" in *"main is untouched"*) fail "main is named though the target is dev: $out";; esac

# finish#request-by-forge, finish#push-only-for-request: an unknown host: nothing is pushed, the agent opens the request
newrepo merge-request false no
bare=$(cd "$(mktemp_dir)" && pwd -P); git init -q --bare "$bare"
git -C "$repo" remote add origin https://git.example.org/x.git
git -C "$repo" config "url.$bare.pushInsteadOf" https://git.example.org/x.git
out=$(cli finish --merged "$plan"); rc=$?
assert_eq 1 "$rc" "--merged before a request is refused" || exit 1
passed
out=$(cli finish "$plan") || fail "finish unknown: $out"
assert_contains "$out" "nothing was pushed" "says nothing was pushed" || exit 1
assert_contains "$out" "plan status" "says to record the link" || exit 1
assert_eq "" "$(git -C "$bare" branch --list)" "nothing in the remote" || exit 1
status_is passed "Status stays passed" || exit 1
cli plan status "$plan" https://git.example.org/x/-/merge_requests/1 >/dev/null || fail "record the link"
cli finish --merged "$plan" >/dev/null || fail "finish --merged"
status_is merged "merged" || exit 1

# a conflict at finish is a round of its own with no notes; its check is the round cycle's
newrepo no-ff false no "test ! -e src/r.txt"
passed
git -C "$repo" switch -q main; echo other > "$repo/src/a.txt"; git -C "$repo" commit -q -m other -- src/a.txt; git -C "$repo" switch -q l
out=$(cli finish "$plan"); rc=$?
assert_eq 1 "$rc" "the conflict is refused" || exit 1
assert_contains "$out" "round start --conflict" "the fix names the conflict round" || exit 1
cli round start "$plan" --conflict "main moved" >/dev/null || fail "round start --conflict"
status_is building "the plan is back to building" || exit 1
echo r > src/r.txt; git add src/r.txt; git commit -q -m rebase -- src/r.txt
cli round report "$plan" --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "round report"
out=$(cli round done "$plan") || fail "round done: $out"
assert_contains "$out" "red" "round done checks in the round's cycle" || exit 1
cli fix start "$plan" >/dev/null || fail "fix start"
python3 - "${plan%.md}.json" <<'PY' || fail "the conflict round's records"
import json, sys
st = json.load(open(sys.argv[1]))
r = st["rounds"][-1]
assert r["notes"] == [] and r["conflict"] == "main moved", r
gate = next(c for c in st["cycles"] if c["kind"] == "gate")
assert st["cycles"][-1]["kind"] == "round" and st["cycles"][-1]["fixes"][0]["items"] == ["check-1"] and not gate["fixes"]
PY
# a conflict round: both briefs, status and the commits section carry the conflict whole, also with no commit
newrepo no-ff false no
passed
git -C "$repo" switch -q main; echo other > "$repo/src/a.txt"; git -C "$repo" commit -q -m other -- src/a.txt; git -C "$repo" switch -q l
cli finish "$plan" >/dev/null
cli round start "$plan" --conflict "main moved on src/a.txt" >/dev/null || fail "round start --conflict"
b=$(cli brief round "$plan") || fail "brief round"
grep -q "main moved on src/a.txt" "$b" || fail "brief round carries the conflict text: $(cat "$b")"
out=$(cli status "$plan")
assert_contains "$out" "Round 1 (user): conflict at finish: main moved on src/a.txt" "status prints the round's line whole" || exit 1
case "$out" in *"takes notes "$'\n'*|*"takes notes ;"*) fail "status prints takes notes with nothing after it: $out";; esac
cli round report "$plan" --became "nothing to rebase" >/dev/null || fail "round report with no commit"
g=$(sed -n '/^## Human gate/,$p' "$plan")
assert_contains "$g" "Round 1 (user): nothing to rebase (no commit)" "a round with no commit renders whole" || exit 1
case "$g" in *"(commits )"*) fail "the commits section renders (commits ): $g";; esac
cli round done "$plan" >/dev/null || fail "round done"
complete_review "$plan" || fail "complete review"
b=$(cli brief judge "$plan") || fail "brief judge"
grep -q "main moved on src/a.txt" "$b" || fail "brief judge carries the conflict text: $(cat "$b")"

# run#changes-through-approve: changed consent invalidates judge, page and acceptance.
newrepo no-ff false no
rf=${plan%.md}.run.toml
sed -i.bak 's/^how = .*/how = "ff-only"/' "$rf"
before=$(git -C "$repo" rev-parse main)
out=$(cli accept "$plan" --by user --words yes); rc=$?
assert_eq 1 "$rc" "stale run consent refuses acceptance" || exit 1
assert_contains "$out" "run-stale" "names stale run" || exit 1
approve_plan "$plan" >/dev/null || fail "approve changed ending"
cli accept "$plan" --by user --words yes >/dev/null && fail "reapproval cannot replace fresh judge"
cli gate start "$plan" >/dev/null || fail "recheck changed contract"
complete_review "$plan" || fail "complete review"
cli verdict pass "$plan" --report "reviewed new ending" >/dev/null || fail "fresh judge"
cli page "$plan" --guide "$finish_guide" >/dev/null || fail "page again"
passed
out=$(cli finish "$plan") || fail "finish after renewed consent: $out"
assert_eq "$(git -C "$repo" rev-parse l)" "$(git -C "$repo" rev-parse main)" "main at tip" || exit 1

# run#changes-through-approve: changes after acceptance refuse without touching backups or target.
newrepo ff-only false no
passed
before=$(git -C "$repo" rev-parse main)
sed -i.bak 's/^delete_backups = .*/delete_backups = true/' "${plan%.md}.run.toml"
out=$(cli finish "$plan"); rc=$?
assert_eq 1 "$rc" "finish refuses changed run" || exit 1
assert_contains "$out" "run-stale" "renewed consent is required" || exit 1
assert_eq "$before" "$(git -C "$repo" rev-parse main)" "target untouched" || exit 1
assert_contains "$(backups)" "backup/l-1" "backups kept" || exit 1
echo "finish.test.sh: ok"
