#!/usr/bin/env bash
# Pins skills/implement/scripts/preflight: the findings it reports today and
# the exit code that follows (0 clean, 1 findings, 2 not a repository). Every
# case runs against its own throwaway gitfixture_new repository.
#
# Also pins --parallel, which answers a different question — do these phases'
# write-sets intersect — and needs no repository at all, only a plan. Its cases
# run against test/fixtures/plan-writesets.md.
#
# Also pins preflight's plan-check integration (TC-4, TC-5) and, because
# neither has a CLI seam of its own and the plan authorises no new file for
# them, the basic CLI contract of brief and dispatch (TC-6, TC-7, TC-8) —
# both need a real repository to derive their workspace from, the same
# gitfixture this file already builds every other case on.
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

write_good_claude_md() {
  cat > "$1/CLAUDE.md" <<'EOF'
## Environment

**Build.** none
**Typecheck.** none
**Lint.** none
**Tests.** none
**Single test file.** none
**Dev server.** none
**E2E.** none
**Runtime.** none
**Phase check.** none

**bootstrap.** none
**link.** none
EOF
}

write_claude_md_missing_link() {
  cat > "$1/CLAUDE.md" <<'EOF'
## Environment

**bootstrap.** none
EOF
}

write_claude_md_missing_phase_check() {
  cat > "$1/CLAUDE.md" <<'EOF'
## Environment

**bootstrap.** none
**link.** none
EOF
}

# run_preflight REPO [ARGS...] — sets $out and $rc in the caller. Called as a
# plain statement, never wrapped in $(...): $rc has to survive the call, and
# wrapping the call itself in command substitution would fork a subshell that
# loses it (test/cli/parallel-contract.test.sh's run_to_file hit the same
# thing; the fix there is the same one applied here).
run_preflight() {
  local repo="$1"
  shift
  out=$(cd "$repo" && "$script" "$@" 2>&1)
  rc=$?
}

# --- on main (the default), CLAUDE.md present -> default-branch finding, exit 1

repo1=$(gitfixture_new)
write_good_claude_md "$repo1"
run_preflight "$repo1"

assert_contains "$out" "on the default branch (main)" \
  "the default-branch finding should name main" || fail "default-branch finding missing"
[ "$rc" -eq 1 ] || fail "default-branch case should exit 1"

# --- non-default branch, clean tree, tracked .gitignore, full CLAUDE.md
# -> preflight clean, exit 0
#
# The .gitignore has to be committed for this to be the clean case at all: a
# fixture without one leaves preflight creating it, and an untracked .gitignore
# is a finding of its own, tested further down.

repo2=$(gitfixture_new)
gitfixture_branch "$repo2" work
gitfixture_gitignore "$repo2"
write_good_claude_md "$repo2"
run_preflight "$repo2"

assert_contains "$out" "preflight clean" \
  "a clean fixture should report preflight clean" || fail "not reported clean"
[ "$rc" -eq 0 ] || fail "clean case should exit 0"

# --- gitfixture_dirty -> the uncommitted-changes finding names 1 staged, 1 unstaged

repo3=$(gitfixture_new)
gitfixture_dirty "$repo3"
run_preflight "$repo3"

assert_contains "$out" "uncommitted changes (1 staged, 1 unstaged)" \
  "the dirty-tree finding should name one staged and one unstaged path" \
  || fail "uncommitted-changes finding missing"

# --- no .gitignore -> it is created with exactly .ai-workflow, fixed: line printed

repo4=$(gitfixture_new)
gitfixture_branch "$repo4" work
write_good_claude_md "$repo4"
[ ! -f "$repo4/.gitignore" ] || fail "test setup: fixture should start without a .gitignore"
run_preflight "$repo4"

assert_contains "$out" "fixed: added '.ai-workflow' to .gitignore" \
  "the fixed: line should be printed" || fail "fixed line missing"
[ -f "$repo4/.gitignore" ] || fail "gitignore should have been created"
gi_content=$(cat "$repo4/.gitignore")
assert_eq ".ai-workflow" "$gi_content" \
  "the .gitignore line must be .ai-workflow with no trailing slash" \
  || fail "gitignore content mismatch"

# --- CLAUDE.md missing **link** -> that finding fires, **bootstrap** does not

repo5=$(gitfixture_new)
gitfixture_branch "$repo5" work
write_claude_md_missing_link "$repo5"
run_preflight "$repo5"

assert_contains "$out" "no 'link' field in CLAUDE.md" \
  "the missing-link finding should fire" || fail "link finding missing"
! printf '%s' "$out" | grep -qF "no 'bootstrap' field" \
  || fail "bootstrap finding should not fire when bootstrap is present"

# --- phase check TC-2: CLAUDE.md missing 'Phase check' -> that finding fires,
# naming the one command a phase runs on its own work ------------------------
#
# Labelled "phase check TC-n" to avoid the bare TC-n token: this file already
# numbers its own cases TC-1, TC-2 and TC-4 through TC-8 (see judge TC-n's own
# comment further down for the same reasoning). The clean half of this case —
# a CLAUDE.md carrying bootstrap, link and Phase check together — is the
# write_good_claude_md() fixture already exercised by repo2's clean case above.

repo5b=$(gitfixture_new)
gitfixture_branch "$repo5b" work
write_claude_md_missing_phase_check "$repo5b"
run_preflight "$repo5b"

assert_contains "$out" "no 'Phase check' field in CLAUDE.md" \
  "phase check TC-2: the missing-Phase-check finding should fire" \
  || fail "phase check TC-2: Phase check finding missing"
! printf '%s' "$out" | grep -qF "no 'bootstrap' field" \
  || fail "phase check TC-2: bootstrap finding should not fire when bootstrap is present"
! printf '%s' "$out" | grep -qF "no 'link' field" \
  || fail "phase check TC-2: link finding should not fire when link is present"

# --- outside any repository -> exit 2, not a git repository

bare=$(mktemp_dir)
run_preflight "$bare"

[ "$rc" -eq 2 ] || fail "outside a repository should exit 2"
assert_contains "$out" "not a git repository" \
  "the not-a-git-repository message should be printed" || fail "message missing"

# --- a plan path that does not exist -> the no such plan file finding

repo7=$(gitfixture_new)
gitfixture_branch "$repo7" work
write_good_claude_md "$repo7"
missing_plan="$repo7/does-not-exist.md"
[ ! -f "$missing_plan" ] || fail "test setup: plan path should not exist"
run_preflight "$repo7" "$missing_plan"

assert_contains "$out" "no such plan file: $missing_plan" \
  "the missing-plan finding should name the path" || fail "missing-plan finding missing"

# --- a .gitignore preflight had to create is untracked -> that is a finding
#
# The fixture starts with no .gitignore at all, so the block above creates one
# and leaves it untracked. Left unsaid, the run commits it on the branch and
# integration then collides with the untracked copy in the main checkout — and
# git reports that as a refused checkout, which reads like the base has moved.

repo8=$(gitfixture_new)
gitfixture_branch "$repo8" work
write_good_claude_md "$repo8"
run_preflight "$repo8"

assert_contains "$out" ".gitignore is not tracked" \
  "an untracked .gitignore should be a finding" || fail "untracked-gitignore finding missing"

# ...and once it is committed, the finding is gone.

git -C "$repo8" add .gitignore >/dev/null 2>&1
git -C "$repo8" commit -q -m "chore: ignore .ai-workflow"
run_preflight "$repo8"

! printf '%s' "$out" | grep -qF ".gitignore is not tracked" \
  || fail "a tracked .gitignore must not raise the finding"

# --- --parallel: disjoint write-sets -> exit 0, the group may run ----------
#
# No repository: --parallel reads a plan and nothing else, and is answered
# before the run's own checks are reached.

wsplan="$repo_root/test/fixtures/plan-writesets.md"

out=$("$script" --parallel "$wsplan" 2 3 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "disjoint write-sets should exit 0"
assert_contains "$out" "write-sets disjoint" \
  "disjoint write-sets should say so" || fail "disjoint message missing"

# --- a path inside a fenced block is an example, never a write -------------

out=$("$script" --parallel "$wsplan" 1 3 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "phases 1 and 3 should be disjoint"
! printf '%s' "$out" | grep -qF "src/fenced/never-a-write.ts" \
  || fail "a path inside a fenced block must not be read as a write"

# --- --parallel: intersecting write-sets -> exit 1, naming the shared path --

out=$("$script" --parallel "$wsplan" 2 4 2>&1); rc=$?
[ "$rc" -eq 1 ] || fail "intersecting write-sets should exit 1"
assert_contains "$out" "intersect: phases 2 and phases 4 both write" \
  "the intersection should name both sides" || fail "intersect line missing"
assert_contains "$out" "src/api/client.ts" \
  "the intersection should name the shared path" || fail "shared path not named"

# --- one clash in a group of three is still a refusal ----------------------

out=$("$script" --parallel "$wsplan" 2 3 4 2>&1); rc=$?
[ "$rc" -eq 1 ] || fail "one clash among three ranges should still exit 1"

# --- every path on a bullet counts, not only the first --------------------
#
# A *Changes* bullet may name more than one path. Reading only the first makes
# the check fail OPEN: it reports a group safe to run in parallel while two of
# its phases write the same file. Phase 5 names its colliding path second.

out=$("$script" --parallel "$wsplan" 3 5 2>&1); rc=$?
[ "$rc" -eq 1 ] || fail "a collision on a bullet's second path should exit 1"
assert_contains "$out" "src/ui/UserCard.tsx" \
  "the second path on the bullet should be named" || fail "second path not read"

# --- ...and nothing after the bullet's em-dash is a path ------------------
#
# The tail is prose about the paths, and it carries backticks of its own —
# phase 5's tail names phase 1's `src/shared/contract.ts`. Reading the tail
# would invent a collision out of a sentence.

out=$("$script" --parallel "$wsplan" 1 5 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "a path named in a bullet's prose must not be a write"

# --- an intersection is found whatever the ambient locale ------------------
#
# changes_paths sorts LC_ALL=C; comm must compare the same way. Left in the
# ambient locale, comm on a UTF-8 system decides C-sorted input is unsorted and
# silently prints nothing — so an intersecting pair is reported as disjoint,
# exit 0. That is a check failing open, and the group it should have stopped
# gets dispatched.
#
# The collision alone does not reproduce it, and neither does any punctuation:
# a Changes field of ordinary paths sorts identically either way, which is why
# the cases above pass with the bug present. What the two collations actually
# disagree about is CASE. In C every capital sorts before every lowercase, so
# `Segment` precedes `docs/shared.md`; under a UTF-8 locale case is secondary,
# so `docs/...` comes first. comm walks the C-sorted files expecting the other
# order, steps past the shared path, and finishes having matched nothing.
#
# A bare capitalised word in a Changes field is not contrived — this plan's own
# phase 4 carried `Segment` in exactly that position.

locale_dir=$(mktemp -d)
locale_plan="$locale_dir/plan.md"
cat > "$locale_plan" <<'PLAN'
# A plan whose Changes fields carry more than paths

## Phases

### Phase 1. The one that also names a heading and a bare word

**Changes**
- `## Ledger` — a heading, not a path
- `Segment` — a capitalised bare word, not a path
- `docs/shared.md` — the real write

### Phase 2. The one that writes the same file

**Changes**
- `docs/shared.md` — the same real write
- `src/other.ts` — its own
PLAN

out=$("$script" --parallel "$locale_plan" 1 2 2>&1); rc=$?
[ "$rc" -eq 1 ] \
  || fail "an intersection must be found whatever the locale, got exit $rc: $out"
assert_contains "$out" "docs/shared.md" \
  "the shared path should be named" || fail "shared path not named"
! printf '%s' "$out" | grep -qF "write-sets disjoint" \
  || fail "intersecting write-sets must never be reported as disjoint"

rm -rf "$locale_dir"

# --- --parallel needs at least two ranges, and rejects a bad one -----------

out=$("$script" --parallel "$wsplan" 2 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "--parallel with one range should exit 2"

out=$("$script" --parallel "$wsplan" 2 abc 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "--parallel with a bad range should exit 2"
assert_contains "$out" "bad RANGE: abc" \
  "a bad range should be named" || fail "bad-range message missing"

# --- TC-20: a wrapped bullet's continuation prose is not a declared path ---
#
# given: test/fixtures/plan-writesets.md's sixth phase — one real path on the
# bullet's head, and phase 2's src/api/client.ts named in the prose on the
# continuation line. when: --parallel <fixture> 2 6 runs. then: exit 0,
# "phases 6: 1 path(s)" listing only phase 6's own path, and no intersect:
# line — a backticked token in a bullet's prose is not a declared path,
# wherever the bullet happens to wrap.

out=$("$script" --parallel "$wsplan" 2 6 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "TC-20: a wrapped bullet's prose path must not invent a collision, got $rc: $out"
assert_contains "$out" "phases 6: 1 path(s)" \
  "TC-20: phase 6 should declare exactly its own one path" || fail "TC-20: path count wrong, got: $out"
! printf '%s' "$out" | grep -qF "intersect:" \
  || fail "TC-20: a backticked token in a bullet's prose must not be read as a declared path"

# --- --attribution: a branch checked against its own phase's declared paths -
#
# --attribution does not exist yet — every case below is RED until it is
# wired. Labelled "attribution TC-n" throughout, because this file already
# numbers its own cases TC-4 through TC-8 for plan-check and for brief and
# dispatch's CLI contract, and the bare TC-n token is per-file, not per-plan
# (the same reasoning judge TC-n uses further down this file).
#
# Every case here builds its own throwaway repository and its own minimal
# plan — a '## Phases' section with one phase's '**Changes**' field, nothing
# else — since --attribution reads only that field and needs no other, the
# same minimal shape the locale fixture above already uses.

# attribution TC-7: an exact match -> exit 0, attribution clean ------------
#
# given: a plan whose phase 2 declares two paths, and a branch off a base
# that wrote exactly those two. when: preflight --attribution <plan> 2
# <base> <branch> runs. then: exit 0 and "attribution clean".

repo_attr7=$(gitfixture_new)
base_attr7=$(git -C "$repo_attr7" rev-parse HEAD)
plan_attr7="$repo_attr7/attribution-plan.md"
cat > "$plan_attr7" <<'EOF'
## Phases

### Phase 2. Two declared paths

**Changes**
- `src/one.ts` — first
- `src/two.ts` — second
EOF

gitfixture_branch "$repo_attr7" attr-exact
mkdir -p "$repo_attr7/src"
printf 'one\n' > "$repo_attr7/src/one.ts"
printf 'two\n' > "$repo_attr7/src/two.ts"
git -C "$repo_attr7" add src/one.ts src/two.ts
git -C "$repo_attr7" commit -q -m "feat: write exactly what phase 2 declared"

run_preflight "$repo_attr7" --attribution "$plan_attr7" 2 "$base_attr7" attr-exact
[ "$rc" -eq 0 ] || fail "attribution TC-7: an exact match should exit 0, got $rc: $out"
assert_contains "$out" "attribution clean" \
  "attribution TC-7: an exact match should report attribution clean" || fail "attribution TC-7: clean line missing, got: $out"

# attribution TC-8: an undeclared write -> exit 1, naming that path alone ---
#
# given: the same plan, and a branch that also wrote a third path phase 2
# does not declare. when: the same command runs. then: exit 1 and "outside
# its declaration:" naming that path and no other. The exit code alone does
# not satisfy this case: today's unwired --attribution already exits 1, for
# an unrelated reason (it falls through to the plan-file finding), so a case
# that checks only the code would pass against a command that does not
# exist.

repo_attr8=$(gitfixture_new)
base_attr8=$(git -C "$repo_attr8" rev-parse HEAD)
plan_attr8="$repo_attr8/attribution-plan.md"
cat > "$plan_attr8" <<'EOF'
## Phases

### Phase 2. Two declared paths

**Changes**
- `src/one.ts` — first
- `src/two.ts` — second
EOF

gitfixture_branch "$repo_attr8" attr-extra
mkdir -p "$repo_attr8/src"
printf 'one\n' > "$repo_attr8/src/one.ts"
printf 'two\n' > "$repo_attr8/src/two.ts"
printf 'extra\n' > "$repo_attr8/src/extra.ts"
git -C "$repo_attr8" add src/one.ts src/two.ts src/extra.ts
git -C "$repo_attr8" commit -q -m "feat: write a third, undeclared path"

run_preflight "$repo_attr8" --attribution "$plan_attr8" 2 "$base_attr8" attr-extra
[ "$rc" -eq 1 ] || fail "attribution TC-8: an undeclared write should exit 1, got $rc: $out"
outside_section=$(printf '%s\n' "$out" | sed -n '/^outside its declaration:$/,$p')
assert_contains "$outside_section" "src/extra.ts" \
  "attribution TC-8: the outside-declaration section should name src/extra.ts" \
  || fail "attribution TC-8: extra path not named, got: $out"
# Only the indented path lines count here — the PLAN_CONFLICT line on
# stderr, captured too since run_preflight merges both streams, comes after
# this section and is not one of the paths it names.
extra_lines=$(printf '%s\n' "$outside_section" | grep -cE '^  ')
[ "$extra_lines" -eq 1 ] \
  || fail "attribution TC-8: outside its declaration: should name that path and no other, got: $outside_section"

# attribution TC-9: a declared path left unwritten -> a note, not a refusal -
#
# given: a branch that wrote only one of phase 2's two declared paths. when:
# the same command runs. then: exit 0, and "declared but not written:"
# names the other.

repo_attr9=$(gitfixture_new)
base_attr9=$(git -C "$repo_attr9" rev-parse HEAD)
plan_attr9="$repo_attr9/attribution-plan.md"
cat > "$plan_attr9" <<'EOF'
## Phases

### Phase 2. Two declared paths

**Changes**
- `src/one.ts` — first
- `src/two.ts` — second
EOF

gitfixture_branch "$repo_attr9" attr-partial
mkdir -p "$repo_attr9/src"
printf 'one\n' > "$repo_attr9/src/one.ts"
git -C "$repo_attr9" add src/one.ts
git -C "$repo_attr9" commit -q -m "feat: write only one of the two declared paths"

run_preflight "$repo_attr9" --attribution "$plan_attr9" 2 "$base_attr9" attr-partial
[ "$rc" -eq 0 ] || fail "attribution TC-9: a declared-but-unwritten path should not refuse, got $rc: $out"
assert_contains "$out" "declared but not written:" \
  "attribution TC-9: the not-written note should be printed" || fail "attribution TC-9: note missing, got: $out"
assert_contains "$out" "src/two.ts" \
  "attribution TC-9: the not-written note should name src/two.ts" || fail "attribution TC-9: path not named, got: $out"

# attribution TC-10: bad arguments -> exit 2 --------------------------------
#
# given: the same repository. when: --attribution is given the wrong number
# of arguments, a malformed range, or a ref git cannot resolve. then: exit 2
# in every case.

out=$(cd "$repo_attr9" && "$script" --attribution "$plan_attr9" 2 "$base_attr9" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "attribution TC-10: too few arguments should exit 2, got $rc: $out"

out=$(cd "$repo_attr9" && "$script" --attribution "$plan_attr9" abc "$base_attr9" attr-partial 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "attribution TC-10: a malformed range should exit 2, got $rc: $out"

out=$(cd "$repo_attr9" && "$script" --attribution "$plan_attr9" 2 "$base_attr9" no-such-ref-xyz 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "attribution TC-10: a ref git cannot resolve should exit 2, got $rc: $out"

# --- worker: a worker's own worktree, given and taken back ------------------
#
# worker does not exist yet — every case below is RED until it is wired.
# Labelled "worker TC-n" throughout, matching this file's own precedent for a
# shared TC-n namespace (attribution TC-n, judge TC-n further down).
#
# worker add writes its worktree to a path *outside* the fixture repository —
# <fixture>/../<fixture-basename>-work/... — a sibling gitfixture_new's own
# EXIT-trap cleanup does not reach, since that trap only removes the fixture
# directory itself. Every case below registers that sibling for cleanup as
# soon as it knows the fixture's path, before calling worker, so a case that
# fails partway through still leaves nothing behind. This chains onto
# harness.sh's own EXIT trap rather than replacing it.

worker_script="$repo_root/skills/implement/scripts/worker"

_worker_work_roots=()
_worker_cleanup() {
  local d
  for d in "${_worker_work_roots[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
  _harness_cleanup
}
trap _worker_cleanup EXIT

register_worker_cleanup() {
  local repo="$1"
  _worker_work_roots+=("$(dirname "$repo")/$(basename "$repo")-work")
}

# worker TC-1: worker add creates a worktree and branch, prints five lines ---
#
# given: a repository with a plan and a committed base. when: worker add
# <plan> 3 <base> runs. then: a worktree exists at the printed path on branch
# run/<slug>/3-3, its HEAD is the base, .ai-workflow inside it resolves to
# the main checkout's, and the five contract lines are printed.

repo_w1=$(gitfixture_new)
register_worker_cleanup "$repo_w1"
write_good_claude_md "$repo_w1"
mkdir -p "$repo_w1/.ai-workflow"
printf 'marker\n' > "$repo_w1/.ai-workflow/marker.txt"
base_w1=$(git -C "$repo_w1" rev-parse HEAD)
plan_w1="$repo_w1/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w1"
slug_w1=$(basename "$plan_w1" .md)

out=$(cd "$repo_w1" && "$worker_script" add "$plan_w1" 3 "$base_w1" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-1: worker add should exit 0, got $rc: $out"
out_w1="$out"

wt_path_w1=$(printf '%s\n' "$out_w1" | sed -n 's/^worktree: //p')
[ -n "$wt_path_w1" ] || fail "worker TC-1: no 'worktree:' line in output: $out_w1"
[ -d "$wt_path_w1" ] || fail "worker TC-1: printed worktree path does not exist: $wt_path_w1"

assert_contains "$out_w1" "branch: run/${slug_w1}/3-3" \
  "worker TC-1: the branch line should name run/<slug>/3-3" || fail "worker TC-1: branch line wrong, got: $out_w1"
assert_contains "$out_w1" "base: $base_w1" \
  "worker TC-1: the base line should carry the full base sha" || fail "worker TC-1: base line wrong, got: $out_w1"

head_w1=$(git -C "$wt_path_w1" rev-parse HEAD)
[ "$head_w1" = "$base_w1" ] || fail "worker TC-1: the worktree's HEAD should equal base, got $head_w1 want $base_w1"

[ -L "$wt_path_w1/.ai-workflow" ] || fail "worker TC-1: .ai-workflow inside the worktree should be a symlink"
marker_w1=$(cat "$wt_path_w1/.ai-workflow/marker.txt" 2>/dev/null || true)
[ "$marker_w1" = "marker" ] || fail "worker TC-1: .ai-workflow inside the worktree should resolve to the main checkout's — the marker file is not visible through it"

assert_contains "$out_w1" "bootstrap: none" \
  "worker TC-1: the bootstrap line should carry the CLAUDE.md value" || fail "worker TC-1: bootstrap line wrong, got: $out_w1"
assert_contains "$out_w1" "link: none" \
  "worker TC-1: the link line should carry the CLAUDE.md value" || fail "worker TC-1: link line wrong, got: $out_w1"

lines_w1=$(printf '%s\n' "$out_w1" | wc -l | tr -d ' ')
[ "$lines_w1" -eq 5 ] || fail "worker TC-1: stdout should be exactly five lines, got $lines_w1: $out_w1"

# worker TC-2: a repeated worker add is a no-op, not a failure --------------
#
# given: worker add has already run for that plan and range (worker TC-1's).
# when: it runs again with the same arguments. then: exit 0 and the same
# five lines — a resume is a no-op, not a failure.

out=$(cd "$repo_w1" && "$worker_script" add "$plan_w1" 3 "$base_w1" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-2: a repeated worker add should exit 0, got $rc: $out"
[ "$out" = "$out_w1" ] || fail "worker TC-2: a repeated worker add should print the same five lines, got: $out"

# worker TC-3: a bad plan, range or base each exit 2, and nothing is created

repo_w3=$(gitfixture_new)
register_worker_cleanup "$repo_w3"
base_w3=$(git -C "$repo_w3" rev-parse HEAD)
plan_w3="$repo_w3/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w3"

out=$(cd "$repo_w3" && "$worker_script" add "$repo_w3/no-such-plan.md" 3 "$base_w3" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "worker TC-3: a missing plan file should exit 2, got $rc: $out"
assert_contains "$out" "no such plan file" \
  "worker TC-3: the message should name the missing plan" || fail "worker TC-3: plan message missing, got: $out"

out=$(cd "$repo_w3" && "$worker_script" add "$plan_w3" abc "$base_w3" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "worker TC-3: a malformed range should exit 2, got $rc: $out"
assert_contains "$out" "bad RANGE: abc" \
  "worker TC-3: the message should name the bad range" || fail "worker TC-3: range message missing, got: $out"

out=$(cd "$repo_w3" && "$worker_script" add "$plan_w3" 3 no-such-base-xyz 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "worker TC-3: an unresolvable base should exit 2, got $rc: $out"
assert_contains "$out" "bad BASE: no-such-base-xyz" \
  "worker TC-3: the message should name the bad base" || fail "worker TC-3: base message missing, got: $out"

[ ! -d "$(dirname "$repo_w3")/$(basename "$repo_w3")-work" ] \
  || fail "worker TC-3: nothing should have been created for a failing worker add"

# worker TC-4: the contract's bootstrap/link values, or their fallback ------
#
# given: a CLAUDE.md carrying **bootstrap.** and **link.**, and a second
# repository carrying neither. when: worker add runs in each. then: the
# first prints those values, the second prints '(not in the contract)' for
# both, and neither refuses.

repo_w4a=$(gitfixture_new)
register_worker_cleanup "$repo_w4a"
write_good_claude_md "$repo_w4a"
base_w4a=$(git -C "$repo_w4a" rev-parse HEAD)
plan_w4a="$repo_w4a/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w4a"

out=$(cd "$repo_w4a" && "$worker_script" add "$plan_w4a" 3 "$base_w4a" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-4: a CLAUDE.md carrying bootstrap/link should not refuse, got $rc: $out"
assert_contains "$out" "bootstrap: none" \
  "worker TC-4: the bootstrap line should carry the CLAUDE.md value" || fail "worker TC-4: bootstrap value wrong, got: $out"
assert_contains "$out" "link: none" \
  "worker TC-4: the link line should carry the CLAUDE.md value" || fail "worker TC-4: link value wrong, got: $out"

repo_w4b=$(gitfixture_new)
register_worker_cleanup "$repo_w4b"
base_w4b=$(git -C "$repo_w4b" rev-parse HEAD)
plan_w4b="$repo_w4b/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w4b"

out=$(cd "$repo_w4b" && "$worker_script" add "$plan_w4b" 3 "$base_w4b" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-4: a repository with no CLAUDE.md should not refuse, got $rc: $out"
assert_contains "$out" "bootstrap: (not in the contract)" \
  "worker TC-4: no CLAUDE.md should print the fallback for bootstrap" || fail "worker TC-4: bootstrap fallback wrong, got: $out"
assert_contains "$out" "link: (not in the contract)" \
  "worker TC-4: no CLAUDE.md should print the fallback for link" || fail "worker TC-4: link fallback wrong, got: $out"

# worker TC-5: worker rm gives the worktree back and keeps the branch -------
#
# given: a worker worktree created by worker add, clean. when: worker rm
# <plan> 3 runs. then: the worktree is gone, the branch still exists, exit
# 0; running it a second time is also exit 0.

repo_w5=$(gitfixture_new)
register_worker_cleanup "$repo_w5"
write_good_claude_md "$repo_w5"
gitfixture_gitignore "$repo_w5"
base_w5=$(git -C "$repo_w5" rev-parse HEAD)
plan_w5="$repo_w5/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w5"
slug_w5=$(basename "$plan_w5" .md)

out=$(cd "$repo_w5" && "$worker_script" add "$plan_w5" 3 "$base_w5" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-5 setup: worker add should exit 0, got $rc: $out"
wt_path_w5=$(printf '%s\n' "$out" | sed -n 's/^worktree: //p')
[ -d "$wt_path_w5" ] || fail "worker TC-5 setup: worktree not created at $wt_path_w5"

out=$(cd "$repo_w5" && "$worker_script" rm "$plan_w5" 3 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-5: worker rm on a clean worktree should exit 0, got $rc: $out"
assert_contains "$out" "removed: $wt_path_w5" \
  "worker TC-5: the removed line should name the worktree path" || fail "worker TC-5: removed line wrong, got: $out"
[ ! -d "$wt_path_w5" ] || fail "worker TC-5: the worktree directory should be gone"
git -C "$repo_w5" show-ref --verify --quiet "refs/heads/run/${slug_w5}/3-3" \
  || fail "worker TC-5: the branch run/${slug_w5}/3-3 should still exist"

out=$(cd "$repo_w5" && "$worker_script" rm "$plan_w5" 3 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-5: a repeated worker rm should also exit 0, got $rc: $out"
assert_contains "$out" "no worktree: $wt_path_w5" \
  "worker TC-5: the second rm should say there is nothing to remove" || fail "worker TC-5: no-worktree line wrong, got: $out"

# worker TC-6: worker rm refuses a dirty worktree, and names what is dirty --
#
# given: a worker worktree with an uncommitted change in it. when: worker rm
# runs. then: exit 1, the worktree is still there, and the message says what
# is uncommitted — it is never forced. A plain 'git worktree remove' already
# refuses a dirty tree on its own, so the exit code alone proves nothing here;
# what worker has to add, and what this asserts, is the file name in the
# message.

repo_w6=$(gitfixture_new)
register_worker_cleanup "$repo_w6"
write_good_claude_md "$repo_w6"
gitfixture_gitignore "$repo_w6"
base_w6=$(git -C "$repo_w6" rev-parse HEAD)
plan_w6="$repo_w6/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w6"

out=$(cd "$repo_w6" && "$worker_script" add "$plan_w6" 3 "$base_w6" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-6 setup: worker add should exit 0, got $rc: $out"
wt_path_w6=$(printf '%s\n' "$out" | sed -n 's/^worktree: //p')
[ -d "$wt_path_w6" ] || fail "worker TC-6 setup: worktree not created at $wt_path_w6"

printf 'dirty\n' >> "$wt_path_w6/README.md"

out=$(cd "$repo_w6" && "$worker_script" rm "$plan_w6" 3 2>&1); rc=$?
[ "$rc" -eq 1 ] || fail "worker TC-6: worker rm on a dirty worktree should exit 1, got $rc: $out"
[ -d "$wt_path_w6" ] || fail "worker TC-6: worker rm must never force-remove a dirty worktree"
assert_contains "$out" "README.md" \
  "worker TC-6: the message should name the uncommitted file, not just refuse" || fail "worker TC-6: uncommitted file not named, got: $out"

# tester TC-3: worker add PLAN RANGE BASE --tests gets its own worktree ----
#
# given: a repository with a plan and a committed base. when: worker add
# <plan> 1-8 <base> --tests runs. then: a worktree exists at
# <work_root>/<slug>/tests-1-8 on branch run/<slug>/tests-1-8, its HEAD is
# the base, .ai-workflow inside it resolves to the main checkout's, and the
# same five contract lines are printed.

repo_t3=$(gitfixture_new)
register_worker_cleanup "$repo_t3"
write_good_claude_md "$repo_t3"
gitfixture_gitignore "$repo_t3"
mkdir -p "$repo_t3/.ai-workflow"
printf 'marker\n' > "$repo_t3/.ai-workflow/marker.txt"
base_t3=$(git -C "$repo_t3" rev-parse HEAD)
plan_t3="$repo_t3/tester-plan.md"
printf '# Tester fixture plan\n' > "$plan_t3"
slug_t3=$(basename "$plan_t3" .md)

out=$(cd "$repo_t3" && "$worker_script" add "$plan_t3" 1-8 "$base_t3" --tests 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "tester TC-3: worker add --tests should exit 0, got $rc: $out"
out_t3="$out"

wt_path_t3=$(printf '%s\n' "$out_t3" | sed -n 's/^worktree: //p')
[ -n "$wt_path_t3" ] || fail "tester TC-3: no 'worktree:' line in output: $out_t3"
[ -d "$wt_path_t3" ] || fail "tester TC-3: printed worktree path does not exist: $wt_path_t3"
case "$wt_path_t3" in
  */"$slug_t3"/tests-1-8) : ;;
  *) fail "tester TC-3: worktree path should end in $slug_t3/tests-1-8, got: $wt_path_t3" ;;
esac

assert_contains "$out_t3" "branch: run/${slug_t3}/tests-1-8" \
  "tester TC-3: the branch line should name run/<slug>/tests-1-8" || fail "tester TC-3: branch line wrong, got: $out_t3"
assert_contains "$out_t3" "base: $base_t3" \
  "tester TC-3: the base line should carry the full base sha" || fail "tester TC-3: base line wrong, got: $out_t3"

head_t3=$(git -C "$wt_path_t3" rev-parse HEAD)
[ "$head_t3" = "$base_t3" ] || fail "tester TC-3: the worktree's HEAD should equal base, got $head_t3 want $base_t3"

[ -L "$wt_path_t3/.ai-workflow" ] || fail "tester TC-3: .ai-workflow inside the worktree should be a symlink"
marker_t3=$(cat "$wt_path_t3/.ai-workflow/marker.txt" 2>/dev/null || true)
[ "$marker_t3" = "marker" ] || fail "tester TC-3: .ai-workflow inside the worktree should resolve to the main checkout's — the marker file is not visible through it"

assert_contains "$out_t3" "bootstrap: none" \
  "tester TC-3: the bootstrap line should carry the CLAUDE.md value" || fail "tester TC-3: bootstrap line wrong, got: $out_t3"
assert_contains "$out_t3" "link: none" \
  "tester TC-3: the link line should carry the CLAUDE.md value" || fail "tester TC-3: link line wrong, got: $out_t3"

lines_t3=$(printf '%s\n' "$out_t3" | wc -l | tr -d ' ')
[ "$lines_t3" -eq 5 ] || fail "tester TC-3: stdout should be exactly five lines, got $lines_t3: $out_t3"

# tester TC-4: a repeated add --tests is a no-op; rm --tests gives it back --
#
# given: a tester worktree created by tester TC-3. when: worker add ...
# --tests runs again with the same arguments, then worker rm <plan> 1-8
# --tests. then: the second add is exit 0 with the same five lines; the rm
# removes the worktree, leaves the branch, exit 0; a second rm is also exit 0.

out=$(cd "$repo_t3" && "$worker_script" add "$plan_t3" 1-8 "$base_t3" --tests 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "tester TC-4: a repeated worker add --tests should exit 0, got $rc: $out"
[ "$out" = "$out_t3" ] || fail "tester TC-4: a repeated worker add --tests should print the same five lines, got: $out"

out=$(cd "$repo_t3" && "$worker_script" rm "$plan_t3" 1-8 --tests 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "tester TC-4: worker rm --tests on a clean worktree should exit 0, got $rc: $out"
assert_contains "$out" "removed: $wt_path_t3" \
  "tester TC-4: the removed line should name the worktree path" || fail "tester TC-4: removed line wrong, got: $out"
[ ! -d "$wt_path_t3" ] || fail "tester TC-4: the worktree directory should be gone"
git -C "$repo_t3" show-ref --verify --quiet "refs/heads/run/${slug_t3}/tests-1-8" \
  || fail "tester TC-4: the branch run/${slug_t3}/tests-1-8 should still exist"

out=$(cd "$repo_t3" && "$worker_script" rm "$plan_t3" 1-8 --tests 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "tester TC-4: a repeated worker rm --tests should also exit 0, got $rc: $out"
assert_contains "$out" "no worktree: $wt_path_t3" \
  "tester TC-4: the second rm --tests should say there is nothing to remove" || fail "tester TC-4: no-worktree line wrong, got: $out"

# tester TC-5: a worker and a tester never collide; rm without the flag -----
# leaves the tester's worktree alone
#
# given: a repository with a plan and a committed base. when: worker add
# <plan> 1-8 <base> and worker add <plan> 1-8 <base> --tests both run.
# then: two different worktrees on two different branches, run/<slug>/1-8
# and run/<slug>/tests-1-8; neither call refuses the other, and worker rm
# <plan> 1-8 without the flag leaves the tester's worktree alone.

repo_t5=$(gitfixture_new)
register_worker_cleanup "$repo_t5"
write_good_claude_md "$repo_t5"
gitfixture_gitignore "$repo_t5"
base_t5=$(git -C "$repo_t5" rev-parse HEAD)
plan_t5="$repo_t5/tester-plan.md"
printf '# Tester fixture plan\n' > "$plan_t5"
slug_t5=$(basename "$plan_t5" .md)

out=$(cd "$repo_t5" && "$worker_script" add "$plan_t5" 1-8 "$base_t5" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "tester TC-5: worker add without --tests should exit 0, got $rc: $out"
wt_path_t5w=$(printf '%s\n' "$out" | sed -n 's/^worktree: //p')
[ -d "$wt_path_t5w" ] || fail "tester TC-5: worker's worktree not created at $wt_path_t5w"
assert_contains "$out" "branch: run/${slug_t5}/1-8" \
  "tester TC-5: the worker branch should be run/<slug>/1-8" || fail "tester TC-5: worker branch line wrong, got: $out"

out=$(cd "$repo_t5" && "$worker_script" add "$plan_t5" 1-8 "$base_t5" --tests 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "tester TC-5: worker add --tests should not be refused by the worker's own worktree, got $rc: $out"
wt_path_t5t=$(printf '%s\n' "$out" | sed -n 's/^worktree: //p')
[ -d "$wt_path_t5t" ] || fail "tester TC-5: tester's worktree not created at $wt_path_t5t"
assert_contains "$out" "branch: run/${slug_t5}/tests-1-8" \
  "tester TC-5: the tester branch should be run/<slug>/tests-1-8" || fail "tester TC-5: tester branch line wrong, got: $out"

[ "$wt_path_t5w" != "$wt_path_t5t" ] || fail "tester TC-5: the worker and tester worktrees should not share a path"

out=$(cd "$repo_t5" && "$worker_script" rm "$plan_t5" 1-8 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "tester TC-5: worker rm without --tests should exit 0, got $rc: $out"
[ ! -d "$wt_path_t5w" ] || fail "tester TC-5: the worker's worktree should be gone"
[ -d "$wt_path_t5t" ] || fail "tester TC-5: worker rm without --tests must leave the tester's worktree alone"

# --- TC-4: preflight surfaces a plan-check finding ("required" once wired) -
#
# given: a three-phase plan, '## Phases' present, phase 2 missing
# '**Frozen for later phases**' (the same shape as plan-check.test.sh's TC-2
# fixture, built again here rather than shared across files, matching this
# file's own idiom of a self-contained fixture per case).
# when: preflight <plan> is run.
# then: the missing field appears among preflight's findings, naming phase 2,
# and preflight exits 1.

repo_tc4=$(gitfixture_new)
gitfixture_branch "$repo_tc4" work
gitfixture_gitignore "$repo_tc4"
write_good_claude_md "$repo_tc4"

plan_tc4="$repo_tc4/plan.md"
cat > "$plan_tc4" <<'EOF'
# TC-4 fixture plan

## Phases

### Phase 1. First phase title

**Becomes true**
- tc4_phase_one_becomes_true

**Changes**
- `src/one.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc4_phase_one_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc4_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Verification**
- proved by: phase 3

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc4_phase_three_becomes_true

**Changes**
- `src/three.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- joins: phases 1-2
- cases: —

**Steps**
- [ ] step three
EOF

run_preflight "$repo_tc4" "$plan_tc4"
[ "$rc" -eq 1 ] || fail "TC-4: preflight on a plan missing a frozen field should exit 1, got $rc: $out"
printf '%s' "$out" | grep -qi 'phase 2' \
  || fail "TC-4: preflight's findings should name phase 2, got: $out"
assert_contains "$out" "Frozen for later phases" \
  "TC-4: preflight's findings should name the missing field" || fail "missing-field name absent"

# --- TC-5: a repairable plan-check fault is repaired, not raised as a finding
#
# given: the plan from TC-1 of plan-check.test.sh — repairable (missing only
# '## Phases'), nothing else wrong. when: preflight <plan> is run. then: the
# plan is repaired, preflight reports it under 'fixed:' alongside its own
# repairs, and raises no finding for it. This fixture is built on an
# otherwise-clean gitfixture repository (branch, tracked .gitignore, full
# CLAUDE.md) so that a passing case here also confirms preflight's own exit
# code — 0 — though the case itself only requires no finding for the
# repaired fault.

repo_tc5=$(gitfixture_new)
gitfixture_branch "$repo_tc5" work
gitfixture_gitignore "$repo_tc5"
write_good_claude_md "$repo_tc5"

plan_tc5="$repo_tc5/plan.md"
cat > "$plan_tc5" <<'EOF'
# TC-5 fixture plan

### Phase 1. First phase title

**Becomes true**
- tc5_phase_one_becomes_true

**Changes**
- `src/one.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc5_phase_one_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc5_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc5_phase_two_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc5_phase_three_becomes_true

**Changes**
- `src/three.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- joins: phases 1-2
- cases: —

**Steps**
- [ ] step three
EOF

! grep -qE '^##[ \t]+Phases[ \t]*$' "$plan_tc5" \
  || fail "TC-5 test setup: fixture must start with no '## Phases' line"

run_preflight "$repo_tc5" "$plan_tc5"
assert_contains "$out" "fixed:" "TC-5: preflight should report the repair under fixed:" \
  || fail "fixed: line missing"
assert_contains "$out" "## Phases" "TC-5: the fixed: line should name '## Phases'" \
  || fail "fixed: line doesn't name ## Phases"
! printf '%s\n' "$out" | grep -E '^[[:space:]]*-' | grep -qi 'phases' \
  || fail "TC-5: a repaired '## Phases' fault must not also be raised as a finding"
[ "$rc" -eq 0 ] || fail "TC-5: this fixture has nothing else wrong, so preflight should exit 0, got $rc: $out"
grep -qE '^##[ \t]+Phases[ \t]*$' "$plan_tc5" \
  || fail "TC-5: the plan on disk should now carry '## Phases'"

# --- TC-6, TC-7, TC-8: brief and dispatch's basic CLI contract --------------
#
# Neither brief nor dispatch has a CLI seam of its own — segment-brief and
# segment-dispatch never had one either, only test/unit/test_segment_dispatch.py
# for dispatch's pure core — and the plan authorises no new file for them, so
# their basic CLI behaviour is pinned here, in the file that already builds
# gitfixture repositories for every other skills/implement/scripts/* case.
#
# brief and dispatch do not exist yet (today: segment-brief, segment-dispatch)
# — every case below is RED until phase 3 renames them.

brief_script="$repo_root/skills/implement/scripts/brief"
dispatch_script="$repo_root/skills/implement/scripts/dispatch"

# write_topology_plan REPO — an eight-phase, well-formed plan: '## Phases',
# phases 1 through 8 contiguous with all seven fields, and a '## Topology'
# table with phase 1's frozen columns (no 'Segment' column) naming two rows,
# 1-3 and 4-8, each with a distinctive Implementer and Why marker so a
# dispatch file can be checked for carrying the right row's content.
write_topology_plan() {
  local repo="$1" n
  local out="$repo/plan.md"
  {
    echo "# Topology fixture plan"
    echo
    echo "## Phases"
    echo
    for n in 1 2 3 4 5 6 7 8; do
      echo "### Phase $n. Phase $n title"
      echo
      echo "**Becomes true**"
      echo "- phase ${n}_becomes_true"
      echo
      echo "**Changes**"
      echo "- \`src/phase${n}.ts\` — placeholder"
      echo
      echo "**Depends on**"
      echo "- —"
      echo
      echo "**How**"
      echo "- plain implementation"
      echo
      echo "**Do not touch**"
      echo "- —"
      echo
      echo "**Frozen for later phases**"
      echo "- —"
      echo
      echo "**Verification**"
      if [ "$n" -eq 8 ]; then
        echo "- joins: phases 1-7"
        echo "- cases: —"
      else
        echo "- proved by: phase 8"
      fi
      echo
      echo "**Steps**"
      echo "- [ ] step $n"
      echo
    done
    echo "## Topology"
    echo
    echo "| Phases | Implementer | Why the boundary is here |"
    echo "|---|---|---|"
    echo "| 1-3 | Sonnet | tc_why_marker_one_three |"
    echo "| 4-8 | Opus | tc_why_marker_four_eight |"
    echo
    echo "## Ledger"
    echo
    echo "- [ ] Tests written"
  } > "$out"
  echo "$out"
}

# --- TC-6: brief then dispatch name the range, not a segment ---------------
#
# given: a well-formed plan and a clean workspace. when: brief <plan> 1-3
# then dispatch <plan> 1-3 are run. then: the files written are
# brief-1-3.md, dispatch-1-3.md, and the dispatch names report-1-3.md as the
# report path. No file called segment-* is created.

repo_tc6=$(gitfixture_new)
plan_tc6=$(write_topology_plan "$repo_tc6")
ws_tc6="$repo_tc6/.ai-workflow/run/plan"

brief_out=$(cd "$repo_tc6" && "$brief_script" "$plan_tc6" 1-3 2>&1)
brief_rc=$?
[ "$brief_rc" -eq 0 ] || fail "TC-6: brief <plan> 1-3 should exit 0, got $brief_rc: $brief_out"

dispatch_out=$(cd "$repo_tc6" && "$dispatch_script" "$plan_tc6" 1-3 2>&1)
dispatch_rc=$?
[ "$dispatch_rc" -eq 0 ] || fail "TC-6: dispatch <plan> 1-3 should exit 0, got $dispatch_rc: $dispatch_out"

[ -f "$ws_tc6/brief-1-3.md" ] || fail "TC-6: expected $ws_tc6/brief-1-3.md, found: $(ls "$ws_tc6" 2>&1)"
[ -f "$ws_tc6/dispatch-1-3.md" ] || fail "TC-6: expected $ws_tc6/dispatch-1-3.md, found: $(ls "$ws_tc6" 2>&1)"
assert_contains "$(cat "$ws_tc6/dispatch-1-3.md")" "report-1-3.md" \
  "TC-6: the dispatch should name report-1-3.md as the report path" || fail "report path not named"
segment_files=$(find "$ws_tc6" -maxdepth 1 -name 'segment-*' 2>/dev/null)
[ -z "$segment_files" ] || fail "TC-6: no segment-* file should exist, found: $segment_files"

# --- TC-7: dispatch works with no 'Segment' column in the Topology table ----
#
# given: a plan whose '## Topology' table has the columns 'Phases |
# Implementer | Why the boundary is here' and no 'Segment' column (every
# fixture this file builds already has this shape — the frozen one). when:
# dispatch <plan> 1-3 is run. then: exit 0, and the dispatch carries the
# row's implementer and its reason.

repo_tc7=$(gitfixture_new)
plan_tc7=$(write_topology_plan "$repo_tc7")
ws_tc7="$repo_tc7/.ai-workflow/run/plan"

dispatch_out7=$(cd "$repo_tc7" && "$dispatch_script" "$plan_tc7" 1-3 2>&1)
dispatch_rc7=$?
[ "$dispatch_rc7" -eq 0 ] || fail "TC-7: dispatch on a Segment-less Topology table should exit 0, got $dispatch_rc7: $dispatch_out7"
dispatch_body7=$(cat "$ws_tc7/dispatch-1-3.md" 2>/dev/null)
assert_contains "$dispatch_body7" "Sonnet" \
  "TC-7: the dispatch should carry row 1-3's implementer (Sonnet)" || fail "implementer missing"
assert_contains "$dispatch_body7" "tc_why_marker_one_three" \
  "TC-7: the dispatch should carry row 1-3's reason" || fail "reason missing"

# --- TC-8: dispatch points at an earlier report already on disk ------------
#
# given: a workspace already holding report-1-3.md. when: dispatch <plan>
# 4-8 is run. then: the dispatch points at report-1-3.md as an earlier
# report, not at "no earlier report exists".

repo_tc8=$(gitfixture_new)
plan_tc8=$(write_topology_plan "$repo_tc8")
ws_tc8="$repo_tc8/.ai-workflow/run/plan"
mkdir -p "$ws_tc8"
printf '# a prior implementer report\n' > "$ws_tc8/report-1-3.md"

dispatch_out8=$(cd "$repo_tc8" && "$dispatch_script" "$plan_tc8" 4-8 2>&1)
dispatch_rc8=$?
[ "$dispatch_rc8" -eq 0 ] || fail "TC-8: dispatch <plan> 4-8 should exit 0, got $dispatch_rc8: $dispatch_out8"
dispatch_body8=$(cat "$ws_tc8/dispatch-4-8.md" 2>/dev/null)
assert_contains "$dispatch_body8" "report-1-3.md" \
  "TC-8: the dispatch should point at report-1-3.md" || fail "earlier report not named"
! printf '%s' "$dispatch_body8" | grep -qi 'no earlier report' \
  || fail "TC-8: the dispatch must not say no earlier report exists"


# --- judge TC-2 through judge TC-14: dispatch --judge's CLI contract --------
#
# dispatch --judge does not exist yet (phase 2 of the-judge.md builds it) —
# every case below is RED until then. Labelled "judge TC-n" throughout,
# section comments and fail messages alike, because this file already
# numbers its own cases TC-1, TC-2 and TC-4 through TC-8 and the bare TC-n
# token is per-file, not per-plan (measured at 2ff649a: grep -rhoE
# 'TC-[0-9]+' test/ already returns TC-1 through TC-12 across four files).

# --- judge TC-2: dispatch --judge derives the judge's dispatch when the
# RUN marker's base= line resolves ------------------------------------------
#
# given: a repository with a well-formed plan and a workspace RUN marker
# carrying a base= line — the base is the fixture's own initial commit, and
# the plan is committed on top of it, so HEAD sits ahead of base the way a
# finished run's does. when: dispatch <plan> --judge is run and its stdout
# is captured. then: exit 0; stdout is exactly two lines — 'wrote
# <workspace>/judge-dispatch.md: N hole(s) to fill', then 'cap origin:
# <sha>' where the sha equals git rev-parse HEAD; the file exists; its
# '## Cap origin' section names that same sha; its '## Review package'
# section names a file that exists; and no '<<< FILL' marker in the file
# asks for BASE.

repo_tc_j2=$(gitfixture_new)
base_tc_j2=$(git -C "$repo_tc_j2" rev-parse HEAD)
plan_tc_j2=$(write_topology_plan "$repo_tc_j2")
git -C "$repo_tc_j2" add plan.md
git -C "$repo_tc_j2" commit -q -m "docs: add plan"
head_tc_j2=$(git -C "$repo_tc_j2" rev-parse HEAD)
gitfixture_marker "$repo_tc_j2" "$plan_tc_j2" "$base_tc_j2" >/dev/null
ws_tc_j2="$repo_tc_j2/.ai-workflow/run/plan"
dispatch_file_j2="$ws_tc_j2/judge-dispatch.md"

out_j2=$(cd "$repo_tc_j2" && "$dispatch_script" "$plan_tc_j2" --judge)
rc_j2=$?
[ "$rc_j2" -eq 0 ] || fail "judge TC-2: dispatch <plan> --judge with a resolvable base should exit 0, got $rc_j2"

lines_j2=$(printf '%s\n' "$out_j2" | wc -l | tr -d ' ')
[ "$lines_j2" -eq 2 ] || fail "judge TC-2: dispatch --judge's stdout should be exactly two lines, got $lines_j2: $out_j2"

first_j2=$(printf '%s\n' "$out_j2" | sed -n '1p')
second_j2=$(printf '%s\n' "$out_j2" | sed -n '2p')

assert_contains "$first_j2" "wrote $dispatch_file_j2:" \
  "judge TC-2: stdout's first line should start with 'wrote $dispatch_file_j2:'" \
  || fail "judge TC-2: first stdout line wrong: $first_j2"
printf '%s' "$first_j2" | grep -qE ': [0-9]+ holes? to fill$' \
  || fail "judge TC-2: stdout's first line should end with ': N hole(s) to fill', got: $first_j2"

assert_eq "cap origin: $head_tc_j2" "$second_j2" \
  "judge TC-2: stdout's second line should be 'cap origin: <HEAD sha>'" \
  || fail "judge TC-2: cap origin line mismatch, got: $second_j2"

[ -f "$dispatch_file_j2" ] || fail "judge TC-2: expected $dispatch_file_j2 to exist"
content_j2=$(cat "$dispatch_file_j2")

section_cap_origin_j2=$(awk '/^## Cap origin$/{flag=1; next} /^## /{flag=0} flag' "$dispatch_file_j2")
assert_contains "$section_cap_origin_j2" "$head_tc_j2" \
  "judge TC-2: the ## Cap origin section should name $head_tc_j2" \
  || fail "judge TC-2: cap origin section mismatch, got: $section_cap_origin_j2"

# Checked before the review-path-exists assertions below on purpose: when a
# BASE hole survives, the ## Review package section has no .diff path to
# find at all, and that absence would otherwise fail first and mask this
# message. Phase 3 matches this exact fail string with grep -F over the
# whole run's output, so this must be the assertion that actually fires.
! printf '%s\n' "$content_j2" | grep -E '<<< FILL:.*>>>' | grep -qw 'BASE' \
  || fail "judge TC-2: no-BASE-hole assertion — a <<< FILL marker in judge-dispatch.md names BASE even though the RUN marker's base= line resolved"

section_review_pkg_j2=$(awk '/^## Review package$/{flag=1; next} /^## /{flag=0} flag' "$dispatch_file_j2")
review_path_j2=$(printf '%s\n' "$section_review_pkg_j2" | grep -oE '/[^[:space:]]+\.diff' | head -n1)
[ -n "$review_path_j2" ] || fail "judge TC-2: no file path found in the ## Review package section: $section_review_pkg_j2"
[ -e "$review_path_j2" ] || fail "judge TC-2: the ## Review package section names $review_path_j2, which does not exist"

# --- judge TC-3: every absolute path judge-dispatch.md names resolves ------
#
# given: the judge dispatch judge TC-2 produced. when: every absolute path
# it names — one per line, bullet marker optional, the idiom this script's
# own dispatch bodies already use for every path they embed — is tested
# with [ -e ]. then: all resolve, and the set includes agents/gate-a.md,
# agents/gate-b.md, agents/implementer.md, agents/judge.md, and the
# dispatch, brief and review-package scripts.
#
# One path is deliberately excluded from the [ -e ] sweep: judge/report.md,
# the judge's own report. It is a write target for rounds the judge has not
# run yet, not a path handed over to be read — build_gate_a_body's own
# '## Your report' field points at gate-a/report.md the same way, and that
# path does not exist at dispatch-generation time either.

paths_j3=$(sed -E 's/^[[:space:]]*-[[:space:]]*//' "$dispatch_file_j2" | grep -E '^/[^[:space:]]+$')
[ -n "$paths_j3" ] || fail "judge TC-3: no absolute paths found in judge-dispatch.md"

while IFS= read -r p_j3; do
  case "$p_j3" in
    */judge/report.md) continue ;;
  esac
  [ -e "$p_j3" ] || fail "judge TC-3: a path judge-dispatch.md names does not resolve: $p_j3"
done <<< "$paths_j3"

for want_j3 in "agents/gate-a.md" "agents/gate-b.md" "agents/implementer.md" "agents/judge.md" \
               "skills/implement/scripts/dispatch" "skills/implement/scripts/brief" \
               "skills/implement/scripts/review-package"; do
  printf '%s\n' "$paths_j3" | grep -qF "$want_j3" \
    || fail "judge TC-3: judge-dispatch.md should name $want_j3 among its absolute paths"
done

# --- judge TC-4: dispatch --judge with no RUN marker asks for BASE ---------
#
# given: a repository with a well-formed plan and no RUN marker at all.
# when: dispatch <plan> --judge is run. then: exit 0 — a missing marker is
# a dispatch built outside a run, not a failure; the '## Review package'
# section carries a <<< FILL marker asking for BASE; and the header's hole
# count includes it.

repo_tc_j4=$(gitfixture_new)
plan_tc_j4=$(write_topology_plan "$repo_tc_j4")
ws_tc_j4="$repo_tc_j4/.ai-workflow/run/plan"
[ ! -e "$ws_tc_j4/RUN" ] || fail "judge TC-4 test setup: fixture should start with no RUN marker"

out_j4=$(cd "$repo_tc_j4" && "$dispatch_script" "$plan_tc_j4" --judge)
rc_j4=$?
[ "$rc_j4" -eq 0 ] || fail "judge TC-4: dispatch <plan> --judge with no RUN marker should exit 0, got $rc_j4: $out_j4"

dispatch_file_j4="$ws_tc_j4/judge-dispatch.md"
[ -f "$dispatch_file_j4" ] || fail "judge TC-4: expected $dispatch_file_j4 to exist"
content_j4=$(cat "$dispatch_file_j4")

section_review_pkg_j4=$(awk '/^## Review package$/{flag=1; next} /^## /{flag=0} flag' "$dispatch_file_j4")
printf '%s\n' "$section_review_pkg_j4" | grep -qF '<<< FILL' \
  || fail "judge TC-4: the ## Review package section should carry a <<< FILL marker when no RUN marker exists, got: $section_review_pkg_j4"
printf '%s\n' "$section_review_pkg_j4" | grep -qw 'BASE' \
  || fail "judge TC-4: the <<< FILL marker in ## Review package should name BASE, got: $section_review_pkg_j4"

first_j4=$(printf '%s\n' "$out_j4" | sed -n '1p')
# Isolate the trailing ": N hole(s) to fill" before pulling the digits out —
# the workspace path earlier on this line can itself contain digits (a
# mktemp_dir suffix), and grabbing the first number in the whole line would
# read one of those instead of the actual count.
n_j4=$(printf '%s' "$first_j4" | grep -oE ': [0-9]+ holes? to fill$' | grep -oE '[0-9]+')
[ -n "$n_j4" ] || fail "judge TC-4: could not parse a hole count out of dispatch's stdout: $out_j4"
real_holes_j4=$(printf '%s\n' "$content_j4" | grep -cE '<<< FILL:.*>>>')
[ "$n_j4" -eq "$real_holes_j4" ] || fail "judge TC-4: the header/stdout hole count ($n_j4) should match the actual <<< FILL markers in the body ($real_holes_j4), so the BASE hole is included"

# --- judge TC-5: --judge 1-3 and --judge --gate-a both name --judge -------
#
# given: any plan. when: dispatch <plan> --judge 1-3 and dispatch <plan>
# --judge --gate-a are each run and stderr is captured. then: both exit 2,
# and the usage text names all three forms, including
# 'dispatch PLAN_FILE --judge [--force]' — grep -cF -- '--judge' over each
# is at least 1. Not the two-argument 'dispatch <plan> --judge' form: its
# 'bad RANGE: --judge' message echoes the argument and would pass this
# discriminator vacuously; that form belongs to judge TC-2.

repo_tc_j5=$(gitfixture_new)
plan_tc_j5=$(gitfixture_plan "$repo_tc_j5")

err_j5a=$(cd "$repo_tc_j5" && "$dispatch_script" "$plan_tc_j5" --judge 1-3 2>&1 1>/dev/null)
rc_j5a=$?
[ "$rc_j5a" -eq 2 ] || fail "judge TC-5: dispatch <plan> --judge 1-3 should exit 2, got $rc_j5a: $err_j5a"
count_j5a=$(printf '%s' "$err_j5a" | grep -cF -- '--judge')
[ "$count_j5a" -ge 1 ] || fail "judge TC-5: usage text for 'dispatch <plan> --judge 1-3' should name --judge at least once, got: $err_j5a"
assert_contains "$err_j5a" "dispatch PLAN_FILE --judge [--force]" \
  "judge TC-5: usage text should name the --judge form exactly" \
  || fail "judge TC-5: the --judge usage form is missing from 'dispatch <plan> --judge 1-3''s stderr: $err_j5a"

err_j5b=$(cd "$repo_tc_j5" && "$dispatch_script" "$plan_tc_j5" --judge --gate-a 2>&1 1>/dev/null)
rc_j5b=$?
[ "$rc_j5b" -eq 2 ] || fail "judge TC-5: dispatch <plan> --judge --gate-a should exit 2, got $rc_j5b: $err_j5b"
count_j5b=$(printf '%s' "$err_j5b" | grep -cF -- '--judge')
[ "$count_j5b" -ge 1 ] || fail "judge TC-5: usage text for 'dispatch <plan> --judge --gate-a' should name --judge at least once, got: $err_j5b"
assert_contains "$err_j5b" "dispatch PLAN_FILE --judge [--force]" \
  "judge TC-5: usage text should name the --judge form exactly" \
  || fail "judge TC-5: the --judge usage form is missing from 'dispatch <plan> --judge --gate-a''s stderr: $err_j5b"

# --- judge TC-6: an existing judge-dispatch.md is refused without --force -
#
# given: a workspace where judge-dispatch.md already exists. when: dispatch
# <plan> --judge is run again, then again with --force. then: the first
# exits 4, naming the existing file and mentioning --force; the second
# exits 0 and overwrites.

repo_tc_j6=$(gitfixture_new)
plan_tc_j6=$(write_topology_plan "$repo_tc_j6")
ws_tc_j6="$repo_tc_j6/.ai-workflow/run/plan"
mkdir -p "$ws_tc_j6"
printf '# placeholder\n' > "$ws_tc_j6/judge-dispatch.md"

out_j6a=$(cd "$repo_tc_j6" && "$dispatch_script" "$plan_tc_j6" --judge 2>&1)
rc_j6a=$?
[ "$rc_j6a" -eq 4 ] || fail "judge TC-6: dispatch <plan> --judge onto an existing judge-dispatch.md should exit 4, got $rc_j6a: $out_j6a"
assert_contains "$out_j6a" "$ws_tc_j6/judge-dispatch.md" \
  "judge TC-6: the refusal should name the existing file" || fail "judge TC-6: existing file path not named, got: $out_j6a"
assert_contains "$out_j6a" "--force" \
  "judge TC-6: the refusal should mention --force" || fail "judge TC-6: --force not mentioned, got: $out_j6a"

out_j6b=$(cd "$repo_tc_j6" && "$dispatch_script" "$plan_tc_j6" --judge --force 2>&1)
rc_j6b=$?
[ "$rc_j6b" -eq 0 ] || fail "judge TC-6: dispatch <plan> --judge --force should exit 0, got $rc_j6b: $out_j6b"
content_after_j6=$(cat "$ws_tc_j6/judge-dispatch.md")
[ "$content_after_j6" != "# placeholder" ] || fail "judge TC-6: --force should have overwritten judge-dispatch.md, but the placeholder content is still there"

# --- judge TC-14: judge-dispatch.md's headings are the thirteen frozen ----
#
# given: the judge dispatch written by dispatch --judge (judge TC-2's).
# when: its level-1 and level-2 headings are read in file order. then: they
# are the thirteen phase 1 froze, in that order and spelled exactly.

expected_headings_j14=$(cat <<'HEADINGS'
# Judge dispatch — the whole run
## Plan
## Implementers' reports
## Baseline
## Review package
## Frozen contracts
## Review criteria
## The seats you dispatch
## The scripts you run
## Cap origin
## Your report
## Corrections
## Run-specific warning
## Everything else
HEADINGS
)

headings_j14=$(grep -E '^(# |## )' "$dispatch_file_j2")
assert_eq "$expected_headings_j14" "$headings_j14" \
  "judge TC-14: judge-dispatch.md's level-1/2 headings should be the thirteen frozen sections, in order and spelled exactly" \
  || fail "judge TC-14: headings mismatch, got: $headings_j14"

# --- finish-guard: permits this run's own merges, denies every other, and
# stops denying a sentence that merely quotes one ---------------------------
#
# hooks/finish-guard.sh has no CLI seam of its own — it is a PreToolUse(Bash)
# hook, not a script this run's phases call — so it lands here for the same
# reason brief and dispatch do (see this file's own header). Labelled "guard
# TC-n" throughout, using this plan's own case numbers (TC-5 through TC-8):
# the bare TC-n token and every prefix already used in this file (attribution,
# phase check, worker, tester, judge) belong to earlier plans' own numbering.
#
# Every case feeds hooks/finish-guard.sh directly: cd into a fixture
# repository and pipe a JSON {"tool_input":{"command": ...}} at it, the same
# shape Claude Code's PreToolUse(Bash) event carries. The hook never executes
# $cmd — it only pattern-matches the text — so a command string below never
# needs to be valid, runnable shell, only the text the hook would have seen.

guard_script="$repo_root/hooks/finish-guard.sh"

guard_feed() {
  local repo="$1" cmd="$2"
  (cd "$repo" && jq -cn --arg cmd "$cmd" '{tool_input:{command:$cmd}}' | "$guard_script")
}

repo_grd=$(gitfixture_new)
plan_grd="$repo_grd/2026-09-24-five-defects.md"
printf '# fixture plan\n' > "$plan_grd"
base_grd=$(git -C "$repo_grd" rev-parse HEAD)
gitfixture_marker "$repo_grd" "$plan_grd" "$base_grd" >/dev/null

# guard TC-5: this run's own merges are permitted ---------------------------
#
# given: a run marker whose plan= names this plan. when: the hook is handed
# git merge --no-ff run/2026-09-24-five-defects/3, and again .../tests-1-7.
# then: both are permitted — the hook returns nothing.

out=$(guard_feed "$repo_grd" "git merge --no-ff run/2026-09-24-five-defects/3")
[ -z "$out" ] || fail "guard TC-5: merging run/2026-09-24-five-defects/3 should be permitted, got: $out"

out=$(guard_feed "$repo_grd" "git merge --no-ff run/2026-09-24-five-defects/tests-1-7")
[ -z "$out" ] || fail "guard TC-5: merging run/2026-09-24-five-defects/tests-1-7 should be permitted, got: $out"

# guard TC-6: every other merge, and every other history-surgery rule, is --
# still denied, with the message it carries today ---------------------------
#
# given: the same marker. when: a merge of main, of origin/main, of another
# run's branch, and each of the other five rules' own commands. then: every
# one is still denied, with the message it carries today. This case exists
# so the narrowing above cannot quietly become a hole.

guard_deny_contains() {
  local cmd="$1" phrase="$2"
  local result
  result=$(guard_feed "$repo_grd" "$cmd")
  [ -n "$result" ] || fail "guard TC-6: [$cmd] should still be denied, got empty output"
  assert_contains "$result" "$phrase" \
    "guard TC-6: [$cmd]'s denial should still mention: $phrase" \
    || fail "guard TC-6: denial message changed for [$cmd], got: $result"
}

guard_deny_contains "git merge main" "integrating is dev-skills:finish's job."
guard_deny_contains "git merge origin/main" "integrating is dev-skills:finish's job."
guard_deny_contains "git merge --no-ff run/2026-09-23-the-judge/3" "integrating is dev-skills:finish's job."
guard_deny_contains "git reset --hard HEAD~1" "moving HEAD is dev-skills:finish's job."
guard_deny_contains "git rebase -i HEAD~3" "rebasing is dev-skills:finish's job."
guard_deny_contains "git commit --amend --no-edit" "amending would move an already-read range under the gate's feet."
guard_deny_contains "git branch -d foo" "the run's branch and worktree are its recovery points."
guard_deny_contains "git push --force origin x" "a force-push during a run rewrites what the gates already read."

# guard TC-7: a command that only quotes a blocked one is permitted ---------
#
# given: the same marker. when: it is handed a command that only quotes a
# blocked one — a grep whose pattern is a sentence containing the word pair,
# a heredoc writing a file that describes it, and an echo of the same prose.
# then: all three are permitted.

q_grep_tc7='grep -n "please never run git merge --no-ff on this branch by hand" NOTES.md'
q_heredoc_tc7='cat > NOTES.md <<EOF
A rule we follow: never run git reset --hard, and never run git rebase -i, by hand.
EOF'
q_echo_tc7='echo "the guard blocks git commit --amend and git branch -d"'

out=$(guard_feed "$repo_grd" "$q_grep_tc7")
[ -z "$out" ] || fail "guard TC-7: a grep quoting a blocked command should be permitted, got: $out"

out=$(guard_feed "$repo_grd" "$q_heredoc_tc7")
[ -z "$out" ] || fail "guard TC-7: a heredoc describing a blocked command should be permitted, got: $out"

out=$(guard_feed "$repo_grd" "$q_echo_tc7")
[ -z "$out" ] || fail "guard TC-7: an echo quoting a blocked command should be permitted, got: $out"

# guard TC-8: with no run marker, the guard is inert ------------------------
#
# given: a repository with no run marker. when: it is handed a merge, a git
# reset --hard and a git rebase. then: all are permitted.

repo_grd8=$(gitfixture_new)

out=$(guard_feed "$repo_grd8" "git merge --no-ff run/2026-09-24-five-defects/3")
[ -z "$out" ] || fail "guard TC-8: with no run marker, a merge should be permitted, got: $out"

out=$(guard_feed "$repo_grd8" "git reset --hard HEAD~1")
[ -z "$out" ] || fail "guard TC-8: with no run marker, git reset --hard should be permitted, got: $out"

out=$(guard_feed "$repo_grd8" "git rebase -i HEAD~3")
[ -z "$out" ] || fail "guard TC-8: with no run marker, git rebase -i should be permitted, got: $out"

# --- worker: add answers for itself after a worker rm -----------------------
#
# given: worker add PLAN 5 BASE then worker rm PLAN 5 has run, leaving the
# branch behind at BASE. when: worker add PLAN 5 BASE runs again. then: if
# the branch is still at BASE, it re-attaches and prints the first call's
# five lines; if the branch has moved, it refuses in worker's own voice,
# naming the branch and the commit it points at, and creates no worktree.
#
# Labelled with this plan's own case numbers, TC-9 and TC-10. TC-9's failing
# assertion below repeats the string "worker TC-5" rather than continuing
# this file's own worker-TC-n sequence (which already runs 1 through 6):
# phase 5's mutation manifest row is frozen to that exact substring (see the
# plan's "Frozen for later phases" under phase 5), so the label the mutation
# net looks for follows the frozen text rather than this file's sequence.
# TC-10 carries no such constraint.

# worker TC-9 (phase 5's frozen manifest row calls its assertion "worker
# TC-5"): a branch still at BASE re-attaches and repeats the first call's
# five lines -----------------------------------------------------------------

repo_w9=$(gitfixture_new)
register_worker_cleanup "$repo_w9"
write_good_claude_md "$repo_w9"
gitfixture_gitignore "$repo_w9"
base_w9=$(git -C "$repo_w9" rev-parse HEAD)
plan_w9="$repo_w9/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w9"
slug_w9=$(basename "$plan_w9" .md)

out=$(cd "$repo_w9" && "$worker_script" add "$plan_w9" 5 "$base_w9" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-9 setup: the first worker add should exit 0, got $rc: $out"
first_add_out_w9="$out"

out=$(cd "$repo_w9" && "$worker_script" rm "$plan_w9" 5 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-9 setup: worker rm should exit 0, got $rc: $out"

out=$(cd "$repo_w9" && "$worker_script" add "$plan_w9" 5 "$base_w9" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-5: worker add after worker rm should exit 0, got $rc: $out"
[ "$out" = "$first_add_out_w9" ] \
  || fail "worker TC-9: worker add after worker rm should print the same five lines as the first call, got: $out"

wt_path_w9=$(printf '%s\n' "$out" | sed -n 's/^worktree: //p')
[ -d "$wt_path_w9" ] || fail "worker TC-9: the re-attached worktree should exist at the printed path, got: $wt_path_w9"
head_w9=$(git -C "$wt_path_w9" rev-parse HEAD)
[ "$head_w9" = "$base_w9" ] || fail "worker TC-9: the re-attached worktree's HEAD should equal base, got $head_w9 want $base_w9"
git -C "$repo_w9" show-ref --verify --quiet "refs/heads/run/${slug_w9}/5-5" \
  || fail "worker TC-9: the branch run/${slug_w9}/5-5 should still exist"

# worker TC-10: a branch that has moved past BASE is refused, in worker's --
# own voice, naming the branch and the commit it points at ------------------

repo_w10=$(gitfixture_new)
register_worker_cleanup "$repo_w10"
write_good_claude_md "$repo_w10"
gitfixture_gitignore "$repo_w10"
base_w10=$(git -C "$repo_w10" rev-parse HEAD)
plan_w10="$repo_w10/worker-plan.md"
printf '# Worker fixture plan\n' > "$plan_w10"
slug_w10=$(basename "$plan_w10" .md)

out=$(cd "$repo_w10" && "$worker_script" add "$plan_w10" 5 "$base_w10" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-10 setup: worker add should exit 0, got $rc: $out"
wt_path_w10=$(printf '%s\n' "$out" | sed -n 's/^worktree: //p')
[ -d "$wt_path_w10" ] || fail "worker TC-10 setup: worktree not created at $wt_path_w10"

printf 'moved\n' >> "$wt_path_w10/README.md"
git -C "$wt_path_w10" add README.md
git -C "$wt_path_w10" commit -q -m "chore: advance the branch past BASE"
moved_tip_w10=$(git -C "$wt_path_w10" rev-parse HEAD)

out=$(cd "$repo_w10" && "$worker_script" rm "$plan_w10" 5 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "worker TC-10 setup: worker rm should exit 0, got $rc: $out"

out=$(cd "$repo_w10" && "$worker_script" add "$plan_w10" 5 "$base_w10" 2>&1); rc=$?
[ "$rc" -eq 1 ] || fail "worker TC-10: worker add onto a branch that has moved past BASE should exit 1, got $rc: $out"
! printf '%s' "$out" | grep -qi '^fatal:' \
  || fail "worker TC-10: the refusal must be worker's own message, not a raw git fatal:, got: $out"
assert_contains "$out" "run/${slug_w10}/5-5" \
  "worker TC-10: the refusal should name the branch" || fail "worker TC-10: branch not named, got: $out"
assert_contains "$out" "$moved_tip_w10" \
  "worker TC-10: the refusal should name the commit the branch points at" || fail "worker TC-10: moved tip not named, got: $out"
[ ! -e "$wt_path_w10" ] || fail "worker TC-10: no worktree should be created for the refusal, got: $wt_path_w10"
current_tip_w10=$(git -C "$repo_w10" rev-parse "refs/heads/run/${slug_w10}/5-5")
[ "$current_tip_w10" = "$moved_tip_w10" ] \
  || fail "worker TC-10: the branch ref should not move, got $current_tip_w10 want $moved_tip_w10"

# --- harness.test.sh's own two refusal paths --------------------------------
#
# test/cli/harness.test.sh cannot exercise these two cases on itself: pointed
# at itself, either directly or through scripts/test, it would either invoke
# itself or start the run's one sweep (see harness.test.sh's own comment at
# :83-94). Both cases here run against a throwaway `git clone` of this
# repository, with one manifest target dirtied, so nothing in the real tree
# is touched — and that clone's own test/cli/harness.test.sh, run directly,
# never discovers or re-invokes anything outside itself.

clone_h=$(mktemp_dir)
git clone -q "$repo_root" "$clone_h" || fail "harness TC-2 setup: git clone should succeed"
dirtied_target_h="skills/finish/scripts/finish"
printf '# harness TC-2/TC-3 probe\n' >> "$clone_h/$dirtied_target_h"

# harness TC-2: a dirty manifest target refuses, names it, and never prints -
# ok, with DEV_SKILLS_MUTATION_ROW unset -------------------------------------
#
# given: a throwaway copy of this repository with one manifest target
# edited, and DEV_SKILLS_MUTATION_ROW not set. when: that copy's own
# test/cli/harness.test.sh is run. then: it exits non-zero, names that
# target, and never prints ok.

out=$(cd "$clone_h" && env -u DEV_SKILLS_MUTATION_ROW ./test/cli/harness.test.sh 2>&1); rc=$?
[ "$rc" -ne 0 ] || fail "harness TC-2: harness.test.sh with a dirty manifest target should exit non-zero, got $rc: $out"
assert_contains "$out" "$dirtied_target_h" \
  "harness TC-2: the refusal should name the dirtied target" || fail "harness TC-2: dirtied target not named, got: $out"
! printf '%s' "$out" | grep -qx "ok" \
  || fail "harness TC-2: a run that could not prove the net must never print ok, got: $out"

# harness TC-3: the same dirty copy, with DEV_SKILLS_MUTATION_ROW set, skips -
# straight to one skip line and exits 0 --------------------------------------
#
# given: the same copy, with DEV_SKILLS_MUTATION_ROW set to a row id. when:
# test/cli/harness.test.sh is run. then: it prints one skip line naming that
# row, exits 0, and runs no assertion and no sweep.

out=$(cd "$clone_h" && DEV_SKILLS_MUTATION_ROW=probe-row ./test/cli/harness.test.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "harness TC-3: harness.test.sh with DEV_SKILLS_MUTATION_ROW set should exit 0, got $rc: $out"
lines_h3=$(printf '%s\n' "$out" | grep -c .)
[ "$lines_h3" -eq 1 ] \
  || fail "harness TC-3: expected exactly one line of output (a skip, nothing else), got $lines_h3 line(s): $out"
assert_contains "$out" "skip" \
  "harness TC-3: the one line should say skip" || fail "harness TC-3: no mention of skip, got: $out"
assert_contains "$out" "probe-row" \
  "harness TC-3: the one line should name the row id the marker carries" || fail "harness TC-3: probe-row not named, got: $out"

echo "ok"
