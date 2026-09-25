#!/usr/bin/env bash
# Pins skills/finish/scripts/finish: squash collapses a unit's commits by
# meaning, records a recovery ref at the pre-squash HEAD and preserves the tree;
# recover restores a named attempt; merge lands the unit with --no-ff, moving a
# stacked unit onto the default branch once its predecessor has landed.
#
# Every invocation runs with a throwaway gitfixture repository as the working
# directory — finish resolves its own repository root from the cwd, and a
# case that forgot this would run squash or recover against the repository
# these tests themselves live in.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/lib/gitfixture.sh"

finish="$repo_root/skills/finish/scripts/finish"

fail() {
  echo "finish.test.sh: $1" >&2
  exit 1
}

run_finish() {
  local repo="$1"
  shift
  out=$(cd "$repo" && "$finish" "$@" 2>&1)
  rc=$?
}

msgdir=$(mktemp_dir)
msg() {
  printf '%s\n' "$2" > "$msgdir/$1"
  echo "$msgdir/$1"
}

repo1=$(gitfixture_new)
gitfixture_branch "$repo1" work
start_sha=$(git -C "$repo1" rev-parse HEAD)
gitfixture_commit "$repo1" "feat: one" >/dev/null
gitfixture_commit "$repo1" "feat: two" >/dev/null
head_before_squash=$(gitfixture_commit "$repo1" "feat: three")
pre_tree=$(git -C "$repo1" rev-parse 'HEAD^{tree}')

run_finish "$repo1" squash "$(msg bad 'not a conventional commit subject')"
[ "$rc" -ne 0 ] || fail "a non-Conventional subject should have been refused"
assert_contains "$out" "not Conventional Commits" "the refusal should say why" || fail "refusal message missing"
assert_eq "$head_before_squash" "$(git -C "$repo1" rev-parse HEAD)" \
  "HEAD must be unchanged when the message is refused" || fail "HEAD moved despite refusal"

run_finish "$repo1" squash "$(msg long "feat: $(printf 'x%.0s' $(seq 1 70))")"
[ "$rc" -ne 0 ] || fail "a subject over 72 should have been refused"
assert_contains "$out" "over 72" "the refusal should name the cap" || fail "72 refusal missing"

run_finish "$repo1" squash "$(msg body "feat: ok

$(printf 'y%.0s' $(seq 1 301))")"
[ "$rc" -ne 0 ] || fail "a body over 300 should have been refused"
assert_contains "$out" "over 300" "the refusal should name the cap" || fail "300 refusal missing"

run_finish "$repo1" preflight
[ "$rc" -eq 0 ] || fail "preflight on a clean unit branch should exit 0: $out"
assert_contains "$out" "base:     $(git -C "$repo1" rev-parse --short "$start_sha")" \
  "preflight should find the merge-base with main" || fail "preflight base wrong"
assert_contains "$out" "feat: three" "preflight should list the commits" || fail "preflight commits missing"

repo_norecover=$(gitfixture_new)
run_finish "$repo_norecover" recover
[ "$rc" -ne 0 ] || fail "recover with no ref should be non-zero"
assert_contains "$out" "no recovery ref" "recover with no ref should say so" || fail "message missing"

run_finish "$repo1" squash "$(msg good 'feat: squash the unit into one commit')"
[ "$rc" -eq 0 ] || fail "squash with a Conventional subject should exit 0: $out"
assert_eq "1" "$(git -C "$repo1" rev-list --count "$start_sha..HEAD")" \
  "squash should leave exactly one commit above base" || fail "commit count wrong"
assert_eq "$pre_tree" "$(git -C "$repo1" rev-parse 'HEAD^{tree}')" \
  "the tree must survive the squash" || fail "tree changed across the squash"
assert_eq "$start_sha" "$(git -C "$repo1" rev-parse HEAD^)" \
  "the squashed commit should sit on the base" || fail "squash parent wrong"
assert_eq "feat: squash the unit into one commit" "$(git -C "$repo1" log -1 --format=%s)" \
  "the message file is the subject" || fail "subject wrong"
assert_eq "$head_before_squash" "$(git -C "$repo1" rev-parse refs/dev-skills/recovery/work/1)" \
  "attempt 1 should resolve to the pre-squash HEAD" || fail "recovery ref wrong"

head_before_listing=$(git -C "$repo1" rev-parse HEAD)
run_finish "$repo1" recover
[ "$rc" -ne 0 ] || fail "recover with no attempt should be non-zero"
assert_contains "$out" "finish recover <attempt>" "it should say how to name one" || fail "usage hint missing"
assert_eq "$head_before_listing" "$(git -C "$repo1" rev-parse HEAD)" \
  "listing the attempts must not move HEAD" || fail "HEAD moved while listing"

gitfixture_commit "$repo1" "fix: something the review asked for" >/dev/null
head_before_second_squash=$(git -C "$repo1" rev-parse HEAD)
run_finish "$repo1" squash "$(msg again 'feat: squash the unit again')"
[ "$rc" -eq 0 ] || fail "the second squash should exit 0: $out"
assert_eq "$head_before_squash" "$(git -C "$repo1" rev-parse refs/dev-skills/recovery/work/1)" \
  "attempt 1 must still point where it did" || fail "attempt 1 was overwritten"
assert_eq "$head_before_second_squash" "$(git -C "$repo1" rev-parse refs/dev-skills/recovery/work/2)" \
  "attempt 2 should be the pre-second-squash HEAD" || fail "attempt 2 wrong"

run_finish "$repo1" recover 1
[ "$rc" -eq 0 ] || fail "recover 1 should exit 0"
assert_eq "$head_before_squash" "$(git -C "$repo1" rev-parse HEAD)" \
  "recover 1 should restore the first pre-squash HEAD" || fail "HEAD not restored"

head_before_bad_attempt=$(git -C "$repo1" rev-parse HEAD)
run_finish "$repo1" recover 99
[ "$rc" -ne 0 ] || fail "an unknown attempt should be non-zero"
assert_eq "$head_before_bad_attempt" "$(git -C "$repo1" rev-parse HEAD)" \
  "an unknown attempt must not move HEAD" || fail "HEAD moved on an unknown attempt"

repo_groups=$(gitfixture_new)
gitfixture_branch "$repo_groups" feat/groups
g_base=$(git -C "$repo_groups" rev-parse HEAD)
gitfixture_commit "$repo_groups" "fix: the bug found on the way" >/dev/null
g_fix_end=$(gitfixture_commit "$repo_groups" "test: pin the bug")
gitfixture_commit "$repo_groups" "feat: step 1" >/dev/null
gitfixture_commit "$repo_groups" "feat: step 2" >/dev/null
g_tree=$(git -C "$repo_groups" rev-parse 'HEAD^{tree}')
fix_msg=$(msg g1 'fix(core): the bug found on the way')
feat_msg=$(msg g2 'feat(core): the unit')
run_finish "$repo_groups" squash "$fix_msg" "$feat_msg"
[ "$rc" -ne 0 ] || fail "two message files with no --through between them should be refused"
assert_contains "$out" "needs one" "the refusal says a --through is missing" || fail "through refusal reason"
git -C "$repo_groups" rev-parse --verify --quiet refs/dev-skills/recovery/feat/groups/1 >/dev/null \
  && fail "a refused squash must record no recovery ref"
run_finish "$repo_groups" squash "$fix_msg" --through "$g_fix_end" "$feat_msg"
[ "$rc" -eq 0 ] || fail "squash by meaning should exit 0: $out"
assert_eq "2" "$(git -C "$repo_groups" rev-list --count "$g_base..HEAD")" \
  "two meanings should land as two commits" || fail "group count wrong"
assert_eq "$(git -C "$repo_groups" rev-parse "$g_fix_end^{tree}")" "$(git -C "$repo_groups" rev-parse 'HEAD^^{tree}')" \
  "the first commit holds the tree at the end of its group" || fail "first group tree wrong"
assert_eq "$g_tree" "$(git -C "$repo_groups" rev-parse 'HEAD^{tree}')" \
  "the last commit holds HEAD's tree" || fail "last group tree wrong"
assert_eq "fix(core): the bug found on the way" "$(git -C "$repo_groups" log -1 --format=%s HEAD^)" \
  "the first group carries its own message" || fail "first group message wrong"

run_finish "$repo_groups" merge
[ "$rc" -eq 0 ] || fail "merge of a squashed unit should exit 0: $out"
merge_commit=$(git -C "$repo_groups" rev-parse main)
assert_eq "2" "$(git -C "$repo_groups" rev-list --parents -n1 main | wc -w | awk '{print $1-1}')" \
  "main should end in a merge commit with two parents" || fail "not a --no-ff merge"
assert_eq "$(git -C "$repo_groups" rev-parse feat/groups)" "$(git -C "$repo_groups" rev-parse "$merge_commit^2")" \
  "the merge's second parent is the unit" || fail "second parent wrong"
assert_eq "feat/groups" "$(git -C "$repo_groups" symbolic-ref --short HEAD)" \
  "the checkout is back on the unit's branch" || fail "not switched back"
assert_eq "feat(core): the unit" "$(git -C "$repo_groups" log -1 --format=%s main)" \
  "the merge commit takes the unit's last subject" || fail "merge subject wrong"

repo_subj=$(gitfixture_new)
gitfixture_branch "$repo_subj" feat/subj
gitfixture_commit "$repo_subj" "work in progress" >/dev/null
subj_main=$(git -C "$repo_subj" rev-parse main)
run_finish "$repo_subj" merge
[ "$rc" -ne 0 ] || fail "merge should refuse a subject that is not Conventional"
assert_contains "$out" "--subject" "the refusal points at --subject" || fail "subject refusal reason"
assert_eq "$subj_main" "$(git -C "$repo_subj" rev-parse main)" "a refused merge leaves main alone" || fail "main moved on refusal"
assert_eq "feat/subj" "$(git -C "$repo_subj" symbolic-ref --short HEAD)" \
  "a refused merge stays on the unit's branch" || fail "switched on subject refusal"
run_finish "$repo_subj" merge --subject "feat: named at the merge"
[ "$rc" -eq 0 ] || fail "merge with --subject should exit 0: $out"
assert_eq "feat: named at the merge" "$(git -C "$repo_subj" log -1 --format=%s main)" \
  "--subject titles the merge commit" || fail "--subject not used"

repo_dirty=$(gitfixture_new)
gitfixture_branch "$repo_dirty" feat/dirty
gitfixture_commit "$repo_dirty" "feat: work" >/dev/null
printf 'uncommitted\n' >> "$repo_dirty/README.md"
main_before=$(git -C "$repo_dirty" rev-parse main)
run_finish "$repo_dirty" merge
[ "$rc" -ne 0 ] || fail "merge should refuse a dirty tree"
assert_eq "feat/dirty" "$(git -C "$repo_dirty" symbolic-ref --short HEAD)" \
  "a refused merge leaves the checkout on its branch" || fail "switched despite refusal"
assert_contains "$out" "modified but not committed" "the refusal names the dirty tree" || fail "dirty message missing"
assert_eq "$main_before" "$(git -C "$repo_dirty" rev-parse main)" "main must not move" || fail "main moved"

repo_wt=$(gitfixture_new)
wt="$(mktemp_dir)/wt"
git -C "$repo_wt" worktree add -q -b feat/wt "$wt" >/dev/null 2>&1
gitfixture_commit "$wt" "feat: built in a worktree" >/dev/null
run_finish "$wt" merge
[ "$rc" -eq 0 ] || fail "merge from a worktree should exit 0: $out"
assert_eq "$(git -C "$wt" rev-parse HEAD)" "$(git -C "$repo_wt" rev-parse main^2)" \
  "main in the main checkout gets the worktree's branch" || fail "worktree merge wrong"
assert_eq "feat/wt" "$(git -C "$wt" symbolic-ref --short HEAD)" \
  "the worktree stays on its branch" || fail "worktree switched"
printf 'in the way\n' > "$repo_wt/README.md"
gitfixture_commit "$wt" "feat: more" >/dev/null
run_finish "$wt" merge
[ "$rc" -ne 0 ] || fail "merge should refuse when the checkout holding main is dirty"

preflight="$repo_root/skills/implement/scripts/preflight"
cut() {
  (cd "$1" && "$preflight" "${@:2}" >/dev/null 2>&1) || fail "preflight ${*:2} failed in $1"
}
add_file() {
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -q -m "$3"
}

repo_stack=$(gitfixture_new)
gitfixture_gitignore "$repo_stack"
cut "$repo_stack" feat/a
add_file "$repo_stack" a.txt "feat: a"
a1=$(git -C "$repo_stack" rev-parse HEAD)
cut "$repo_stack" --from feat/a feat/b
add_file "$repo_stack" b.txt "feat: b"
b_tip=$(git -C "$repo_stack" rev-parse HEAD)

run_finish "$repo_stack" merge
[ "$rc" -ne 0 ] || fail "a unit stacked on an unlanded branch should be refused"
assert_contains "$out" "has not landed" "the refusal names the unlanded predecessor" || fail "stack refusal missing: $out"
assert_eq "$b_tip" "$(git -C "$repo_stack" rev-parse HEAD)" "the refusal changes nothing" || fail "HEAD moved"
git -C "$repo_stack" rev-parse --verify --quiet refs/dev-skills/recovery/feat/b/1 >/dev/null \
  && fail "a refused merge must record no recovery ref"

run_finish "$repo_stack" squash "$(msg b 'feat: land b')"
[ "$rc" -eq 0 ] || fail "squash of b ahead of a should exit 0: $out"
assert_eq "$a1" "$(git -C "$repo_stack" rev-parse HEAD^)" "b squashes onto its recorded base" || fail "b base wrong"

git -C "$repo_stack" checkout -q feat/a
printf 'a, reviewed\n' > "$repo_stack/a.txt"
git -C "$repo_stack" commit -q -am "fix: a review fix after b started"
run_finish "$repo_stack" preflight
assert_contains "$out" " feat: a" "a's preflight lists a's own commits" || fail "a preflight: $out"
run_finish "$repo_stack" squash "$(msg a 'feat: land a')"
[ "$rc" -eq 0 ] || fail "squash of a should exit 0 after b was squashed: $out"
assert_eq "$(git -C "$repo_stack" rev-parse main)" "$(git -C "$repo_stack" rev-parse HEAD^)" \
  "a squashes onto main, not onto anything b recorded" || fail "a base moved by b"

git -C "$repo_stack" checkout -q feat/b
run_finish "$repo_stack" merge
[ "$rc" -ne 0 ] || fail "b should still be refused while a is squashed but not merged"
assert_contains "$out" "has not landed" "b's refusal says a has not landed" || fail "b refusal reason: $out"

git -C "$repo_stack" checkout -q feat/a
run_finish "$repo_stack" merge
[ "$rc" -eq 0 ] || fail "merge of a should exit 0: $out"
git -C "$repo_stack" branch -q -d feat/a

main_wt="$(mktemp_dir)/main"
git -C "$repo_stack" checkout -q feat/b
git -C "$repo_stack" worktree add -q "$main_wt" main >/dev/null 2>&1
printf 'dirty\n' >> "$main_wt/README.md"
b_squashed=$(git -C "$repo_stack" rev-parse HEAD)
run_finish "$repo_stack" merge
[ "$rc" -ne 0 ] || fail "merge should refuse when the checkout holding main is dirty"
assert_eq "$b_squashed" "$(git -C "$repo_stack" rev-parse HEAD)" \
  "the dirty refusal comes before b is moved" || fail "b moved before the refusal"
git -C "$main_wt" checkout -q -- README.md

run_finish "$repo_stack" merge
[ "$rc" -eq 0 ] || fail "merge of b after a landed (and its branch was deleted) should exit 0: $out"
assert_eq "feat: land b" "$(git -C "$repo_stack" log -1 --format=%s main^2)" \
  "main's last merge brings b" || fail "b not merged"
assert_eq "b.txt" "$(git -C "$repo_stack" diff --name-only main^2^ main^2)" \
  "b's landing commit carries only b's change" || fail "b carried a's change"
assert_eq "1" "$(git -C "$repo_stack" rev-list --count main^1..main^2)" \
  "b lands as one commit on top of main" || fail "b landed with extra commits"
git -C "$repo_stack" cat-file -e main:a.txt && git -C "$repo_stack" cat-file -e main:b.txt \
  || fail "main should hold both units' files"

repo_skip=$(gitfixture_new)
gitfixture_gitignore "$repo_skip"
cut "$repo_skip" feat/a
add_file "$repo_skip" a.txt "feat: a"
a1=$(git -C "$repo_skip" rev-parse HEAD)
cut "$repo_skip" --from feat/a feat/d
add_file "$repo_skip" d.txt "feat: d"
run_finish "$repo_skip" squash "$(msg d 'feat: land d')"
[ "$rc" -eq 0 ] || fail "squash of d should exit 0: $out"
git -C "$repo_skip" rebase -q --onto main "$a1" feat/d
run_finish "$repo_skip" merge
[ "$rc" -eq 0 ] || fail "d, moved onto main by hand, should merge: $out"
git -C "$repo_skip" checkout -q feat/a
cut "$repo_skip" --from feat/a feat/b
add_file "$repo_skip" b.txt "feat: b"
run_finish "$repo_skip" merge
[ "$rc" -ne 0 ] || fail "b must not land because a sibling stacked on the same base landed"
assert_contains "$out" "has not landed" "the sibling refusal says why" || fail "sibling reason: $out"

repo_del=$(gitfixture_new)
gitfixture_gitignore "$repo_del"
printf 'old\n' > "$repo_del/old.txt"
git -C "$repo_del" add old.txt
git -C "$repo_del" commit -q -m "chore: old"
cut "$repo_del" feat/a
git -C "$repo_del" rm -q old.txt
git -C "$repo_del" commit -q -m "feat: drop old"
cut "$repo_del" --from feat/a feat/b
add_file "$repo_del" b.txt "feat: b"
git -C "$repo_del" checkout -q main
printf 'old, edited\n' > "$repo_del/old.txt"
git -C "$repo_del" commit -q -am "fix: edit old"
git -C "$repo_del" checkout -q feat/b
run_finish "$repo_del" merge
[ "$rc" -ne 0 ] || fail "a conflicting merge-tree whose tree equals main's must not count as landed"

repo_hand=$(gitfixture_new)
gitfixture_branch "$repo_hand" feat/a
add_file "$repo_hand" a.txt "feat: a"
gitfixture_branch "$repo_hand" feat/b
add_file "$repo_hand" b.txt "feat: b"
run_finish "$repo_hand" preflight
assert_contains "$out" "carries commits of feat/a" "preflight names the carried branch" || fail "hand stack note: $out"
hand_tip=$(git -C "$repo_hand" rev-parse HEAD)
run_finish "$repo_hand" squash "$(msg hand 'feat: land b')"
[ "$rc" -ne 0 ] || fail "squash must refuse a range that carries an unlanded branch"
assert_contains "$out" "carries commits of feat/a" "the squash refusal names the carried branch" || fail "hand squash reason: $out"
assert_eq "$hand_tip" "$(git -C "$repo_hand" rev-parse HEAD)" "the squash refusal moves nothing" || fail "hand squash moved HEAD"
run_finish "$repo_hand" merge
[ "$rc" -ne 0 ] || fail "a hand-cut stack must not land its predecessor"
assert_contains "$out" "carries commits of feat/a" "the refusal names the carried branch" || fail "hand stack reason: $out"

repo_reb=$(gitfixture_new)
gitfixture_branch "$repo_reb" other
printf 'other\n' > "$repo_reb/README.md"
git -C "$repo_reb" commit -q -am "feat: other"
git -C "$repo_reb" checkout -q main
printf 'main\n' > "$repo_reb/README.md"
git -C "$repo_reb" commit -q -am "feat: main"
reb_wt="$(mktemp_dir)/wt"
git -C "$repo_reb" worktree add -q -b feat/r "$reb_wt" >/dev/null 2>&1
gitfixture_commit "$reb_wt" "feat: r" >/dev/null
git -C "$repo_reb" rebase -q other >/dev/null 2>&1
run_finish "$reb_wt" merge
[ "$rc" -ne 0 ] || fail "merge must refuse while main is being rebased elsewhere"
assert_contains "$out" "being rebased" "the refusal names the rebase" || fail "rebase reason: $out"

repo_old=$(gitfixture_new)
m0=$(git -C "$repo_old" rev-parse HEAD)
gitfixture_branch "$repo_old" feat/u
add_file "$repo_old" u.txt "feat: u1"
git -C "$repo_old" checkout -q main
add_file "$repo_old" other.txt "feat: someone else's work"
git -C "$repo_old" checkout -q feat/u
git -C "$repo_old" merge -q --no-edit main
add_file "$repo_old" u2.txt "feat: u2"
run_finish "$repo_old" squash --base "$m0" "$(msg u 'feat: land u')"
[ "$rc" -eq 0 ] || fail "squash with an old --base should exit 0: $out"
assert_eq "u.txt u2.txt" "$(git -C "$repo_old" diff --name-only HEAD^ HEAD | tr '\n' ' ' | sed 's/ $//')" \
  "an old base below main's merge does not pull main's work in" || fail "main's commits folded in"

repo_hash=$(gitfixture_new)
gitfixture_branch "$repo_hash" fix/hash
gitfixture_commit "$repo_hash" "fix: one" >/dev/null
run_finish "$repo_hash" squash "$(msg hash '#42 fix: handle the thing')"
[ "$rc" -eq 0 ] || fail "a '#N type:' subject should be accepted: $out"
assert_eq "#42 fix: handle the thing" "$(git -C "$repo_hash" log -1 --format=%s)" \
  "the '#N' subject is kept, not stripped as a comment" || fail "subject stripped"

repo_busy=$(gitfixture_new)
gitfixture_branch "$repo_busy" side
gitfixture_commit "$repo_busy" "feat: side" >/dev/null
git -C "$repo_busy" checkout -q main
busy_wt="$(mktemp_dir)/wt"
git -C "$repo_busy" worktree add -q -b feat/busy "$busy_wt" >/dev/null 2>&1
gitfixture_commit "$busy_wt" "feat: busy" >/dev/null
git -C "$repo_busy" merge -q --no-ff --no-commit -s ours side >/dev/null 2>&1
run_finish "$busy_wt" merge
[ "$rc" -ne 0 ] || fail "merge should refuse while main's checkout is mid-merge"
assert_contains "$out" "merge in progress in" "the refusal names the half-done merge" || fail "busy reason: $out"
git -C "$repo_busy" rev-parse -q --verify MERGE_HEAD >/dev/null || fail "the user's merge must survive"

repo_empty=$(gitfixture_new)
gitfixture_branch "$repo_empty" feat/empty
run_finish "$repo_empty" merge
[ "$rc" -ne 0 ] || fail "merge of an empty range should be refused"
run_finish "$repo_empty" preflight
[ "$rc" -ne 0 ] || fail "preflight of an empty range should be refused"
git -C "$repo_empty" checkout -q main
run_finish "$repo_empty" preflight
assert_contains "$out" "on the default branch" "preflight on main is refused" || fail "main refusal: $out"
git -C "$repo_empty" checkout -q --detach
run_finish "$repo_empty" preflight
assert_contains "$out" "detached HEAD" "preflight on a detached HEAD is refused" || fail "detached refusal: $out"

echo "ok"
