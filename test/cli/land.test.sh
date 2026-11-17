#!/usr/bin/env bash
# land draft|land|accept|revert, the land record, its stops, and verdict evidence-owed, in throwaway repos.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"

fail() { echo "land.test.sh: $1" >&2; exit 1; }
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
  cli approve "$plan" >/dev/null || fail "approve"
  cli build start "$plan" --base v0 >/dev/null || fail "build start"
  cli phase start "$plan" 1 >/dev/null || fail "phase start"
  echo 1 >> src/a.txt; git commit -q -m c1 -- src/a.txt
  echo b > src/b.txt; echo c > src/c.txt; git add src; git commit -q -m c2 -- src
  cli phase report "$plan" 1 --became x --commit "$(git rev-parse HEAD)" >/dev/null || fail "report"
  cli phase done "$plan" 1 >/dev/null || fail "phase done"
  cli gate start "$plan" >/dev/null || fail "gate start"
  cli verdict pass "$plan" --report ok --predicted pass --engine claude >/dev/null || fail "verdict"
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

# land#backup-first: a dirty tree, then a shape that misses or repeats a path
newrepo
pre=$(git rev-parse HEAD)
echo u > untracked.txt
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "a dirty tree is refused" || exit 1
assert_contains "$out" "untracked.txt" "it names what is there" || exit 1
assert_contains "$out" "— fix:" "refusal format" || exit 1
rm untracked.txt
out=$(cli land draft "$plan") || fail "draft"
python3 - "$shape" <<'PY' || fail "the draft: $(cat "$shape")"
import tomllib, sys
v = tomllib.load(open(sys.argv[1], "rb"))
assert len(v["commit"]) == 1 and v["commit"][0]["paths"] == ["docs/spec/README.md", "docs/spec/archive/2026-11-16-l.md", "docs/spec/land.md", "src/a.txt", "src/b.txt", "src/c.txt"], v
PY
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "the draft's empty message is refused" || exit 1
write_shape "" src/a.txt -- src/b.txt
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "a shape missing paths is refused" || exit 1
assert_contains "$out" "src/c.txt" "it names the missing path" || exit 1
write_shape "" src/a.txt src/b.txt src/c.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "a shape repeating a path is refused" || exit 1
assert_contains "$out" "src/b.txt" "it names the repeated path" || exit 1
assert_eq "$pre" "$(git rev-parse HEAD)" "a refused land touches no git" || exit 1
[ -z "$(git branch --list 'backup/*')" ] || fail "no backup before the shape passes"

# land#backup-first, land#recorded: a two-commit shape
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
out=$(cli land "$plan") || fail "land: $out"
assert_eq "$pre" "$(git rev-parse backup/l-1)" "the backup is the old HEAD" || exit 1
assert_eq "feat: part 2" "$(git log -1 --format=%s)" "the tip is the shape's last commit" || exit 1
assert_eq "feat: part 1" "$(git log -1 --format=%s HEAD~1)" "the first commit" || exit 1
assert_eq "2" "$(git rev-list --count v0..HEAD)" "two commits" || exit 1
git diff --quiet backup/l-1 HEAD || fail "the tree is the backup's"
tip=$(git rev-parse --short HEAD)
out=$(statuses)
assert_contains "$out" "Land 1: tip $tip has the tree of ${pre:0:7}" "status names the tip and its tree" || exit 1
assert_contains "$out" "backup/l-1" "status names the backup" || exit 1
grep -q "^### The commits · landed $tip · backup/l-1$" "$plan" || fail "the section's heading: $(tail -20 "$plan")"
grep -q "^## Human gate$" "$plan" || fail "the gate section"
for w in "#### feat: part 1" "#### feat: part 2" "body 2" "walk 1" "walk 2" '`src/c.txt`'; do grep -qF -- "$w" "$plan" || fail "the section holds: $w"; done
out=$(cli status "$plan") && cli phase start "$plan" 1 --note x >/dev/null || fail "the plan still takes commands after a land (no drift)"

# re-land: the last shape, a new path apart, backup-2, one section with range-diff and since
echo d > src/d.txt; git add src/d.txt; git commit -q -m round -- src/d.txt
cli land draft "$plan" >/dev/null || fail "re-draft"
python3 - "$shape" <<'PY' || fail "the re-draft: $(cat "$shape")"
import tomllib, sys
v = tomllib.load(open(sys.argv[1], "rb"))
assert v["unplaced"] == ["src/d.txt"] and [c["message"].splitlines()[0] for c in v["commit"]] == ["feat: part 1", "feat: part 2"], v
assert v["since"] == "" and v["commit"][1]["walkthrough"] == "walk 2", v
PY
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "land refuses until the new path is placed" || exit 1
assert_contains "$out" "src/d.txt" "names it" || exit 1
before=$(git rev-parse HEAD)
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/d.txt
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "a re-land without since is refused" || exit 1
assert_contains "$out" "since" "it says so" || exit 1
write_shape "the round added d" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/d.txt
cli land "$plan" >/dev/null || fail "re-land"
assert_eq "$before" "$(git rev-parse backup/l-2)" "backup 2 holds the pre-land head" || exit 1
assert_eq 1 "$(grep -c '^### The commits' "$plan")" "one commits section" || exit 1
grep -q "^### The commits · landed $(git rev-parse --short HEAD) · backup/l-2$" "$plan" || fail "the new heading"
grep -qF "the round added d" "$plan" && grep -q "Since the last land" "$plan" && grep -qF 'feat: part 2' "$plan" || fail "since text and range-diff in the section"
python3 - "${plan%.md}.json" "$tip" <<'PY' || fail "the record"
import json, sys
st = json.load(open(sys.argv[1]))
a, b = st["lands"]
assert a["tip"].startswith(sys.argv[2]) and a["backup"] == "backup/l-1" and a["pre"] and a["difference"] == [] and a["accepted"] is None, a
assert b["range_diff"] and b["since"] == "the round added d" and b["shape"][0]["sha"], b
PY

# land#checked-tree: a hook that reformats a file; revert, then accept
hook() { printf '#!/bin/sh\necho fmt >> src/a.txt\ngit add src/a.txt\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit; }
newrepo
pre=$(git rev-parse HEAD)
hook
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
out=$(cli land "$plan") || fail "hook land: $out"
assert_contains "$out" "differs" "the difference is printed" || exit 1
assert_contains "$out" "src/a.txt" "naming the file" || exit 1
assert_eq "feat: part 2" "$(git log -1 --format=%s)" "the rewrite stays" || exit 1
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "another land waits for the decision" || exit 1
out=$(cli land accept "$plan"); rc=$?
assert_eq 1 "$rc" "accept needs a note" || exit 1
cli land revert "$plan" | grep -q "reverted to backup/l-1" || fail "revert"
assert_eq "$pre" "$(git rev-parse HEAD)" "the branch is the backup" || exit 1
statuses | grep -q "Land stop (revert)" || fail "a stop is recorded"
statuses | grep -q "^Land 1" && fail "a reverted land is gone"
grep -q "^### The commits" "$plan" && fail "the reverted land's section is gone"
out=$(cli land "$plan") || fail "land again: $out"
cli land accept --note "the formatter's newline" "$plan" >/dev/null || fail "accept"
grep -qF "the formatter's newline" "$plan" && grep -q "not the tree the checks passed" "$plan" || fail "the page shows the note and says so"
assert_contains "$(statuses)" "kept: the formatter's newline" "status shows it" || exit 1
assert_eq "backup/l-2" "$(git branch --list 'backup/*' --format='%(refname:short)' | tail -1)" "the next backup is numbered on" || exit 1

# land#backup-first: land revert refuses a dirty tree, naming it, and changes nothing; a hook's own leftovers do not stop it
newrepo
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
cli land "$plan" >/dev/null || fail "land"
tip=$(git rev-parse HEAD)
echo mine > mine.txt; echo edit >> src/b.txt
out=$(cli land revert "$plan"); rc=$?
assert_eq 1 "$rc" "revert on a dirty tree is refused" || exit 1
assert_contains "$out" "dirty-tree" "the code" || exit 1
assert_contains "$out" "mine.txt" "it names the untracked file" || exit 1
assert_contains "$out" "src/b.txt" "it names the edited file" || exit 1
assert_eq "$tip" "$(git rev-parse HEAD)" "the branch is as it was" || exit 1
git rev-parse --verify -q backup/l-1 >/dev/null || fail "the backup stays"
[ -f mine.txt ] && grep -q edit src/b.txt || fail "the files are untouched"
assert_contains "$(statuses)" "Land 1:" "the land stays recorded" || exit 1
rm mine.txt; git checkout -q -- src/b.txt
cli land revert "$plan" >/dev/null || fail "revert on a clean tree"
newrepo
printf '#!/bin/sh\necho fmt >> src/a.txt\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
cli land "$plan" >/dev/null || fail "hook land"
git status --porcelain | grep -q 'src/a.txt' || fail "the hook left an uncommitted change"
cli land revert "$plan" >/dev/null || fail "a hook's leftovers are the difference, not someone's files: revert goes through"

# land#checked-tree: a hook that leaves a stash
newrepo
printf '#!/bin/sh\necho j > junk.txt\ngit stash push -q -u -- junk.txt\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
out=$(cli land "$plan") || fail "stash land: $out"
assert_contains "$out" "stash" "a stash a hook left is named" || exit 1

# land#stops-to-user: stops past the cap are a question
newrepo
echo u > untracked.txt
cli land "$plan" >/dev/null
cli land "$plan" >/dev/null
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "the third stop is refused" || exit 1
assert_contains "$out" "question for the user" "past the cap it is a question" || exit 1
out=$(statuses)
assert_contains "$out" "question: land stopped: the tree has uncommitted paths: untracked.txt" "status shows land's message" || exit 1
out=$(cli brief judge "$plan"); rc=$?
assert_eq 1 "$rc" "brief judge waits for the answer" || exit 1
assert_contains "$out" "no-answer" "refused without --note" || exit 1
cli brief judge "$plan" --note "I will move it" >/dev/null || fail "brief judge with the answer"
rm untracked.txt
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "no land until the judge passes again" || exit 1
assert_contains "$out" "no-pass" "the code" || exit 1

# build#judge-file-by-code: evidence-owed
newrepo
cli finding "$plan" --kind defect --where src/a.txt:1 --source plan --text "a defect" >/dev/null || fail "defect"
python3 - "${plan%.md}.json" <<'PY'
import json, sys
st = json.load(open(sys.argv[1])); st["verdicts"] = []; json.dump(st, open(sys.argv[1], "w"))
PY
rm -f "${plan%.md}.judge.md"
out=$(cli verdict evidence-owed "$plan" --report "the cases have no capture" --decide D1 let-through x --owed verify); rc=$?
assert_eq 1 "$rc" "evidence-owed takes no decisions" || exit 1
cli verdict evidence-owed "$plan" --owed verify --report "the cases have no capture" >/dev/null || fail "evidence-owed with an Open entry undecided"
assert_contains "$(statuses)" "owed by verify: the cases have no capture" "status lists it" || exit 1
b=$(cli brief judge "$plan") || fail "brief judge"
grep -q "^Owed: verify" "$b" && grep -q "^Case: at the gate" "$b" || fail "the next brief is the same case"
[ ! -e "${plan%.md}.judge.md" ] || fail "no judge file from an owed verdict"
cli verdict evidence-owed "$plan" --owed reviewer --report "the range was not reviewed" >/dev/null || fail "evidence-owed names the judge's word: reviewer"
assert_contains "$(statuses)" "owed by reviewer: the range was not reviewed" "status lists the reviewer" || exit 1
out=$(cli verdict pass "$plan" --report r --decide D1 let-through x); rc=$?
assert_eq 1 "$rc" "the first real verdict still needs the Prediction" || exit 1

# land#backup-first: a tree on another branch than the plan's is refused by every action, naming both
newrepo
git checkout -q -b other
echo z > src/z.txt; git add src/z.txt; git commit -q -m z -- src/z.txt
oh=$(git rev-parse HEAD)
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/z.txt
for act in "land" "land draft" "land accept --note x" "land revert"; do
  out=$(cli $act "$plan"); rc=$?
  assert_eq 1 "$rc" "$act is refused on another branch" || exit 1
  assert_contains "$out" "wrong-branch" "$act: the code" || exit 1
  assert_contains "$out" "other" "$act: names the tree's branch" || exit 1
  assert_contains "$out" "\`l\`" "$act: names the plan's branch" || exit 1
done
assert_eq "$oh" "$(git rev-parse HEAD)" "the other branch is untouched" || exit 1
[ -z "$(git branch --list 'backup/*')" ] || fail "no backup from a refused land"

# land#recorded: a refused land keeps a hand-written section of a plan with no land record
newrepo
printf '\n## Human gate\n\n### The commits · landed abc1234 · backup/l-9\n\nhand written\n' >> "$plan"
echo u > untracked.txt
out=$(cli land "$plan"); rc=$?
assert_eq 1 "$rc" "dirty tree refused" || exit 1
assert_contains "$out" "dirty-tree" "the code" || exit 1
grep -q "^### The commits · landed abc1234 · backup/l-9$" "$plan" && grep -q "^hand written$" "$plan" || fail "the hand-written section survives: $(tail -8 "$plan")"
rm untracked.txt

# land#checked-tree: a tracked file .gitignore matches is carried by the rewrite, with no difference reported
newrepo
echo '*.gen' >> .git/info/exclude
echo g > src/x.gen; git add -f src/x.gen; git commit -q -m gen -- src/x.gen
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt src/x.gen
out=$(cli land "$plan") || fail "land ignored: $out"
git ls-tree -r --name-only HEAD | grep -qx src/x.gen || fail "the tip lacks the ignored tracked file"
case "$out" in *differs*) fail "no difference expected: $out";; esac

# land#backup-first: a backup namespace collision stops before a hook or rewrite runs.
newrepo
pre=$(git rev-parse HEAD)
git branch backup || fail "reserve the backup namespace"
hook
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
out=$(cli land "$plan" 2>&1); rc=$?
assert_eq 1 "$rc" "a failed backup refuses land" || exit 1
assert_contains "$out" "git-failed:" "backup failure is a normal diagnostic" || exit 1
assert_contains "$out" "backup/l-1" "the failed backup is named" || exit 1
assert_eq "$pre" "$(git rev-parse HEAD)" "backup failure leaves the branch unchanged" || exit 1
git diff --quiet HEAD || fail "backup failure leaves the tree unchanged"
grep -q fmt src/a.txt && fail "the hook must not run without a backup"
python3 - "${plan%.md}.json" <<'PY' || fail "backup failure records no land"
import json, sys
assert not json.load(open(sys.argv[1])).get("lands")
PY

git_bin=$(mktemp_dir)
export LAND_REAL_GIT=$(command -v git)
cat > "$git_bin/git" <<'GIT'
#!/bin/sh
case "$*" in
  "$LAND_FAIL_GIT"*) echo "injected Git failure: $LAND_FAIL_GIT" >&2; exit 128 ;;
esac
if [ "${LAND_FAIL_ROLLBACK:-}" = 1 ] && [ "$1 $2 $3" = 'reset -q --hard' ]; then
  echo 'injected rollback failure' >&2
  exit 128
fi
exec "$LAND_REAL_GIT" "$@"
GIT
chmod +x "$git_bin/git"

# land#checked-tree: failed reads and writes never become a successful land.
for command in 'status --porcelain' 'diff --name-only -z --no-renames' 'branch --list' reset 'add -A' commit 'diff --name-only -z backup/'; do
  newrepo
  pre=$(git rev-parse HEAD)
  [ "$command" != reset ] || command="reset -q $(git rev-parse v0)"
  hook
  write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
  cp "${plan%.md}.json" "$git_bin/state"
  cp "$plan" "$git_bin/plan"
  out=$(PATH="$git_bin:$PATH" LAND_FAIL_GIT="$command" cli land "$plan" 2>&1); rc=$?
  assert_eq 1 "$rc" "$command failure refuses land" || exit 1
  assert_contains "$out" "git-failed:" "$command failure uses Refuse" || exit 1
  assert_contains "$out" "injected Git failure: $command" "$command failure preserves the cause" || exit 1
  case "$out" in *Traceback*|*"the tip's tree is the backup's"*) fail "false success or traceback: $out";; esac
  assert_eq "$pre" "$(git rev-parse HEAD)" "$command failure preserves or restores HEAD" || exit 1
  git diff --quiet HEAD || fail "$command failure preserves or restores the tree"
  cmp -s "$git_bin/state" "${plan%.md}.json" && cmp -s "$git_bin/plan" "$plan" || fail "$command failure changes no record"
  case "$command" in
    reset*|add*|commit*|'diff --name-only -z backup/'*)
      assert_eq "$pre" "$(git rev-parse backup/l-1)" "the backup survives $command failure" || exit 1
      assert_contains "$out" "land-restored:" "successful rollback is reported" || exit 1 ;;
    *) [ -z "$(git branch --list 'backup/*')" ] || fail "$command failure must precede the backup" ;;
  esac
done

# land#backup-first: a failed rollback retains the recovery ref and the original state.
newrepo
pre=$(git rev-parse HEAD)
write_shape "" src/a.txt docs/spec/README.md docs/spec/archive/2026-11-16-l.md docs/spec/land.md -- src/b.txt src/c.txt
cp "${plan%.md}.json" "$git_bin/state"
out=$(PATH="$git_bin:$PATH" LAND_FAIL_GIT=commit LAND_FAIL_ROLLBACK=1 cli land "$plan" 2>&1); rc=$?
assert_eq 1 "$rc" "failed commit and rollback refuse land" || exit 1
assert_contains "$out" "injected Git failure: commit" "the original error survives" || exit 1
assert_contains "$out" "rollback-failed: injected rollback failure" "rollback failure is explicit" || exit 1
assert_contains "$out" 'git reset --hard backup/l-1' "recovery names the usable backup" || exit 1
case "$out" in *land-restored*|*Traceback*) fail "rollback did not succeed: $out";; esac
assert_eq "$pre" "$(git rev-parse backup/l-1)" "failed rollback keeps the backup" || exit 1
assert_eq "$(git rev-parse v0)" "$(git rev-parse HEAD)" "failed rollback is not silently restored" || exit 1
cmp -s "$git_bin/state" "${plan%.md}.json" || fail "failed rollback changes no record"
git reset -q --hard backup/l-1 || fail "the backup permits recovery"

# land#recorded: failed revert keeps its land record and backup, with no traceback.
cli land "$plan" >/dev/null || fail "land after recovery"
tip=$(git rev-parse HEAD)
cp "${plan%.md}.json" "$git_bin/state"
out=$(PATH="$git_bin:$PATH" LAND_FAIL_GIT='reset -q --hard' cli land revert "$plan" 2>&1); rc=$?
assert_eq 1 "$rc" "failed revert refuses" || exit 1
assert_contains "$out" "git-failed:" "failed revert uses Refuse" || exit 1
case "$out" in *"land reverted"*|*Traceback*) fail "failed revert must not claim success: $out";; esac
assert_eq "$tip" "$(git rev-parse HEAD)" "failed revert leaves HEAD" || exit 1
assert_eq "$pre" "$(git rev-parse backup/l-2)" "failed revert keeps its backup" || exit 1
cmp -s "$git_bin/state" "${plan%.md}.json" || fail "failed revert keeps the land record"

# the epic's Interfaces: `land` with no arguments is a usage error
out=$(cli land 2>&1); rc=$?
assert_eq 2 "$rc" "land with no arguments exits 2" || exit 1
case "$out" in *Traceback*) fail "no traceback: $out";; esac
echo "land.test.sh: ok"
