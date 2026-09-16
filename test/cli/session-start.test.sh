#!/usr/bin/env bash
# Pins hooks/session-start: TC-17. The injected bootstrap must name the
# skills in the running host's invocation syntax. Both known hosts share
# the same syntax: the plugin-qualified `dev-skills:<name>` form — Claude
# Code's Skill tool resolves it, and so does Codex's own skill resolution.
# This was gotten wrong once: an earlier build of this file (and of the
# hook it pins) assumed Codex used a bare `<name>` with no plugin
# namespace, on the premise that Codex had no such namespace to qualify
# with. Gate B found that premise false three ways against a real Codex
# session — its `skills/list`, its own <skills_instructions> block, and a
# binding probe (`[[skills.config]] name = "grill"` does not bind,
# `"dev-skills:grill"` does) — and two live sessions reading the bare-name
# bootstrap repeated `implement`/`finish` back as instructions to run.
# Only the undetermined host (neither signal visible at all) gets the
# neutral bare form, per this phase's own How — not a form either real
# host actually uses, just the least-wrong thing to say when there is no
# host to name a form for.
#
# Host detection is stubbed the same way test/cli/harness-ready.test.sh
# stubs skills/implement/scripts/harness-ready's: a bare PATH with no codex
# and no claude for the undetermined case, a stub `codex` binary on PATH
# for the Codex case, $CLAUDECODE=1 with no codex on PATH for the Claude
# Code case. This file does not choose a different signal than that one —
# phase 7's own How pins the same two signals, in the same order.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

hook="$repo_root/hooks/session-start"

fail() {
  echo "session-start.test.sh: $1" >&2
  exit 1
}

# A PATH with no codex, no claude, and nothing this repo installed — just
# enough of the system to run the hook at all.
bare_path="/usr/bin:/bin:/usr/sbin:/sbin"

stub_bin=$(mktemp_dir)
cat > "$stub_bin/codex" <<'STUB'
#!/usr/bin/env bash
echo "codex-cli 9999.0.0"
STUB
chmod +x "$stub_bin/codex"
codex_path="$stub_bin:$bare_path"

# run_hook PATH CLAUDECODE — runs the hook with the given PATH and
# $CLAUDECODE, sets $out and $rc. CLAUDECODE unset entirely (not just
# empty) when the second argument is omitted, since the hook's own check
# is against the literal value "1".
run_hook() {
  local path="$1" claudecode="${2:-}"
  if [ -n "$claudecode" ]; then
    out=$(PATH="$path" CLAUDECODE="$claudecode" "$hook" 2>&1)
  else
    out=$(PATH="$path" env -u CLAUDECODE "$hook" 2>&1)
  fi
  rc=$?
}

# --- TC-17, Codex: the plugin-qualified form, same as Claude Code --------

run_hook "$codex_path"
assert_eq 0 "$rc" "TC-17 (codex): hook exits 0, got $rc. Output: $out" || fail "TC-17 codex exit"

case "$out" in
  *'{{SKILL:'*) fail "TC-17 (codex): an unsubstituted {{SKILL:...}} placeholder leaked into the output: $out" ;;
esac
assert_contains "$out" '`dev-skills:grill`' \
  "TC-17 (codex): expected the plugin-qualified form \`dev-skills:grill\`, not found in: $out" \
  || fail "TC-17 codex qualified grill"
assert_contains "$out" '`dev-skills:setup`' \
  "TC-17 (codex): expected the plugin-qualified form \`dev-skills:setup\`, not found in: $out" \
  || fail "TC-17 codex qualified setup"
case "$out" in
  *'`grill`'*) fail "TC-17 (codex): the bare form \`grill\` appeared — Codex uses the plugin-qualified form too: $out" ;;
esac

# --- TC-17, Claude Code: the plugin-qualified form (same form as Codex) --

run_hook "$bare_path" "1"
assert_eq 0 "$rc" "TC-17 (claude): hook exits 0, got $rc. Output: $out" || fail "TC-17 claude exit"

case "$out" in
  *'{{SKILL:'*) fail "TC-17 (claude): an unsubstituted {{SKILL:...}} placeholder leaked into the output: $out" ;;
esac
assert_contains "$out" '`dev-skills:grill`' \
  "TC-17 (claude): expected \`dev-skills:grill\`, not found in: $out" \
  || fail "TC-17 claude qualified grill"
assert_contains "$out" '`dev-skills:setup`' \
  "TC-17 (claude): expected \`dev-skills:setup\`, not found in: $out" \
  || fail "TC-17 claude qualified setup"
case "$out" in
  *'`grill`'*) fail "TC-17 (claude): the bare form \`grill\` leaked — Claude Code always uses the plugin-qualified form: $out" ;;
esac

# --- TC-17, undetermined: neither signal visible — the neutral bare form -

run_hook "$bare_path"
assert_eq 0 "$rc" "TC-17 (undetermined): hook exits 0 rather than refusing to produce a bootstrap at all, got $rc. Output: $out" || fail "TC-17 undetermined exit"

case "$out" in
  *'{{SKILL:'*) fail "TC-17 (undetermined): an unsubstituted {{SKILL:...}} placeholder leaked into the output: $out" ;;
esac
assert_contains "$out" '`grill`' \
  "TC-17 (undetermined): expected the neutral bare form \`grill\`, not found in: $out" \
  || fail "TC-17 undetermined bare grill"
case "$out" in
  *'dev-skills:'*) fail "TC-17 (undetermined): should not guess Claude Code's prefixed form when the host can't be determined: $out" ;;
esac

# --- TC-17, both signals present: still the plugin-qualified form --------
#
# A session with both $CLAUDECODE=1 and a codex CLI on PATH is genuinely on
# one host or the other, never neither. Both real hosts now share the same
# `dev-skills:<name>` form (see the header above), so this case can no
# longer distinguish *which* branch of $host fired the way an earlier
# version of this file did when the two hosts disagreed — that made it a
# precedence probe for this file; it no longer can be, now that the
# premise it relied on is fixed. What it still proves: a session where a
# real host actually is detected never falls through to the undetermined
# branch's bare form. $CLAUDECODE-outranks-codex-on-PATH itself is pinned
# by skills/implement/scripts/harness-ready's own tests, not this file's.

run_hook "$codex_path" "1"
assert_eq 0 "$rc" "TC-17 (both signals): hook exits 0, got $rc. Output: $out" || fail "TC-17 both exit"

case "$out" in
  *'{{SKILL:'*) fail "TC-17 (both signals): an unsubstituted {{SKILL:...}} placeholder leaked into the output: $out" ;;
esac
assert_contains "$out" '`dev-skills:grill`' \
  "TC-17 (both signals): expected the plugin-qualified form \`dev-skills:grill\`, not found in: $out" \
  || fail "TC-17 both qualified grill"
case "$out" in
  *'`grill`'*) fail "TC-17 (both signals): the bare form \`grill\` leaked even though a real host was detected: $out" ;;
esac

exit 0
