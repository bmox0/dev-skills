#!/usr/bin/env bash
# Pins skills/implement/scripts/preflight: it cuts the branch or the worktree,
# prepares a worktree from CLAUDE.md's ## Environment block, and reports the
# git state that stands in the way (0 clean, 1 findings, 2 not a repository or
# bad arguments). Every case runs against its own throwaway repository.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/lib/gitfixture.sh"

script="$repo_root/skills/implement/scripts/preflight"

fail() {
  echo "preflight.test.sh: $1" >&2
  exit 1
}

run_preflight() {
  local repo="$1"
  shift
  out=$(cd "$repo" && "$script" "$@" 2>&1)
  rc=$?
}

nested_repo() {
  local parent
  parent=$(mktemp_dir)
  git -C "$parent" init -q -b main repo
  git -C "$parent/repo" config user.email "fixture@example.com"
  git -C "$parent/repo" config user.name "gitfixture"
  printf '# fixture\n' > "$parent/repo/README.md"
  printf '.ai-workflow\n' > "$parent/repo/.gitignore"
  git -C "$parent/repo" add README.md .gitignore
  git -C "$parent/repo" commit -q -m "chore: initial commit"
  echo "$(cd "$parent" && pwd -P)/repo"
}

repo=$(gitfixture_new)
gitfixture_gitignore "$repo"
run_preflight "$repo"
assert_eq 1 "$rc" "on main with no branch: exit 1" || fail "TC-1: $out"
assert_contains "$out" "on the default branch (main)" "on main: the default-branch finding" || fail "TC-1"

run_preflight "$repo" feat/one
assert_eq 0 "$rc" "preflight feat/one: exit 0" || fail "TC-2: $out"
assert_eq "feat/one" "$(git -C "$repo" symbolic-ref --short HEAD)" "the branch is cut and checked out" || fail "TC-2"
assert_eq "$(git -C "$repo" rev-parse main)" "$(git -C "$repo" rev-parse feat/one)" "it starts at main" || fail "TC-2"
assert_contains "$out" "preflight clean" "a fresh branch is clean" || fail "TC-2"

gitfixture_commit "$repo" "feat: work on one" >/dev/null
git -C "$repo" checkout -q main
run_preflight "$repo" feat/one
assert_eq 0 "$rc" "an existing branch is resumed: exit 0" || fail "TC-3: $out"
assert_eq "feat/one" "$(git -C "$repo" symbolic-ref --short HEAD)" "the existing branch is checked out" || fail "TC-3"
assert_eq 1 "$(git -C "$repo" rev-list --count main..feat/one)" "resuming keeps its commits" || fail "TC-3"

run_preflight "$repo" --from feat/one feat/two
assert_eq 0 "$rc" "a stacked branch: exit 0" || fail "TC-4: $out"
assert_eq "$(git -C "$repo" rev-parse feat/one)" "$(git -C "$repo" rev-parse feat/two)" "it starts at its predecessor" || fail "TC-4"
assert_contains "$out" "stacked on feat/one, which has not landed on main" "the unmerged predecessor is named" || fail "TC-4"

gitfixture_commit "$repo" "feat: work on two" >/dev/null
run_preflight "$repo"
assert_contains "$out" "stacked on feat/one, which has not landed on main" "a check on a stacked branch names it" || fail "TC-5: $out"

gitfixture_dirty "$repo"
run_preflight "$repo"
assert_eq 1 "$rc" "dirty tree: exit 1" || fail "TC-6: $out"
assert_contains "$out" "uncommitted changes (1 staged, 1 unstaged)" "the dirty finding counts both" || fail "TC-6"

repo=$(gitfixture_new)
gitfixture_branch "$repo" work
printf 'node_modules' > "$repo/.git/info/exclude"
run_preflight "$repo"
assert_eq 0 "$rc" "a branch with nothing ignoring .ai-workflow: exit 0" || fail "TC-7: $out"
assert_contains "$out" "fixed: added .ai-workflow to" "the exclude line is added" || fail "TC-7"
assert_eq "node_modules
.ai-workflow" "$(cat "$repo/.git/info/exclude")" "the exclude keeps its last line intact" || fail "TC-7"
[ ! -e "$repo/.gitignore" ] || fail "TC-7: no tracked file is touched"
git -C "$repo" check-ignore -q .ai-workflow || fail "TC-7: .ai-workflow should now be ignored"
run_preflight "$repo"
! printf '%s' "$out" | grep -q "fixed:" || fail "TC-7b: a second run fixes nothing"
repo=$(gitfixture_new)
gitfixture_branch "$repo" work
printf '/.ai-workflow\n' > "$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -q -m "chore: ignore"
run_preflight "$repo"
! printf '%s' "$out" | grep -q "fixed:" || fail "TC-7c: an existing ignore rule is respected: $out"

repo=$(gitfixture_new)
gitfixture_gitignore "$repo"
git -C "$repo" checkout -q --detach
run_preflight "$repo"
assert_contains "$out" "detached HEAD" "a detached HEAD is a finding" || fail "TC-8: $out"

repo=$(gitfixture_new)
gitfixture_gitignore "$repo"
gitfixture_branch "$repo" side
printf 'side\n' > "$repo/README.md"
git -C "$repo" commit -q -am "feat: side"
git -C "$repo" checkout -q main
printf 'main\n' > "$repo/README.md"
git -C "$repo" commit -q -am "feat: main"
git -C "$repo" checkout -q side
git -C "$repo" merge -q main >/dev/null 2>&1
run_preflight "$repo"
assert_contains "$out" "merge in progress" "a half-done merge is a finding" || fail "TC-9: $out"

outside=$(mktemp_dir)
run_preflight "$outside"
assert_eq 2 "$rc" "outside a repository: exit 2" || fail "TC-10: $out"
run_preflight "$repo" --worktree
assert_eq 2 "$rc" "--worktree needs a branch: exit 2" || fail "TC-10b: $out"
run_preflight "$repo" --from main
assert_eq 2 "$rc" "--from needs a branch: exit 2" || fail "TC-10c: $out"
run_preflight "$repo" 'bad..name'
assert_eq 2 "$rc" "an invalid branch name: exit 2" || fail "TC-10d: $out"

repo=$(nested_repo)
mkdir -p "$repo/.ai-workflow/plans"
printf 'SECRET=1\n' > "$repo/.env.local"
cat > "$repo/CLAUDE.md" <<'EOF'
## Environment

**Tests.** none

**bootstrap.** `printf ready > bootstrapped.txt`
**link.** `.env*` from the main checkout
EOF
git -C "$repo" add CLAUDE.md
git -C "$repo" commit -q -m "docs: environment"
run_preflight "$repo" --worktree feat/wt
wt="$(dirname "$repo")/repo.worktrees/feat-wt"
assert_eq 0 "$rc" "a worktree is cut: exit 0" || fail "TC-11: $out"
assert_contains "$out" "worktree: $wt" "the worktree path is printed" || fail "TC-11"
assert_eq "feat/wt" "$(git -C "$wt" symbolic-ref --short HEAD)" "the worktree is on the new branch" || fail "TC-11"
assert_eq "main" "$(git -C "$repo" symbolic-ref --short HEAD)" "the main checkout stays where it was" || fail "TC-11"
[ -L "$wt/.ai-workflow" ] || fail "TC-11: .ai-workflow should be a symlink in the worktree"
[ -L "$wt/.env.local" ] || fail "TC-11: the link field's .env* should be linked"
assert_eq "ready" "$(cat "$wt/bootstrapped.txt" 2>/dev/null)" "bootstrap ran in the worktree" || fail "TC-11"
[ ! -e "$repo/bootstrapped.txt" ] || fail "TC-11: bootstrap must not run in the main checkout"

run_preflight "$repo" --worktree feat/wt
assert_eq 0 "$rc" "the worktree is resumed: exit 0" || fail "TC-12: $out"
assert_contains "$out" "resuming: feat/wt is checked out at $wt" "resuming names the worktree" || fail "TC-12"

repo=$(nested_repo)
printf '## Environment\n\n**Tests.** none\n' > "$repo/CLAUDE.md"
git -C "$repo" add CLAUDE.md
git -C "$repo" commit -q -m "docs: environment"
run_preflight "$repo" --worktree feat/bare
assert_eq 1 "$rc" "a worktree with no bootstrap or link field: exit 1" || fail "TC-13: $out"
assert_contains "$out" "no 'bootstrap' field" "the missing bootstrap is named" || fail "TC-13"
assert_contains "$out" "no 'link' field" "the missing link is named" || fail "TC-13"

repo=$(nested_repo)
printf '## Environment\n\n**bootstrap.** `exit 3`\n**link.** none\n' > "$repo/CLAUDE.md"
git -C "$repo" add CLAUDE.md
git -C "$repo" commit -q -m "docs: environment"
run_preflight "$repo" --worktree feat/broken
assert_eq 1 "$rc" "a failing bootstrap: exit 1" || fail "TC-14: $out"
assert_contains "$out" "bootstrap failed" "a failing bootstrap is a finding" || fail "TC-14"
! printf '%s' "$out" | grep -q "no 'link' field" || fail "TC-14: a link of none is not a missing field"
run_preflight "$repo" --worktree feat/broken
assert_contains "$out" "bootstrap failed" "a failed bootstrap is reported again on resume" || fail "TC-14b: $out"
wt="$(dirname "$repo")/repo.worktrees/feat-broken"
printf '## Environment\n\n**bootstrap.** `printf ok > done.txt`\n**link.** none\n' > "$wt/CLAUDE.md"
run_preflight "$repo" --worktree feat/broken
assert_eq "ok" "$(cat "$wt/done.txt" 2>/dev/null)" "a fixed bootstrap runs on resume" || fail "TC-14c: $out"
rm "$wt/done.txt"
run_preflight "$repo" --worktree feat/broken
[ ! -e "$wt/done.txt" ] || fail "TC-14d: a bootstrap that succeeded does not run again"

mkdir -p "$(dirname "$repo")/repo.worktrees/feat-taken/x"
run_preflight "$repo" --worktree feat/taken
assert_eq 1 "$rc" "an existing worktree path: exit 1" || fail "TC-15: $out"
git -C "$repo" show-ref --verify --quiet refs/heads/feat/taken && fail "TC-15: no branch is left behind"

run_preflight "$repo" --worktree feat/gone
gone="$(dirname "$repo")/repo.worktrees/feat-gone"
rm -rf "$gone"
run_preflight "$repo" --worktree feat/gone
[ -d "$gone" ] || fail "TC-16: a deleted worktree is recreated: $out"
assert_eq "feat/gone" "$(git -C "$gone" symbolic-ref --short HEAD)" "TC-16: on its branch" || fail "TC-16"

repo=$(gitfixture_new)
gitfixture_gitignore "$repo"
gitfixture_branch "$repo" feat/one
gitfixture_commit "$repo" "feat: one" >/dev/null
run_preflight "$repo" feat/z
assert_eq "$(git -C "$repo" rev-parse main)" "$(git -C "$repo" rev-parse feat/z)" \
  "a new branch starts at the default branch, not at HEAD" || fail "TC-17: $out"
git -C "$repo" checkout -q main
run_preflight "$repo" --from feat/one feat/y
assert_eq "$(git -C "$repo" rev-parse feat/one)" "$(git -C "$repo" rev-parse feat/y)" \
  "--from is the base, whatever HEAD is" || fail "TC-17b: $out"
assert_eq "$(git -C "$repo" rev-parse feat/one)" "$(git -C "$repo" config --get branch.feat/y.devskillsbase)" \
  "the base is recorded for finish" || fail "TC-17c"

git -C "$repo" checkout -q main
printf 'mine\n' >> "$repo/README.md"
run_preflight "$repo" feat/carry
assert_contains "$out" "came along from main" "carried changes are named with where they came from" || fail "TC-18: $out"
git -C "$repo" checkout -q -- README.md

git -C "$repo" remote add origin /nonexistent
git -C "$repo" update-ref refs/remotes/origin/feat/base "$(git -C "$repo" rev-parse feat/one)"
git -C "$repo" checkout -q main
run_preflight "$repo" --from origin/feat/base feat/next
assert_eq 0 "$rc" "cutting from a remote ref: exit 0" || fail "TC-19: $out"
git -C "$repo" rev-parse --abbrev-ref feat/next@{upstream} >/dev/null 2>&1 \
  && fail "TC-19: a branch cut from a remote ref does not track it"
git -C "$repo" update-ref refs/remotes/origin/feat/pushed "$(git -C "$repo" rev-parse feat/one)"
git -C "$repo" checkout -q main
run_preflight "$repo" feat/pushed
assert_eq "$(git -C "$repo" rev-parse feat/one)" "$(git -C "$repo" rev-parse HEAD)" \
  "a branch that exists on the remote is resumed, not cut anew" || fail "TC-19b: $out"

git -C "$repo" checkout -q feat/one
git -C "$repo" checkout -q -b feat/pick main
printf 'pick\n' > "$repo/README.md"
git -C "$repo" commit -q -am "feat: pick"
git -C "$repo" checkout -q feat/one
printf 'other\n' > "$repo/README.md"
git -C "$repo" commit -q -am "feat: clash"
git -C "$repo" cherry-pick feat/pick >/dev/null 2>&1
run_preflight "$repo"
assert_contains "$out" "cherry-pick in progress" "a half-done cherry-pick is a finding" || fail "TC-20: $out"

repo=$(nested_repo)
printf '## Environment\n\n**bootstrap.** `printf x > boot.txt`\n**link.** none\n' > "$repo/CLAUDE.md"
git -C "$repo" add CLAUDE.md
git -C "$repo" commit -q -m "docs: environment"
run_preflight "$repo" --worktree feat/again
wt="$(dirname "$repo")/repo.worktrees/feat-again"
[ -e "$wt/boot.txt" ] || fail "TC-21: first bootstrap: $out"
git -C "$repo" worktree remove --force "$wt"
run_preflight "$repo" --worktree feat/again
[ -e "$wt/boot.txt" ] || fail "TC-21b: a recreated worktree is bootstrapped again: $out"

run_preflight "$repo" --worktree feat/rb
wt="$(dirname "$repo")/repo.worktrees/feat-rb"
printf 'branch\n' > "$wt/README.md"
git -C "$wt" commit -q -am "feat: rb"
printf 'main\n' > "$repo/README.md"
git -C "$repo" commit -q -am "feat: main side"
git -C "$wt" rebase -q main >/dev/null 2>&1
run_preflight "$repo" --worktree feat/rb
assert_contains "$out" "rebase in progress" "a worktree mid-rebase is resumed and reported" || fail "TC-22: $out"
! printf '%s' "$out" | grep -q "already exists" || fail "TC-22: a registered worktree is not a taken path"
git -C "$wt" rebase --abort
run_preflight "$repo" --worktree feat-rb
assert_eq 1 "$rc" "a branch whose sibling path holds another branch is refused" || fail "TC-22b: $out"
assert_contains "$out" "holds another branch" "TC-22b: the refusal says why" || fail "TC-22b"
for i in 1 2 3; do gitfixture_commit "$wt" "feat: rb $i" >/dev/null; done
git -C "$wt" bisect start HEAD HEAD~4 >/dev/null 2>&1
git -C "$wt" symbolic-ref -q HEAD >/dev/null && fail "TC-22c: the bisect should have detached HEAD"
run_preflight "$repo" --worktree feat/rb
assert_contains "$out" "bisect in progress" "TC-22c: a worktree mid-bisect of this branch is resumed" || fail "TC-22c: $out"
git -C "$wt" bisect reset -q >/dev/null 2>&1
git -C "$repo" show-ref --verify --quiet refs/heads/feat-rb && fail "TC-22b: no branch is left behind"

repo=$(gitfixture_new)
git -C "$repo" checkout -q --detach
printf 'mine\n' >> "$repo/README.md"
run_preflight "$repo" feat/d
assert_contains "$out" "git switch --detach" "carried changes from a detached HEAD get advice that works" || fail "TC-23: $out"

repo=$(gitfixture_new)
gitfixture_branch "$repo" work
mkdir -p "$repo/.ai-workflow"
printf 'tracked\n' > "$repo/.ai-workflow/plan.md"
git -C "$repo" add -f .ai-workflow/plan.md
git -C "$repo" commit -q -m "docs: a tracked plan"
run_preflight "$repo"
run_preflight "$repo"
assert_eq 1 "$(grep -cxF .ai-workflow "$repo/.git/info/exclude")" "the exclude line is written once" || fail "TC-24"

repo=$(gitfixture_new)
gitfixture_branch "$repo" feat/x
printf 'b\n' > "$repo/f.txt"
git -C "$repo" add f.txt
git -C "$repo" commit -q -m "feat: f"
git -C "$repo" checkout -q main
printf 'b\n' > "$repo/f.txt"
git -C "$repo" add f.txt
run_preflight "$repo" feat/x
! printf '%s' "$out" | grep -q "came along" || fail "TC-25: a change the branch already has is not carried: $out"

exit 0
