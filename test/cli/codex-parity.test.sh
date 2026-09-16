#!/usr/bin/env bash
# Repository-wide Codex-parity invariants, checked by grepping the tree
# rather than driving a process — the seam the plan's *Test seams* section
# names for this shape of case.
#
# TC-1  every skill directory holds agents/openai.yaml with a non-empty
#       interface.display_name and interface.short_description
# TC-2  the disable-model-invocation / policy.allow_implicit_invocation
#       correspondence, and user-invocable is the only unmatched flag
# TC-3  the plugin manifest and the marketplace manifest agree
# TC-9  hooks/hooks.json's SessionStart matcher includes resume
# TC-16 no model name anywhere in skills/, agents/, references/, hooks/
# TC-18 (cache-path half only — the scripts/check half is phase 8's, not
#       written here): no path under .claude/plugins/cache anywhere in the
#       tree
# TC-19 every instruction that dispatches one of the five roles names both
#       the Claude subagent type and the literal Codex agent_type, and the
#       SETUP_REQUIRED stop is documented
# PROBE-DRIVEN (added in fix round 1, gate A BLOCKER — not one of the plan's
#       numbered cases): implement and finish actually drive the reserved
#       hook probe (DEV_SKILLS_HOOK_PROBE / DEV_SKILLS_HOOK_READY) phase 3's
#       harness-ready deliberately leaves to the orchestrator's own prose
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

fail() {
  echo "codex-parity.test.sh: $1" >&2
  exit 1
}

cd "$repo_root"

# --- small local YAML helpers — two keys deep, grep/sed rather than a parser,
# per phase 1's How. Not a shared assertion library: this is parsing local to
# this one file's own cases. -------------------------------------------------

# yaml_nested_scalar FILE TOP SUB -> the value of SUB under a "TOP:" block,
# where SUB is indented under it; stops at the next unindented line.
# The awk variable is named subkey, never sub — sub() is awk's own builtin
# substitution function, and a variable named sub collides with it.
yaml_nested_scalar() {
  local file="$1" top="$2" subkey="$3"
  awk -v top="$top" -v subkey="$subkey" '
    $0 ~ "^"top":[[:space:]]*$" { intop = 1; next }
    intop && /^[^[:space:]]/ { intop = 0 }
    intop && $0 ~ "^[[:space:]]+"subkey":" {
      line = $0
      sub("^[[:space:]]+" subkey ":[[:space:]]*", "", line)
      print line
      exit
    }
  ' "$file" 2>/dev/null
}

yaml_has_top_key() {
  grep -qE "^$2:" "$1" 2>/dev/null
}

strip_quotes() {
  local v="$1"
  v="${v%\"}"; v="${v#\"}"
  v="${v%\'}"; v="${v#\'}"
  printf '%s' "$v"
}

# frontmatter_keys FILE -> one SKILL.md top-level frontmatter key per line
frontmatter_keys() {
  awk '
    /^---$/ { c++; next }
    c == 1 && /^[A-Za-z_-]+:/ { sub(/:.*/, ""); print }
  ' "$1" 2>/dev/null
}

skill_dirs() {
  find skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort
}

# --- TC-1: every skill directory holds agents/openai.yaml with a non-empty
# interface.display_name and interface.short_description --------------------

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  skill=$(basename "$dir")
  meta="$dir/agents/openai.yaml"
  [ -f "$meta" ] || fail "TC-1: $skill has no agents/openai.yaml"

  dn="$(strip_quotes "$(yaml_nested_scalar "$meta" "interface" "display_name")")"
  [ -n "$dn" ] || fail "TC-1: $skill's openai.yaml has no non-empty interface.display_name"

  sd="$(strip_quotes "$(yaml_nested_scalar "$meta" "interface" "short_description")")"
  [ -n "$sd" ] || fail "TC-1: $skill's openai.yaml has no non-empty interface.short_description"
done < <(skill_dirs)

# --- TC-2: the invocation-flag correspondence -------------------------------
#
# The flags this check knows about — enumerated, not discovered, so a third
# invocation flag added later fails loudly instead of quietly becoming an
# unmatched difference nobody declared. `user-invocable` is deliberately
# never required to have a Codex counterpart below: it is the one flag the
# plan's Constraints section names as irreducible.

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  skill=$(basename "$dir")
  sk="$dir/SKILL.md"
  meta="$dir/agents/openai.yaml"
  [ -f "$sk" ] || continue

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case "$key" in
      name|description|disable-model-invocation|user-invocable) : ;;
      *) fail "TC-2: $skill/SKILL.md carries a frontmatter key '$key' the invocation-flag check does not recognise" ;;
    esac
  done < <(frontmatter_keys "$sk")

  if grep -qE '^disable-model-invocation:[[:space:]]*true' "$sk" 2>/dev/null; then
    allow="$(strip_quotes "$(yaml_nested_scalar "$meta" "policy" "allow_implicit_invocation")")"
    assert_eq "false" "$allow" \
      "TC-2: $skill has disable-model-invocation: true; its openai.yaml's policy.allow_implicit_invocation should be false, got '$allow'" \
      || fail "TC-2 policy mismatch: $skill"
  else
    if [ -f "$meta" ] && yaml_has_top_key "$meta" "policy"; then
      fail "TC-2: $skill has no disable-model-invocation flag, but its openai.yaml carries a policy: block anyway"
    fi
  fi
done < <(skill_dirs)

# --- TC-3: the plugin manifest and the marketplace manifest agree ----------

plugin_json="$repo_root/.claude-plugin/plugin.json"
marketplace_json="$repo_root/.claude-plugin/marketplace.json"

p_name="$(jq -r '.name' "$plugin_json")"
p_version="$(jq -r '.version' "$plugin_json")"

entries="$(jq -c '[.plugins[] | select(.source == "." or .source == "./")]' "$marketplace_json")"
entry_count="$(printf '%s' "$entries" | jq 'length')"
assert_eq "1" "$entry_count" \
  "TC-3: expected exactly one marketplace entry with source . or ./, found $entry_count" \
  || fail "TC-3 entry count"

m_name="$(printf '%s' "$entries" | jq -r '.[0].name')"
m_version="$(printf '%s' "$entries" | jq -r '.[0].version')"
assert_eq "$p_name" "$m_name" "TC-3: marketplace entry's name must equal the plugin manifest's" || fail "TC-3 name"
assert_eq "$p_version" "$m_version" "TC-3: marketplace entry's version must equal the plugin manifest's" || fail "TC-3 version"

# --- TC-9: hooks/hooks.json's SessionStart matcher also matches resume -----

hooks_json="$repo_root/hooks/hooks.json"
matcher="$(jq -r '.hooks.SessionStart[0].matcher' "$hooks_json")"
assert_contains "$matcher" "resume" "TC-9: SessionStart matcher '$matcher' should also match resume" || fail "TC-9 resume"
for m in startup clear compact; do
  assert_contains "$matcher" "$m" "TC-9: SessionStart matcher '$matcher' should still match $m" || fail "TC-9 regressed $m"
done

# --- TC-16: no model name anywhere it is documented -------------------------

model_matches="$(grep -rniE '\b(sonnet|opus|haiku|fable)\b' skills agents references hooks 2>/dev/null || true)"
assert_eq "" "$model_matches" \
  "TC-16: expected no model names in skills/, agents/, references/ or hooks/, found:
$model_matches" \
  || fail "TC-16"

# --- TC-18 (cache-path half): no path resolves through the plugin cache ----

cache_matches="$(grep -rn '\.claude/plugins/cache' skills hooks agents references scripts README.md 2>/dev/null || true)"
assert_eq "" "$cache_matches" \
  "TC-18 (cache-path half): expected no path under .claude/plugins/cache, found:
$cache_matches" \
  || fail "TC-18 cache-path"

# --- TC-18 (scripts/check half): the Codex-side validation actually runs ---
#
# Drives the real scripts/check rather than asserting on its source text, the
# same seam TC-9 above already uses. Two sides: codex absent is reported (not
# silently skipped, the rule the file already applies to claude), and codex
# present is a real pass whose own step is visible in the output.

check_script="$repo_root/scripts/check"
bare_path="/usr/bin:/bin:/usr/sbin:/sbin"

# check-links.py needs a python3 that actually runs — not just "no codex, no
# claude". Same convention harness-ready.test.sh's TC-21 uses: add the ambient
# python3's own directory alongside bare_path, never bare_path alone.
python3_dir="$(dirname "$(command -v python3)")"
no_codex_path="$python3_dir:$bare_path"

check_out_noc="$(PATH="$no_codex_path" "$check_script" 2>&1)"
check_rc_noc=$?
assert_eq "1" "$check_rc_noc" \
  "TC-18 (scripts/check half): with no codex on PATH, scripts/check should exit 1 (reported, not silently skipped), got $check_rc_noc. Output: $check_out_noc" \
  || fail "TC-18 codex-absent exit"
check_out_noc_lower="$(printf '%s' "$check_out_noc" | tr '[:upper:]' '[:lower:]')"
assert_contains "$check_out_noc_lower" "'codex' is not on path" \
  "TC-18 (scripts/check half): the failure should name codex missing from PATH, got: $check_out_noc" \
  || fail "TC-18 codex-absent message"

command -v codex >/dev/null 2>&1 \
  || fail "TC-18 (scripts/check half): this case needs a real 'codex' on PATH to prove the validation actually runs, none found"

check_out="$("$check_script" 2>&1)"
check_rc=$?
assert_eq "0" "$check_rc" \
  "TC-18 (scripts/check half): scripts/check should pass with codex present, got $check_rc. Output: $check_out" \
  || fail "TC-18 codex-present exit"
assert_contains "$check_out" "codex plugin add" \
  "TC-18 (scripts/check half): the Codex-side validator's own step should be visible in the output, not silently skipped — got: $check_out" \
  || fail "TC-18 codex-present ran"

# --- TC-19: every role dispatch names both harnesses' forms, and the
# SETUP_REQUIRED stop is documented rather than a silent fallback -----------

implement_md="$repo_root/skills/implement/SKILL.md"
finish_md="$repo_root/skills/finish/SKILL.md"
moments_md="$repo_root/skills/plan/references/moments.md"

# check_dispatch_pair FILE CLAUDE_FORM CODEX_AGENT_TYPE LABEL — CLAUDE_FORM
# pins that the file still dispatches this role at all (so a rewrite that
# drops the role entirely fails loudly rather than vacuously passing), and
# CODEX_AGENT_TYPE pins that its literal Codex agent_type is named in the
# same file.
check_dispatch_pair() {
  local file="$1" claude_form="$2" codex_form="$3" label="$4"
  [ -f "$file" ] || fail "TC-19: $file does not exist"
  grep -qF -- "$claude_form" "$file" \
    || fail "TC-19: $file no longer names $label ('$claude_form') — this case needs updating alongside the prose, not silently passing"
  grep -qF -- "$codex_form" "$file" \
    || fail "TC-19: $file dispatches $label but never names its Codex agent_type ('$codex_form')"
}

check_dispatch_pair "$implement_md" "gate A" "dev-skills-gate-a" "gate A"
check_dispatch_pair "$implement_md" "gate B" "dev-skills-gate-b" "gate B"
check_dispatch_pair "$implement_md" "the implementer" "dev-skills-implementer" "the implementer"
check_dispatch_pair "$implement_md" "dev-skills:test-writer" "dev-skills-test-writer" "the test writer"
check_dispatch_pair "$moments_md" "dev-skills:prototyper" "dev-skills-prototyper" "the prototyper"

grep -q "SETUP_REQUIRED" "$implement_md" || fail "TC-19: $implement_md never states the SETUP_REQUIRED stop"
grep -q "SETUP_REQUIRED" "$finish_md" || fail "TC-19: $finish_md never states the SETUP_REQUIRED stop"

# --- PROBE-DRIVEN: the readiness step actually drives the reserved hook
# probe, the only proof commit-guard.sh's diagnostic branch (phase 3) is
# live — harness-ready's own comment says exactly this is deliberately not
# attempted by static inspection, so the orchestration prose is the only
# place it can be driven from. Fixed for gate A's BLOCKER in fix round 1. ---

for f in "$implement_md" "$finish_md"; do
  grep -q "DEV_SKILLS_HOOK_PROBE" "$f" \
    || fail "PROBE-DRIVEN: $f never names the DEV_SKILLS_HOOK_PROBE command — the live probe harness-ready relies on is never driven"
  grep -q "DEV_SKILLS_HOOK_READY" "$f" \
    || fail "PROBE-DRIVEN: $f names the probe but never the DEV_SKILLS_HOOK_READY reply the denial must carry"
done

exit 0
