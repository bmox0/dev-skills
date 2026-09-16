#!/usr/bin/env bash
# Pins hooks/commit-guard.sh's diagnostic branch: TC-10. The reserved probe
# command lets a run prove the guard is actually live, without touching any
# of commit-guard.sh's other rules — this file adds only that one case.
#
# This test never executes the probe command itself; it only feeds the hook
# the same JSON payload the harness would and reads the hook's own response.
# Denial happening here at all is what proves the underlying command never
# ran — a PreToolUse hook that denies is exactly what stops the tool call
# from reaching the shell in the first place.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

hook="$repo_root/hooks/commit-guard.sh"

fail() {
  echo "commit-guard.test.sh: $1" >&2
  exit 1
}

# run_hook COMMAND — feeds commit-guard.sh a Bash PreToolUse payload carrying
# COMMAND as tool_input.command. Sets $out and $rc.
run_hook() {
  local cmd="$1" payload
  payload=$(python3 - "$cmd" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
PY
)
  out=$(printf '%s' "$payload" | "$hook")
  rc=$?
}

# --- TC-10: the reserved probe command, carrying a nonce -------------------

nonce="dev-skills-probe-$$-$RANDOM"
probe_cmd="printf '%s\n' 'DEV_SKILLS_HOOK_PROBE:${nonce}'"

run_hook "$probe_cmd"
assert_eq 0 "$rc" "TC-10: the hook itself still exits 0" || fail "TC-10 exit"

case "$out" in
  *'"permissionDecision":"deny"'*) : ;;
  *) fail "TC-10: the probe command should be denied, got: $out" ;;
esac

assert_contains "$out" "DEV_SKILLS_HOOK_READY:${nonce}" \
  "TC-10: the deny reason should contain the nonce marker DEV_SKILLS_HOOK_READY:${nonce}, got: $out" \
  || fail "TC-10 nonce"

exit 0
