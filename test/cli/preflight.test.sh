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

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc4_phase_one_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc4_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**How**
- plain implementation

**Do not touch**
- —

**Verification**
- cases: —

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc4_phase_three_becomes_true

**Changes**
- `src/three.ts` — placeholder

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
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

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc5_phase_one_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc5_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc5_phase_two_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc5_phase_three_becomes_true

**Changes**
- `src/three.ts` — placeholder

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
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
      echo "- cases: —"
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

echo "ok"
