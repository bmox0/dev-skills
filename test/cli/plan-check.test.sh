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

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc1_phase_one_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc1_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc1_phase_two_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc1_phase_three_becomes_true

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

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc2_phase_one_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc2_phase_two_becomes_true

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
- tc2_phase_three_becomes_true

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

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc3_phase_one_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step one

### Phase 2. Second phase title

**Becomes true**
- tc3_phase_two_becomes_true

**Changes**
- `src/two.ts` — placeholder

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `tc3_phase_two_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step two

### Phase 3. Third phase title

**Becomes true**
- tc3_phase_three_becomes_true

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
  local f="$1" nums="$2" rng="$3" n fld
  {
    printf '# numbered\n\n## Phases\n\n'
    for n in $nums; do
      printf '### Phase %s. p%s\n\n' "$n" "$n"
      for fld in "Becomes true" "Changes" "How" "Do not touch" \
                 "Frozen for later phases" "Verification" "Steps"; do
        printf '**%s**\n- x\n\n' "$fld"
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

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- `mode_phase_one_frozen` — placeholder

**Verification**
- cases: —

**Steps**
- [ ] step one
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
# '## Phases', one phase carrying all seven fields, a covering
# '## Topology' table, a '## Ledger' — so that only the moments rule under
# test can move the exit code or the findings.

# write_moments_plan FILE BLOCK — BLOCK becomes the verbatim body of
# '## Moments'; pass "" to omit the heading entirely (TC-5).
write_moments_plan() {
  local f="$1" block="$2" fld
  {
    printf '# moments fixture\n\n'
    if [ -n "$block" ]; then
      printf '## Moments\n\n%s\n\n' "$block"
    fi
    printf '## Phases\n\n### Phase 1. First phase title\n\n'
    for fld in "Becomes true" "Changes" "How" "Do not touch" \
               "Frozen for later phases" "Verification" "Steps"; do
      printf '**%s**\n- x\n\n' "$fld"
    done
    printf '## Topology\n\n'
    printf '| Phases | Implementer | Why the boundary is here |\n'
    printf '|---|---|---|\n'
    printf '| 1 | Sonnet | one |\n\n'
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

echo "ok"
