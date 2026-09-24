#!/usr/bin/env bash
# Pins skills/implement/scripts/plan-check: the mechanical checker that
# refuses a malformed plan before a human ever sees it (TC-1, TC-2, TC-3 of
# .ai-workflow/plans/2026-08-06-six-fixes-from-real-runs.md).
#
# plan-check does not exist yet — this file is written before it, per the
# test-writer's own rule that a runnable test lands before the production
# code it describes. Every case below fails today because the script itself
# is missing; each one is RED for that reason, not for a wrong assertion.
#
# No git repository is needed: plan-check takes a plan path and nothing
# else. Every fixture plan is built in a scratch temp dir at run time (never
# test/fixtures/plan-frozen.md or plan-writesets.md, which phase 3 owns and
# which do not carry '## Phases' or a '## Topology' section at all yet).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

script="$repo_root/skills/implement/scripts/plan-check"

fail() {
  echo "plan-check.test.sh: $1" >&2
  exit 1
}

# run_plan_check PLAN — sets $out and $rc in the caller. Called as a plain
# statement, never wrapped in $(...): $rc has to survive the call, the same
# reason test/cli/preflight.test.sh's run_preflight is written this way.
run_plan_check() {
  out=$("$script" "$1" 2>&1)
  rc=$?
}

# The closing sentence phase 2's How field requires on every reported
# message: it tells the reader not to open the script to work out why. The
# plan gives the meaning, not the literal words, so this checks the meaning —
# a negation, a read/open verb, and the word "script" — on the message's own
# closing line, rather than a literal string this file would be guessing at.
assert_ends_without_reading_script() {
  local out="$1" msg="$2" last
  last=$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | tail -n1)
  printf '%s' "$last" | grep -qi 'script' \
    || fail "$msg (closing line does not mention 'script': $last)"
  printf '%s' "$last" | grep -qiE "not|never" \
    || fail "$msg (closing line has no negation: $last)"
  printf '%s' "$last" | grep -qiE 'read|open' \
    || fail "$msg (closing line has no read/open verb: $last)"
}

# --- TC-1: three phases, all seven fields, no '## Phases' — repaired -------
#
# given: a plan with three '### Phase N.' headings, all seven fields on each,
# and no '## Phases' line.

dir1=$(mktemp_dir)
plan1="$dir1/plan.md"
cat > "$plan1" <<'EOF'
# TC-1 fixture plan

### Phase 1. First phase title

**Becomes true**
- tc1_phase_one_becomes_true

**Changes**
- `src/one.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc1_phase_one_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc1_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc1_phase_two_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc1_phase_three_becomes_true

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

! grep -qE '^##[ \t]+Phases[ \t]*$' "$plan1" \
  || fail "TC-1 test setup: fixture must start with no '## Phases' line"

run_plan_check "$plan1"
[ "$rc" -eq 0 ] || fail "TC-1: plan-check on a repairable plan should exit 0, got $rc: $out"

fixed_count=$(printf '%s\n' "$out" | grep -c '^fixed:')
[ "$fixed_count" -eq 1 ] || fail "TC-1: expected exactly one 'fixed:' line, got $fixed_count: $out"
fixed_line=$(printf '%s\n' "$out" | grep '^fixed:')
assert_contains "$fixed_line" "## Phases" \
  "TC-1: the fixed: line should name what it inserted (## Phases)" || fail "fixed: line missing ## Phases"
assert_contains "$fixed_line" "Phase 1" \
  "TC-1: the fixed: line should name where it inserted it (above Phase 1)" || fail "fixed: line missing where"

phases_line=$(grep -n '^##[ \t]*Phases[ \t]*$' "$plan1" | head -1 | cut -d: -f1)
phase1_line=$(grep -n '^###[ \t]*Phase[ \t]*1\.' "$plan1" | head -1 | cut -d: -f1)
[ -n "$phases_line" ] || fail "TC-1: '## Phases' should now be present in the file"
[ -n "$phase1_line" ] || fail "TC-1: test setup lost '### Phase 1.'"
[ "$phases_line" -lt "$phase1_line" ] || fail "TC-1: '## Phases' must sit above '### Phase 1.'"
between=$(sed -n "$((phases_line + 1)),$((phase1_line - 1))p" "$plan1" | grep -vc '^[ \t]*$')
[ "$between" -eq 0 ] \
  || fail "TC-1: '## Phases' must sit immediately above '### Phase 1.', nothing else between them"

# --- TC-1, second run: idempotent — no 'fixed:' line, exit 0 ---------------

before=$(cat "$plan1")
run_plan_check "$plan1"
[ "$rc" -eq 0 ] || fail "TC-1: a second run on an already-repaired plan should exit 0, got $rc"
! printf '%s' "$out" | grep -q '^fixed:' \
  || fail "TC-1: a second run should print no 'fixed:' line, got: $out"
after=$(cat "$plan1")
assert_eq "$before" "$after" "TC-1: a second run must not change the file" || fail "file changed on rerun"

# --- TC-2: phase 2 missing '**Frozen for later phases**' — reported --------
#
# given: a plan of three phases where phase 2 has no
# '**Frozen for later phases**'.

dir2=$(mktemp_dir)
plan2="$dir2/plan.md"
cat > "$plan2" <<'EOF'
# TC-2 fixture plan

## Phases

### Phase 1. First phase title

**Becomes true**
- tc2_phase_one_becomes_true

**Changes**
- `src/one.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc2_phase_one_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc2_phase_two_becomes_true

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
- tc2_phase_three_becomes_true

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

! grep -qF '**Frozen for later phases**' <(sed -n '/^### Phase 2\./,/^### Phase 3\./p' "$plan2") \
  || fail "TC-2 test setup: phase 2 must not carry '**Frozen for later phases**'"

before2=$(cat "$plan2")
run_plan_check "$plan2"
[ "$rc" -eq 1 ] || fail "TC-2: a plan with a missing field should exit 1, got $rc: $out"
printf '%s' "$out" | grep -qi 'phase 2' \
  || fail "TC-2: the message should name phase 2, got: $out"
assert_contains "$out" "Frozen for later phases" \
  "TC-2: the message should name the missing field" || fail "missing-field name absent"
! printf '%s' "$out" | grep -qiE 'phase 1|phase 3' \
  || fail "TC-2: phases 1 and 3 must not be reported, got: $out"
assert_ends_without_reading_script "$out" "TC-2: message should end telling the reader not to open the script"
after2=$(cat "$plan2")
assert_eq "$before2" "$after2" "TC-2: the file must not be modified" || fail "file was modified"

# --- TC-3: a well-formed plan — clean, byte-identical afterwards -----------
#
# given: '## Phases', contiguous phases from 1, seven fields each, a
# '## Topology' table with 'Phases | Implementer | Why the boundary is here',
# a '## Ledger'.

dir3=$(mktemp_dir)
plan3="$dir3/plan.md"
cat > "$plan3" <<'EOF'
# TC-3 fixture plan

## Phases

### Phase 1. First phase title

**Becomes true**
- tc3_phase_one_becomes_true

**Changes**
- `src/one.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc3_phase_one_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc3_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc3_phase_two_frozen` — placeholder

**Verification**
- proved by: phase 3

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc3_phase_three_becomes_true

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

## Topology

| Phases | Implementer | Why the boundary is here |
|---|---|---|
| 1-3 | Sonnet | tc3_single_group |

## Ledger

- [ ] Tests written
- [ ] Phase 1
- [ ] Phase 2
- [ ] Phase 3
EOF

before3=$(cat "$plan3")
run_plan_check "$plan3"
[ "$rc" -eq 0 ] || fail "TC-3: a well-formed plan should exit 0, got $rc: $out"
! printf '%s' "$out" | grep -q '^fixed:' \
  || fail "TC-3: a well-formed plan should print no 'fixed:' line, got: $out"
after3=$(cat "$plan3")
assert_eq "$before3" "$after3" "TC-3: a well-formed plan's file must be byte-identical afterwards" \
  || fail "file changed"

# --- phase numbers past nine ------------------------------------------------
#
# The contiguity and coverage checks compare lists of numbers sorted with
# `sort -n`. Compared with `comm` — as they were until gate A caught it — the
# comparison silently breaks at the first two-digit number: comm compares as
# text whatever the locale, and numerically 9 precedes 10 while as text it does
# not. A plan of nine phases never shows it. Every case above uses three, which
# is why none of them caught it.
#
# The symptom it produced: a twelve-phase plan with phase 9 duplicated reported
# "duplicated: 9 10 11 12" — three phases accused that were entirely fine.

# write_numbered_plan FILE NUMBERS TABLE_RANGE
write_numbered_plan() {
  local f="$1" nums="$2" rng="$3" n fld last=0
  for n in $nums; do [ "$n" -gt "$last" ] && last="$n"; done
  {
    printf '# numbered\n\n## Phases\n\n'
    for n in $nums; do
      printf '### Phase %s. p%s\n\n' "$n" "$n"
      for fld in "Becomes true" "Changes" "Depends on" "How" "Do not touch" \
                 "Frozen for later phases" "Verification" "Steps"; do
        case "$fld" in
          "Depends on")
            printf '**%s**\n- —\n\n' "$fld" ;;
          "Verification")
            if [ "$n" -eq "$last" ]; then
              printf '**%s**\n- joins: phases 1-%s\n- cases: —\n\n' "$fld" "$((last - 1))"
            else
              printf '**%s**\n- proved by: phase %s\n\n' "$fld" "$last"
            fi ;;
          *)
            printf '**%s**\n- x\n\n' "$fld" ;;
        esac
      done
    done
    printf '## Topology\n\n'
    printf '| Phases | Implementer | Why the boundary is here |\n'
    printf '|---|---|---|\n'
    printf '| %s | Sonnet | one |\n\n' "$rng"
    printf '## Ledger\n- [ ] x\n'
  } > "$f"
}

numdir=$(mktemp_dir)

# twelve contiguous phases, the table covering all of them: nothing to report
write_numbered_plan "$numdir/ok.md" "1 2 3 4 5 6 7 8 9 10 11 12" "1-12"
run_plan_check "$numdir/ok.md"
[ "$rc" -eq 0 ] || fail "twelve contiguous phases should exit 0, got $rc: $out"

# phase 9 duplicated: 9 named, and no innocent two-digit phase alongside it
write_numbered_plan "$numdir/dup.md" "1 2 3 4 5 6 7 8 9 9 10 11 12" "1-12"
run_plan_check "$numdir/dup.md"
[ "$rc" -eq 1 ] || fail "a duplicated phase should exit 1, got $rc: $out"
assert_contains "$out" "duplicated: 9" \
  "the duplicate should be named" || fail "duplicate not named"
! printf '%s' "$out" | grep -qE 'duplicated:[^.]*1[012]' \
  || fail "only phase 9 is duplicated; 10, 11 and 12 must not be accused: $out"

# phase 10 missing: the two-digit gap is found, and named
write_numbered_plan "$numdir/gap.md" "1 2 3 4 5 6 7 8 9 11 12" "1-12"
run_plan_check "$numdir/gap.md"
[ "$rc" -eq 1 ] || fail "a gap in the numbering should exit 1, got $rc: $out"
assert_contains "$out" "missing: 10" \
  "the two-digit gap should be named" || fail "gap not named"

# --- the check-1 repair preserves the plan's own file mode -----------------
#
# check 1 repairs through mktemp + mv. mktemp hands out 0600 regardless of
# the mode the plan file already had, so a naive `mv "$tmp" "$plan"` quietly
# drops whatever mode the plan carried (typically 0644) to 0600.

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

dir4=$(mktemp_dir)
plan4="$dir4/plan.md"
cat > "$plan4" <<'EOF'
# mode fixture plan

### Phase 1. First phase title

**Becomes true**
- mode_phase_one_becomes_true

**Changes**
- `src/one.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `mode_phase_one_frozen` — placeholder

**Verification**
- proved by: phase 2

**Steps**
- [ ] step one

### Phase 2. The join

**Becomes true**
- mode_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- joins: phases 1-1
- cases: —

**Steps**
- [ ] step two
EOF

chmod 644 "$plan4"
before_mode=$(file_mode "$plan4")
[ "$before_mode" = "644" ] || fail "mode test setup: expected 644 before repair, got $before_mode"

run_plan_check "$plan4"
[ "$rc" -eq 0 ] || fail "mode: plan-check on a repairable plan should exit 0, got $rc: $out"
fixed_count4=$(printf '%s\n' "$out" | grep -c '^fixed:')
[ "$fixed_count4" -eq 1 ] || fail "mode: expected exactly one 'fixed:' line, got $fixed_count4: $out"

after_mode=$(file_mode "$plan4")
assert_eq "$before_mode" "$after_mode" \
  "mode: the repair must preserve the plan's original file mode, not mktemp's 0600 (was $before_mode, now $after_mode)" \
  || fail "file mode changed by repair"

# second run: already repaired, no further write — mode still untouched
run_plan_check "$plan4"
[ "$rc" -eq 0 ] || fail "mode: a second run on an already-repaired plan should exit 0, got $rc"
after_mode2=$(file_mode "$plan4")
assert_eq "$before_mode" "$after_mode2" \
  "mode: a second, idempotent run must not change the file mode either" \
  || fail "file mode changed on idempotent rerun"

# --- TC-1, TC-2, TC-3, TC-4, TC-5, TC-11 of ------------------------------
# .ai-workflow/plans/2026-08-23-moments-in-the-plan.md — the '## Moments'
# check. These numbers repeat TC-1/TC-2/TC-3 used above for
# .ai-workflow/plans/2026-08-06-six-fixes-from-real-runs.md: two different
# plans, each with its own case list, sharing this one file per that plan's
# Test seams.
#
# The '## Moments' check itself is phase 2's, and does not exist in this
# script yet. Every fixture below is well-formed by every OTHER check —
# '## Phases', every phase carrying all eight fields, a covering
# '## Topology' table, a '## Ledger' — so that only the moments rule under
# test can move the exit code or the findings. Two phases, not one: check 9
# reads a phase's '**Verification**' as naming the join that proves it, and
# the smallest plan that can say that is one phase and the join it names.

# write_moments_plan FILE BLOCK — BLOCK becomes the verbatim body of
# '## Moments'; pass "" to omit the heading entirely (TC-5).
write_moments_plan() {
  local f="$1" block="$2" fld n
  {
    printf '# moments fixture\n\n'
    if [ -n "$block" ]; then
      printf '## Moments\n\n%s\n\n' "$block"
    fi
    printf '## Phases\n\n'
    for n in 1 2; do
      printf '### Phase %s. Phase %s title\n\n' "$n" "$n"
      for fld in "Becomes true" "Changes" "Depends on" "How" "Do not touch" \
                 "Frozen for later phases" "Verification" "Steps"; do
        case "$fld" in
          "Depends on")
            printf '**%s**\n- —\n\n' "$fld" ;;
          "Verification")
            if [ "$n" -eq 2 ]; then
              printf '**%s**\n- joins: phases 1-1\n- cases: —\n\n' "$fld"
            else
              printf '**%s**\n- proved by: phase 2\n\n' "$fld"
            fi ;;
          *)
            printf '**%s**\n- x\n\n' "$fld" ;;
        esac
      done
    done
    printf '## Topology\n\n'
    printf '| Phases | Implementer | Why the boundary is here |\n'
    printf '|---|---|---|\n'
    printf '| 1-2 | Sonnet | one |\n\n'
    printf '## Ledger\n- [ ] x\n'
  } > "$f"
}

# --- TC-1: a moment with a single step ------------------------------------
#
# given: '## Moments' holds '- **M-1. Switching provider** · US-1' followed
# by a single numbered step.

dirm1=$(mktemp_dir)
planm1="$dirm1/plan.md"
write_moments_plan "$planm1" '- **M-1. Switching provider** · US-1
  1. You open settings and pick a new provider.'

run_plan_check "$planm1"
[ "$rc" -eq 1 ] || fail "TC-1 (moments): a moment with one step should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'M-1' \
  || fail "TC-1 (moments): the finding should name M-1, got: $out"
printf '%s' "$out" | grep -qiE '\btwo\b|\b2\b' \
  || fail "TC-1 (moments): the finding should say a moment needs at least two steps, got: $out"
printf '%s' "$out" | grep -qi 'step' \
  || fail "TC-1 (moments): the finding should mention steps, got: $out"

# --- TC-2: a bullet under '## Moments' that is not a moment heading --------
#
# given: '## Moments' holds '- **Switching provider** · US-1' — no
# 'M-<n>.'.

dirm2=$(mktemp_dir)
planm2="$dirm2/plan.md"
write_moments_plan "$planm2" '- **Switching provider** · US-1'

run_plan_check "$planm2"
[ "$rc" -eq 1 ] || fail "TC-2 (moments): a bullet with no 'M-<n>.' should exit 1, got $rc: $out"
assert_contains "$out" "Switching provider" \
  "TC-2 (moments): the finding should name the offending line" || fail "line not named"
printf '%s' "$out" | grep -q 'M-' \
  || fail "TC-2 (moments): the finding should say the shape it wanted (an 'M-<n>.' heading), got: $out"

# --- TC-3: a well-formed moment ---------------------------------------------
#
# given: one moment heading, four numbered steps.

dirm3=$(mktemp_dir)
planm3="$dirm3/plan.md"
write_moments_plan "$planm3" '- **M-1. Switching provider** · US-1
  1. You open settings and see your current provider.
  2. You pick a new provider from the list.
  3. You see a confirmation before anything changes.
  4. You see the switch applied and your data intact.'

run_plan_check "$planm3"
[ "$rc" -eq 0 ] || fail "TC-3 (moments): a well-formed moment should exit 0, got $rc: $out"
! printf '%s' "$out" | grep -qi 'moment' \
  || fail "TC-3 (moments): no finding should mention a moment, got: $out"

# --- TC-4: '## Moments' holding a single dash -------------------------------
#
# given: '## Moments' is a single '—', asserting no new moment.

dirm4=$(mktemp_dir)
planm4="$dirm4/plan.md"
write_moments_plan "$planm4" '—'

run_plan_check "$planm4"
[ "$rc" -eq 0 ] || fail "TC-4 (moments): a dash should exit 0, got $rc: $out"
! printf '%s' "$out" | grep -qi 'moment' \
  || fail "TC-4 (moments): a dash should raise no finding mentioning a moment, got: $out"

# --- TC-5: no '## Moments' heading at all -----------------------------------

dirm5=$(mktemp_dir)
planm5="$dirm5/plan.md"
write_moments_plan "$planm5" ""

! grep -qE '^##[ \t]+Moments[ \t]*$' "$planm5" \
  || fail "TC-5 test setup: fixture must have no '## Moments' heading"

run_plan_check "$planm5"
[ "$rc" -eq 0 ] || fail "TC-5 (moments): a plan with no '## Moments' heading should exit 0, got $rc: $out"
[ -z "$out" ] \
  || fail "TC-5 (moments): a plan with no '## Moments' heading should raise no finding at all, got: $out"

# --- TC-11: a moment heading with no story reference ------------------------
#
# given: '## Moments' holds '- **M-1. Switching provider**' with nothing
# after it — no 'US-' reference.

dirm11=$(mktemp_dir)
planm11="$dirm11/plan.md"
write_moments_plan "$planm11" '- **M-1. Switching provider**
  1. You open settings and see your current provider.
  2. You pick a new provider from the list.'

run_plan_check "$planm11"
[ "$rc" -eq 1 ] || fail "TC-11 (moments): a moment heading with no story reference should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'M-1' \
  || fail "TC-11 (moments): the finding should name M-1, got: $out"
printf '%s' "$out" | grep -qiE 'stor|US-' \
  || fail "TC-11 (moments): the finding should say a moment names the stories it gathers, got: $out"

# --- a moment whose steps are indented four spaces --------------------------
#
# No TC-ID: this is a local regression test, not one of the plan's approved
# cases. Steps are counted by /^  [0-9]+\.[ \t]/, so ordinary four-space
# markdown nesting is not a step. The rule stays as frozen — four spaces is
# still rejected — but the finding has to name the two-space indentation, or
# it reports '0 numbered step(s)' to a planner looking at two steps.

dirm12=$(mktemp_dir)
planm12="$dirm12/plan.md"
write_moments_plan "$planm12" '- **M-1. Switching provider**  · US-1
    1. You open settings and see your current provider.
    2. You pick a new provider from the list.'

run_plan_check "$planm12"
[ "$rc" -eq 1 ] || fail "four-space steps: should still exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'M-1' \
  || fail "four-space steps: the finding should name M-1, got: $out"
printf '%s' "$out" | grep -qiE 'two spaces|indent' \
  || fail "four-space steps: the finding should name the two-space indentation, got: $out"

# --- graph TC-1 through graph TC-12 -----------------------------------------
#
# .ai-workflow/plans/2026-09-24-the-plans-graph.md's own test cases: the
# eighth phase field, '**Depends on**', the checker that refuses a plan
# whose field is missing, empty, malformed or points forward (plan-check —
# graph TC-1 through graph TC-8) and the script that renders '## Graph' from
# the field (plan-graph — graph TC-9 through graph TC-12). Labelled
# 'graph TC-n' throughout — this comment and every fail message — because
# this file already numbers its own cases TC-1 through TC-11 for two earlier
# plans, and two identically prefixed messages in one file would let a
# mutation row match the wrong assertion.
#
# graph TC-13, graph TC-14 and graph TC-15 are not here: TC-13 is a mutation
# patch plus a manifest row phase 2 adds, TC-14 is a set of greps and TC-15
# runs the whole suite — both driven directly by the final gate, neither an
# executable case in this file.
#
# plan-graph does not exist yet, so graph TC-9 through graph TC-12 fail for
# that reason alone — the same reason every case in this file's own header
# comment gives for plan-check itself, before it existed.

script_graph="$repo_root/skills/implement/scripts/plan-graph"

# run_plan_graph PLAN — sets $out and $rc in the caller, the same contract
# as run_plan_check above and for the same reason: $rc must survive the
# call, so it is never wrapped in $(...).
run_plan_graph() {
  out=$("$script_graph" "$1" 2>&1)
  rc=$?
}

# write_graph_plan FILE P1 P2 P3 — a three-phase, otherwise well-formed plan
# (a covering '## Topology' table, a '## Ledger', all seven existing fields
# on every phase), mirroring the fixture the file's own TC-3 already builds
# above. P1, P2 and P3 are each the verbatim '**Depends on**' block —
# heading and body — placed directly under that phase's '**Changes**', which
# is where phase 1's How field says the eighth field belongs; pass "" to
# omit the heading from that phase entirely.
write_graph_plan() {
  local f="$1" p1="$2" p2="$3" p3="$4" n title changes depends
  {
    printf '# graph fixture plan\n\n## Phases\n\n'
    for n in 1 2 3; do
      case "$n" in
        1) title="First phase title"; changes="src/one.ts"; depends="$p1" ;;
        2) title="Second phase title"; changes="src/two.ts"; depends="$p2" ;;
        3) title="Third phase title"; changes="src/three.ts"; depends="$p3" ;;
      esac
      printf '### Phase %s. %s\n\n' "$n" "$title"
      printf '**Becomes true**\n- graph_phase_%s_becomes_true\n\n' "$n"
      printf '**Changes**\n- `%s` — placeholder\n\n' "$changes"
      if [ -n "$depends" ]; then
        printf '%s\n\n' "$depends"
      fi
      printf '**How**\n- plain implementation\n\n'
      printf '**Do not touch**\n- —\n\n'
      printf '**Frozen for later phases**\n- —\n\n'
      if [ "$n" -eq 3 ]; then
        printf '**Verification**\n- joins: phases 1-2\n- cases: —\n\n'
      else
        printf '**Verification**\n- proved by: phase 3\n\n'
      fi
      printf '**Steps**\n- [ ] step %s\n\n' "$n"
    done
    printf '## Topology\n\n'
    printf '| Phases | Implementer | Why the boundary is here |\n'
    printf '|---|---|---|\n'
    printf '| 1-3 | Sonnet | graph_fixture_single_group |\n\n'
    printf '## Ledger\n- [ ] x\n'
  } > "$f"
}

# depends_slice PLAN PHASE_HEADING NEXT_HEADING — the lines of PLAN between
# (not including) the two headings, for setup assertions on one phase's own
# field without matching another phase's.
depends_slice() {
  sed -n "/^### Phase ${2}\\./,/^### Phase ${3}\\./p" "$1" | sed '1d;$d'
}

# phase_depends_body PLAN PHASE NEXT_PHASE — the body lines of PHASE's own
# '**Depends on**' field only: the lines after the heading and before the
# next bold field heading, the next phase heading, or the next '##'. Scoped
# to one phase first (via depends_slice) so a bullet under some other field
# ('**Becomes true**', '**Changes**', ...) is never mistaken for one here.
phase_depends_body() {
  depends_slice "$1" "$2" "$3" | awk '
    /^\*\*Depends on\*\*[ \t]*$/ { infield = 1; next }
    infield && /^\*\*[A-Za-z]/ { exit }
    infield && /^##/ { exit }
    infield { print }
  '
}

dep_none=$(cat <<'EOF'
**Depends on**
- —
EOF
)

dep_on_1=$(cat <<'EOF'
**Depends on**
- phase 1 — src/phase1.ts, which it edits
EOF
)

dep_on_2=$(cat <<'EOF'
**Depends on**
- phase 2 — src/two.ts, which it edits
EOF
)

dep_on_3=$(cat <<'EOF'
**Depends on**
- phase 3 — src/three.ts, which it edits
EOF
)

dep_no_emdash=$(cat <<'EOF'
**Depends on**
- phase 1
EOF
)

dep_no_phase_word=$(cat <<'EOF'
**Depends on**
- 1 — src/phase1.ts
EOF
)

dep_heading_only=$(cat <<'EOF'
**Depends on**
EOF
)

dep_mixed=$(cat <<'EOF'
**Depends on**
- —
- phase 1 — src/phase1.ts, which it edits
EOF
)

# --- graph TC-1: phase 2 carries no '**Depends on**' heading at all --------

dirg1=$(mktemp_dir)
plang1="$dirg1/plan.md"
write_graph_plan "$plang1" "$dep_none" "" "$dep_none"

! grep -qF '**Depends on**' <(depends_slice "$plang1" 2 3) \
  || fail "graph TC-1 test setup: phase 2 must carry no '**Depends on**' heading"

run_plan_check "$plang1"
[ "$rc" -eq 1 ] || fail "graph TC-1: a phase with no '**Depends on**' heading should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "graph TC-1: the finding should name phase 2, got: $out"
assert_contains "$out" "Depends on" \
  "graph TC-1: the finding should name the missing '**Depends on**' field" || fail "missing-field name absent"

# --- graph TC-2: '- —' on every phase — accept-side pin ---------------------
#
# Would pass even before check 8 exists: what it pins is the other
# direction, that check 8 does not over-refuse a well-formed '- —' on every
# phase.

dirg2=$(mktemp_dir)
plang2="$dirg2/plan.md"
write_graph_plan "$plang2" "$dep_none" "$dep_none" "$dep_none"

run_plan_check "$plang2"
[ "$rc" -eq 0 ] || fail "graph TC-2: '- —' on every phase should exit 0, got $rc: $out"
[ -z "$out" ] || fail "graph TC-2: '- —' on every phase should print nothing, got: $out"

# --- graph TC-3: phase 3 depending on phase 1 — accept-side pin -------------

dirg3=$(mktemp_dir)
plang3="$dirg3/plan.md"
write_graph_plan "$plang3" "$dep_none" "$dep_none" "$dep_on_1"

run_plan_check "$plang3"
[ "$rc" -eq 0 ] || fail "graph TC-3: phase 3 depending on phase 1 should exit 0, got $rc: $out"
[ -z "$out" ] || fail "graph TC-3: phase 3 depending on phase 1 should print nothing, got: $out"

# --- graph TC-4: phase 2's field naming phase 3, a later phase --------------
#
# This case's fail message is frozen verbatim (the plan's Test cases
# section): the manifest row phase 2 adds for
# test/mutations/plan-check-depends-forward-allowed.patch matches it with
# grep -F, so the text up to 'got $rc' may not be reworded.

dirg4=$(mktemp_dir)
plang4="$dirg4/plan.md"
write_graph_plan "$plang4" "$dep_none" "$dep_on_3" "$dep_none"

run_plan_check "$plang4"
[ "$rc" -eq 1 ] || fail "graph TC-4: a Depends on naming a later phase should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "graph TC-4: the finding should name phase 2, got: $out"
printf '%s' "$out" | grep -qE '(^|[^0-9])3([^0-9]|$)' \
  || fail "graph TC-4: the finding should name the number 3, got: $out"
printf '%s' "$out" | grep -qi 'earlier' \
  || fail "graph TC-4: the finding should say a dependency is always on an earlier phase, got: $out"

# --- graph TC-5: phase 2's field naming phase 2, itself ---------------------

dirg5=$(mktemp_dir)
plang5="$dirg5/plan.md"
write_graph_plan "$plang5" "$dep_none" "$dep_on_2" "$dep_none"

run_plan_check "$plang5"
[ "$rc" -eq 1 ] || fail "graph TC-5: a Depends on naming its own phase should exit 1, got $rc: $out"
phase2_count=$(printf '%s' "$out" | grep -o 'phase 2' | wc -l | tr -d ' ')
[ "$phase2_count" -ge 2 ] \
  || fail "graph TC-5: the finding should name phase 2 twice over, got: $out"

# --- graph TC-6: a bullet in the wrong shape ---------------------------------
#
# Two fixtures: no em dash and no reason, then a number with no 'phase'.

dirg6a=$(mktemp_dir)
plang6a="$dirg6a/plan.md"
write_graph_plan "$plang6a" "$dep_none" "$dep_no_emdash" "$dep_none"

run_plan_check "$plang6a"
[ "$rc" -eq 1 ] || fail "graph TC-6 (no em dash): should exit 1, got $rc: $out"
assert_contains "$out" "- phase 1" \
  "graph TC-6 (no em dash): the finding should quote the offending bullet" || fail "offending bullet not quoted"
assert_contains "$out" "- phase <n> — <why this phase needs its file>" \
  "graph TC-6 (no em dash): the finding should give the expected shape" || fail "expected shape absent"

dirg6b=$(mktemp_dir)
plang6b="$dirg6b/plan.md"
write_graph_plan "$plang6b" "$dep_none" "$dep_no_phase_word" "$dep_none"

run_plan_check "$plang6b"
[ "$rc" -eq 1 ] || fail "graph TC-6 (no phase word): should exit 1, got $rc: $out"
assert_contains "$out" "- 1 — src/phase1.ts" \
  "graph TC-6 (no phase word): the finding should quote the offending bullet" || fail "offending bullet not quoted"
assert_contains "$out" "- phase <n> — <why this phase needs its file>" \
  "graph TC-6 (no phase word): the finding should give the expected shape" || fail "expected shape absent"

# --- graph TC-7: the heading present, no bullet under it --------------------

dirg7=$(mktemp_dir)
plang7="$dirg7/plan.md"
write_graph_plan "$plang7" "$dep_none" "$dep_heading_only" "$dep_none"

grep -qF '**Depends on**' <(depends_slice "$plang7" 2 3) \
  || fail "graph TC-7 test setup: phase 2 must carry the '**Depends on**' heading"
body7=$(phase_depends_body "$plang7" 2 3)
[ -z "$(printf '%s\n' "$body7" | grep -v '^[ \t]*$')" ] \
  || fail "graph TC-7 test setup: phase 2 must carry no bullet under '**Depends on**'"

run_plan_check "$plang7"
[ "$rc" -eq 1 ] || fail "graph TC-7: an empty '**Depends on**' should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "graph TC-7: the finding should name phase 2, got: $out"
assert_contains "$out" "- —" \
  "graph TC-7: the finding should say to write '- —' when the phase depends on nothing" || fail "'- —' not suggested"

# --- graph TC-8: '- —' mixed with a dependency bullet -----------------------

dirg8=$(mktemp_dir)
plang8="$dirg8/plan.md"
write_graph_plan "$plang8" "$dep_none" "$dep_none" "$dep_mixed"

run_plan_check "$plang8"
[ "$rc" -eq 1 ] || fail "graph TC-8: '- —' mixed with a dependency should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 3' \
  || fail "graph TC-8: the finding should name phase 3, got: $out"
printf '%s' "$out" | grep -qi 'alone' \
  || fail "graph TC-8: the finding should say the dash stands alone or not at all, got: $out"

# --- graph TC-9: plan-graph renders '## Graph' from the fields --------------
#
# The fixture's phase titles are 'One', 'Two' and 'Three' exactly, and its
# phase 3 depends on phases 1 and 2 — not decoration: the assertion below is
# a byte comparison against the block frozen in phase 3's How field, which
# was written for these titles.

write_titled_plan() {
  cat > "$1" <<'PLANEOF'
# graph render fixture plan

## Phases

### Phase 1. One

**Becomes true**
- one_becomes_true

**Changes**
- `src/one.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- proved by: phase 3

**Steps**
- [ ] step one

### Phase 2. Two

**Becomes true**
- two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- proved by: phase 3

**Steps**
- [ ] step two

### Phase 3. Three

**Becomes true**
- three_becomes_true

**Changes**
- `src/three.ts` — placeholder

**Depends on**
- phase 1 — src/one.ts, which it edits
- phase 2 — src/two.ts, which it edits

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
PLANEOF
}

dirg9=$(mktemp_dir)
plang9="$dirg9/plan.md"
write_titled_plan "$plang9"

! grep -qE '^##[ \t]+Graph[ \t]*$' "$plang9" \
  || fail "graph TC-9 test setup: fixture must start with no '## Graph' section"

expected_graph_block=$(cat <<'BLOCKEOF'
## Graph

<!-- rendered by skills/implement/scripts/plan-graph — do not edit by hand -->

```text
1  --       One
2  --       Two
3  <- 1, 2  Three

3 phases · 2 with no dependency · longest chain: 1 -> 3
```
BLOCKEOF
)

run_plan_graph "$plang9"
[ "$rc" -eq 0 ] || fail "graph TC-9: plan-graph on a valid plan should exit 0, got $rc: $out"
first_word=$(printf '%s\n' "$out" | head -n1 | awk '{print $1}')
[ "$first_word" = "wrote:" ] \
  || fail "graph TC-9: stdout's first word should be 'wrote:', got: $out"
line_count=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$line_count" -eq 1 ] || fail "graph TC-9: stdout should be exactly one line, got: $out"

graph_line=$(grep -n '^## Graph$' "$plang9" | head -1 | cut -d: -f1)
phases_line9=$(grep -n '^## Phases$' "$plang9" | head -1 | cut -d: -f1)
[ -n "$graph_line" ] || fail "graph TC-9: '## Graph' should now be present in the file"
[ -n "$phases_line9" ] || fail "graph TC-9 test setup: lost '## Phases'"
[ "$graph_line" -lt "$phases_line9" ] || fail "graph TC-9: '## Graph' must sit above '## Phases'"

fence_end=$(awk 'NR>'"$graph_line"' && /^```$/ { print NR; exit }' "$plang9")
[ -n "$fence_end" ] || fail "graph TC-9: could not find the closing fence of the rendered block"
actual_graph_block=$(sed -n "${graph_line},${fence_end}p" "$plang9")
assert_eq "$expected_graph_block" "$actual_graph_block" \
  "graph TC-9: the '## Graph' block should be byte-identical to the one frozen in phase 3" \
  || fail "rendered block does not match"

# --- graph TC-10: a second run is a no-op — 'unchanged:', bytes unchanged ---

before9=$(cat "$plang9")
run_plan_graph "$plang9"
[ "$rc" -eq 0 ] || fail "graph TC-10: a second run should exit 0, got $rc: $out"
first_word10=$(printf '%s\n' "$out" | head -n1 | awk '{print $1}')
[ "$first_word10" = "unchanged:" ] \
  || fail "graph TC-10: stdout's first word should be 'unchanged:', got: $out"
after9=$(cat "$plang9")
assert_eq "$before9" "$after9" \
  "graph TC-10: a second run must not change the file" || fail "file changed on rerun"

# --- graph TC-11: a ten-phase plan, a false '## Graph' replaced -------------

write_ten_phase_plan() {
  local f="$1" n
  {
    printf '# ten-phase graph fixture plan\n\n'
    printf '## Graph\n\n'
    printf '<!-- rendered by skills/implement/scripts/plan-graph — do not edit by hand -->\n\n'
    printf '```text\nthis block is false and must be replaced, not joined\n```\n\n'
    printf '## Phases\n\n'
    for n in 1 2 3 4 5 6 7 8 9 10; do
      printf '### Phase %s. Phase %s title\n\n' "$n" "$n"
      printf '**Becomes true**\n- ten_phase_%s_becomes_true\n\n' "$n"
      printf '**Changes**\n- `src/p%s.ts` — placeholder\n\n' "$n"
      if [ "$n" -eq 10 ]; then
        printf '**Depends on**\n- phase 9 — src/p9.ts, which it edits\n\n'
      else
        printf '**Depends on**\n- —\n\n'
      fi
      printf '**How**\n- plain implementation\n\n'
      printf '**Do not touch**\n- —\n\n'
      printf '**Frozen for later phases**\n- —\n\n'
      if [ "$n" -eq 10 ]; then
        printf '**Verification**\n- joins: phases 1-9\n- cases: —\n\n'
      else
        printf '**Verification**\n- proved by: phase 10\n\n'
      fi
      printf '**Steps**\n- [ ] step %s\n\n' "$n"
    done
  } > "$f"
}

dirg11=$(mktemp_dir)
plang11="$dirg11/plan.md"
write_ten_phase_plan "$plang11"

graph_headings_before=$(grep -c '^## Graph$' "$plang11")
[ "$graph_headings_before" -eq 1 ] \
  || fail "graph TC-11 test setup: fixture must start with exactly one '## Graph' heading"
grep -qF 'this block is false' "$plang11" \
  || fail "graph TC-11 test setup: the '## Graph' section must be hand-edited to something false"

run_plan_graph "$plang11"
[ "$rc" -eq 0 ] || fail "graph TC-11: plan-graph on a valid ten-phase plan should exit 0, got $rc: $out"

graph_headings_after=$(grep -c '^## Graph$' "$plang11")
[ "$graph_headings_after" -eq 1 ] \
  || fail "graph TC-11: the file should carry exactly one '## Graph' heading afterwards, got $graph_headings_after"
! grep -qF 'this block is false' "$plang11" \
  || fail "graph TC-11: the false block should have been replaced, not left in place"

grep -qF '1   --    Phase 1 title' "$plang11" \
  || fail "graph TC-11: phase 1's row should read '1   --    Phase 1 title'"
grep -qF '10  <- 9  Phase 10 title' "$plang11" \
  || fail "graph TC-11: phase 10's row should read '10  <- 9  Phase 10 title'"
grep -qF '10 phases · 9 with no dependency · longest chain: 9 -> 10' "$plang11" \
  || fail "graph TC-11: the summary line should read '10 phases · 9 with no dependency · longest chain: 9 -> 10'"

# --- graph TC-12: plan-graph refuses a plan plan-check would refuse --------
#
# The exit code and the message are the load-bearing half — the
# file-unchanged half is vacuously true of a script that does not exist yet,
# and only starts meaning something once one does.

dirg12=$(mktemp_dir)
plang12="$dirg12/plan.md"
write_graph_plan "$plang12" "$dep_none" "$dep_on_3" "$dep_none"
copy12="$dirg12/copy.md"
cp "$plang12" "$copy12"

run_plan_graph "$plang12"
[ "$rc" -eq 2 ] || fail "graph TC-12: plan-graph on a plan-check-refused plan should exit 2, got $rc: $out"
printf '%s' "$out" | grep -qi 'plan-check' \
  || fail "graph TC-12: the message should name plan-check, got: $out"
assert_eq "$(cat "$copy12")" "$(cat "$plang12")" \
  "graph TC-12: the plan file must be byte-identical to the copy" || fail "file changed"

# --- join TC-6 through join TC-11 -------------------------------------------
#
# .ai-workflow/plans/2026-09-24-the-join-and-the-tester.md's own test cases:
# check 9, which reads every phase's '**Verification**' and refuses one that
# is malformed, names no join, or names a join that does not cover it.
# Labelled 'join TC-n' throughout — this comment and every fail message —
# because this file already numbers its own cases TC-1 through TC-11 for two
# earlier plans and 'graph TC-n' for a third, and two identically prefixed
# messages in one file would let a mutation row match the wrong assertion.
#
# The smallest plan check 9 can accept is two phases: an ordinary phase names
# the join that proves it, a join's range is always earlier than the join, so
# a one-phase plan has nothing either bullet could name.

# write_join_plan FILE V1 [V2 ...] — a plan with one phase per Verification
# block given, otherwise well-formed by every other check: '## Phases', all
# eight fields on every phase, a '## Topology' table covering them all, and a
# '## Ledger'. Each Vn is the verbatim body of that phase's
# '**Verification**' field, bullets only and heading excluded; pass "" for a
# phase whose heading is there with nothing under it.
write_join_plan() {
  local f="$1"; shift
  local total=$# n=0 body
  {
    printf '# join fixture plan\n\n## Phases\n\n'
    for body in "$@"; do
      n=$((n + 1))
      printf '### Phase %s. Phase %s title\n\n' "$n" "$n"
      printf '**Becomes true**\n- join_phase_%s_becomes_true\n\n' "$n"
      printf '**Changes**\n- `src/p%s.ts` — placeholder\n\n' "$n"
      printf '**Depends on**\n- —\n\n'
      printf '**How**\n- plain implementation\n\n'
      printf '**Do not touch**\n- —\n\n'
      printf '**Frozen for later phases**\n- —\n\n'
      if [ -n "$body" ]; then
        printf '**Verification**\n%s\n\n' "$body"
      else
        printf '**Verification**\n\n'
      fi
      printf '**Steps**\n- [ ] step %s\n\n' "$n"
    done
    printf '## Topology\n\n'
    printf '| Phases | Implementer | Why the boundary is here |\n'
    printf '|---|---|---|\n'
    printf '| 1-%s | Sonnet | join_fixture_single_row |\n\n' "$total"
    printf '## Ledger\n- [ ] x\n'
  } > "$f"
}

# --- join TC-6: the form the whole tree is about to be written in ----------
#
# given: phases 1-3 each carrying a single '- proved by: phase 4' bullet, and
# phase 4 carrying '- joins: phases 1-3' and '- cases: TC-1, TC-2'.
# when: plan-check <plan> runs. then: exit 0, no finding. The over-refusal
# guard — it passes vacuously before check 9 exists, and only starts meaning
# something once one does.

dirj6=$(mktemp_dir)
planj6="$dirj6/plan.md"
write_join_plan "$planj6" \
  '- proved by: phase 4' \
  '- proved by: phase 4' \
  '- proved by: phase 4' \
  '- joins: phases 1-3
- cases: TC-1, TC-2'

run_plan_check "$planj6"
[ "$rc" -eq 0 ] || fail "join TC-6: a plan in the new grammar should exit 0, got $rc: $out"
[ -z "$out" ] || fail "join TC-6: a plan in the new grammar should print nothing, got: $out"

# --- join TC-7: a plan whose phases name no join at all --------------------
#
# given: two phases, each carrying '- cases: TC-1' and nothing else — the
# old grammar, where '**Verification**' was a list of case IDs.
# when: plan-check <plan> runs. then: exit 1, and one finding per phase,
# each naming its phase and saying a phase's '**Verification**' names the
# join that proves it.

dirj7=$(mktemp_dir)
planj7="$dirj7/plan.md"
write_join_plan "$planj7" '- cases: TC-1' '- cases: TC-1'

run_plan_check "$planj7"
[ "$rc" -eq 1 ] || fail "join TC-7: a plan naming no join should exit 1, got $rc: $out"
findings7=$(printf '%s\n' "$out" | grep -c 'Verification')
[ "$findings7" -eq 2 ] \
  || fail "join TC-7: expected one finding per phase, got $findings7: $out"
printf '%s' "$out" | grep -q 'phase 1' \
  || fail "join TC-7: a finding should name phase 1, got: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "join TC-7: a finding should name phase 2, got: $out"
printf '%s' "$out" | grep -q 'proved by' \
  || fail "join TC-7: the finding should name the join that proves the phase, got: $out"
assert_contains "$out" "- cases: TC-1" \
  "join TC-7: the finding should quote the offending bullet back" || fail "offending bullet not quoted"
assert_ends_without_reading_script "$out" \
  "join TC-7: message should end telling the reader not to open the script"

# --- join TC-8: a phase proved by a join that does not exist ---------------
#
# given: a three-phase plan whose phase 2 carries '- proved by: phase 99'.
# when: plan-check <plan> runs. then: exit 1, and the finding names phase 2
# and phase 99.

dirj8=$(mktemp_dir)
planj8="$dirj8/plan.md"
write_join_plan "$planj8" \
  '- proved by: phase 3' \
  '- proved by: phase 99' \
  '- joins: phases 1-2
- cases: —'

run_plan_check "$planj8"
[ "$rc" -eq 1 ] || fail "join TC-8: a phase proved by a phase that does not exist should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "join TC-8: the finding should name phase 2, got: $out"
printf '%s' "$out" | grep -q 'phase 99' \
  || fail "join TC-8: the finding should name phase 99, got: $out"

# --- join TC-9: the three direction faults ---------------------------------
#
# given: three plans — one where phase 3 carries '- proved by: phase 1', one
# where phase 5 carries '- joins: phases 4-6', one where a phase carries both
# '- proved by:' and '- joins:'. when: plan-check runs on each. then: exit 1
# each, with a finding naming the direction fault.

dirj9a=$(mktemp_dir)
planj9a="$dirj9a/plan.md"
write_join_plan "$planj9a" \
  '- proved by: phase 4' \
  '- proved by: phase 4' \
  '- proved by: phase 1' \
  '- joins: phases 1-3
- cases: —'

run_plan_check "$planj9a"
[ "$rc" -eq 1 ] || fail "join TC-9 (proved by an earlier phase): should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 3' \
  || fail "join TC-9 (proved by an earlier phase): the finding should name phase 3, got: $out"
printf '%s' "$out" | grep -q 'phase 1' \
  || fail "join TC-9 (proved by an earlier phase): the finding should name phase 1, got: $out"
printf '%s' "$out" | grep -qi 'later' \
  || fail "join TC-9 (proved by an earlier phase): the finding should say a join is always later than what it proves, got: $out"

dirj9b=$(mktemp_dir)
planj9b="$dirj9b/plan.md"
write_join_plan "$planj9b" \
  '- proved by: phase 6' \
  '- proved by: phase 6' \
  '- proved by: phase 6' \
  '- proved by: phase 6' \
  '- joins: phases 4-6
- cases: —' \
  '- joins: phases 1-5
- cases: —'

run_plan_check "$planj9b"
[ "$rc" -eq 1 ] || fail "join TC-9 (a join reaching past itself): should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 5' \
  || fail "join TC-9 (a join reaching past itself): the finding should name phase 5, got: $out"
assert_contains "$out" "4-6" \
  "join TC-9 (a join reaching past itself): the finding should name the range" || fail "range not named"
printf '%s' "$out" | grep -qi 'earlier' \
  || fail "join TC-9 (a join reaching past itself): the finding should say a join's range is always earlier than the join, got: $out"

dirj9c=$(mktemp_dir)
planj9c="$dirj9c/plan.md"
write_join_plan "$planj9c" \
  '- proved by: phase 3' \
  '- proved by: phase 3
- joins: phases 1-1' \
  '- joins: phases 1-2
- cases: —'

run_plan_check "$planj9c"
[ "$rc" -eq 1 ] || fail "join TC-9 (both bullets in one field): should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "join TC-9 (both bullets in one field): the finding should name phase 2, got: $out"
printf '%s' "$out" | grep -qi 'both' \
  || fail "join TC-9 (both bullets in one field): the finding should say the field carries both, got: $out"
printf '%s' "$out" | grep -qi 'one or the other' \
  || fail "join TC-9 (both bullets in one field): the finding should say a phase is one or the other, got: $out"

# --- join TC-10: a join whose range does not reach the phase naming it -----
#
# given: a plan whose phase 2 carries '- proved by: phase 6', and whose
# phase 6 carries '- joins: phases 3-5'. Phase 1 is proved by phase 3, which
# joins 1-2, so phase 2 is the only phase left outside the range that names
# it. when: plan-check <plan> runs. then: exit 1, and the finding says phase
# 6's range does not cover phase 2.

dirj10=$(mktemp_dir)
planj10="$dirj10/plan.md"
write_join_plan "$planj10" \
  '- proved by: phase 3' \
  '- proved by: phase 6' \
  '- joins: phases 1-2
- cases: —' \
  '- proved by: phase 6' \
  '- proved by: phase 6' \
  '- joins: phases 3-5
- cases: —'

run_plan_check "$planj10"
[ "$rc" -eq 1 ] || fail "join TC-10: a join whose range does not cover the phase should exit 1, got $rc: $out"
findings10=$(printf '%s\n' "$out" | grep -c 'Verification')
[ "$findings10" -eq 1 ] \
  || fail "join TC-10: only phase 2 is outside its join's range, so exactly one finding is expected, got $findings10: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "join TC-10: the finding should name phase 2, got: $out"
printf '%s' "$out" | grep -q 'phase 6' \
  || fail "join TC-10: the finding should name phase 6, got: $out"
assert_contains "$out" "3-5" \
  "join TC-10: the finding should name the range that does not cover it" || fail "range not named"
printf '%s' "$out" | grep -qi 'cover' \
  || fail "join TC-10: the finding should say the range does not cover the phase, got: $out"

# --- join TC-11: a join says which approved cases it proves ----------------
#
# given: two plans whose join phase carries '- joins: phases 1-3', one with
# no '- cases:' bullet and one with '- cases: —'. when: plan-check runs on
# each. then: the first is exit 1, naming the missing bullet; the second is
# exit 0 — the dash is the assertion that this join proves no approved case,
# the same way a dash asserts in every other field.

dirj11a=$(mktemp_dir)
planj11a="$dirj11a/plan.md"
write_join_plan "$planj11a" \
  '- proved by: phase 4' \
  '- proved by: phase 4' \
  '- proved by: phase 4' \
  '- joins: phases 1-3'

run_plan_check "$planj11a"
[ "$rc" -eq 1 ] || fail "join TC-11: a join with no '- cases:' bullet should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 4' \
  || fail "join TC-11: the finding should name phase 4, got: $out"
assert_contains "$out" "- cases:" \
  "join TC-11: the finding should name the missing '- cases:' bullet" || fail "missing bullet not named"

dirj11b=$(mktemp_dir)
planj11b="$dirj11b/plan.md"
write_join_plan "$planj11b" \
  '- proved by: phase 4' \
  '- proved by: phase 4' \
  '- proved by: phase 4' \
  '- joins: phases 1-3
- cases: —'

run_plan_check "$planj11b"
[ "$rc" -eq 0 ] || fail "join TC-11: a join whose '- cases:' is a dash should exit 0, got $rc: $out"
[ -z "$out" ] || fail "join TC-11: a join whose '- cases:' is a dash should print nothing, got: $out"

# --- an empty '**Verification**', and a join that is not one ---------------
#
# No TC-ID: two local regression tests, not approved cases of the plan. They
# cover the two of check 9's eight finding kinds that no approved case
# reaches — an empty field, and a '- proved by:' naming a phase that carries
# no '- joins:' bullet — so that neither is production code no test can move.

dirjE=$(mktemp_dir)
planjE="$dirjE/plan.md"
write_join_plan "$planjE" '' '- joins: phases 1-1
- cases: —'

run_plan_check "$planjE"
[ "$rc" -eq 1 ] || fail "empty Verification: should exit 1, got $rc: $out"
printf '%s' "$out" | grep -q 'phase 1' \
  || fail "empty Verification: the finding should name phase 1, got: $out"
printf '%s' "$out" | grep -qi 'empty' \
  || fail "empty Verification: the finding should say the field is empty, got: $out"
assert_contains "$out" "- proved by: phase <n>" \
  "empty Verification: the finding should give the shape it wanted" || fail "expected shape absent"

dirjN=$(mktemp_dir)
planjN="$dirjN/plan.md"
write_join_plan "$planjN" \
  '- proved by: phase 2' \
  '- proved by: phase 3' \
  '- joins: phases 1-2
- cases: —'

run_plan_check "$planjN"
[ "$rc" -eq 1 ] || fail "a join that is not one: should exit 1, got $rc: $out"
findings_nojoin=$(printf '%s\n' "$out" | grep -c 'Verification')
[ "$findings_nojoin" -eq 1 ] \
  || fail "a join that is not one: only phase 1 names a non-join, so exactly one finding is expected, got $findings_nojoin: $out"
printf '%s' "$out" | grep -q 'phase 1' \
  || fail "a join that is not one: the finding should name phase 1, got: $out"
printf '%s' "$out" | grep -q 'phase 2' \
  || fail "a join that is not one: the finding should name phase 2, got: $out"
assert_contains "$out" "- joins:" \
  "a join that is not one: the finding should say phase 2 carries no '- joins:' bullet" || fail "missing bullet not named"

echo "ok"
