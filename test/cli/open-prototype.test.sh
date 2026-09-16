#!/usr/bin/env bash
# Pins hooks/open-prototype.sh: a Write of a .html file under a prototypes/
# directory opens it, and nothing else does. The opener is stubbed through
# DEV_SKILLS_OPEN_CMD so the test proves the call without a browser.
#
# TC-1 through TC-6 below are this file's own long-standing local numbering,
# unrelated to the codex-parity plan's case IDs. TC-8 at the bottom is that
# plan's own case — a prototype written by apply_patch rather than Write.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

hook="$repo_root/hooks/open-prototype.sh"

fail() {
  echo "open-prototype.test.sh: $1" >&2
  exit 1
}

tmp=$(mktemp_dir)
log="$tmp/opened.log"
stub="$tmp/opener"
cat > "$stub" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$log"
STUB
chmod +x "$stub"

proto_dir="$tmp/.ai-workflow/plans/2026-08-27-demo/prototypes"
mkdir -p "$proto_dir"
proto="$proto_dir/M-1.html"
printf '<h1>M-1</h1>\n' > "$proto"

# run_hook TOOL PATH — feeds the hook the JSON Claude Code would and sets
# $rc. The hook backgrounds the opener so it never holds Claude Code up,
# which means the stub's write lands some time after the hook has returned:
# the positive case polls for it (opened_within). The negative cases need no
# wait — every path that declines exits before anything is forked, so an
# empty log the instant the hook returns is exact, not lucky.
run_hook() {
  : > "$log"
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" \
    | DEV_SKILLS_OPEN_CMD="$stub" "$hook"
  rc=$?
}

opened_within() {
  local i
  for i in $(seq 1 40); do
    [ -s "$log" ] && return 0
    sleep 0.05
  done
  return 1
}

# TC-1: a Write of a prototype .html opens exactly that file.
run_hook Write "$proto"
assert_eq 0 "$rc" "TC-1: hook exits 0" || fail "TC-1"
opened_within || fail "TC-1: opener never called"
assert_eq "$proto" "$(cat "$log")" "TC-1: opener called with the prototype path" || fail "TC-1"

# TC-2: an Edit of the same file does not open it again.
run_hook Edit "$proto"
assert_eq 0 "$rc" "TC-2: hook exits 0" || fail "TC-2"
assert_eq "" "$(cat "$log")" "TC-2: opener not called on Edit" || fail "TC-2"

# TC-3: a Write of an .html outside prototypes/ is ignored.
other="$tmp/.ai-workflow/plans/2026-08-27-demo/report.html"
printf '<h1>report</h1>\n' > "$other"
run_hook Write "$other"
assert_eq 0 "$rc" "TC-3: hook exits 0" || fail "TC-3"
assert_eq "" "$(cat "$log")" "TC-3: opener not called outside prototypes/" || fail "TC-3"

# TC-4: a Write of a non-.html under prototypes/ is ignored.
notes="$proto_dir/notes.md"
printf 'notes\n' > "$notes"
run_hook Write "$notes"
assert_eq 0 "$rc" "TC-4: hook exits 0" || fail "TC-4"
assert_eq "" "$(cat "$log")" "TC-4: opener not called for non-html" || fail "TC-4"

# TC-5: a path that does not exist on disk is ignored — nothing to open.
run_hook Write "$proto_dir/M-9.html"
assert_eq 0 "$rc" "TC-5: hook exits 0" || fail "TC-5"
assert_eq "" "$(cat "$log")" "TC-5: opener not called for a missing file" || fail "TC-5"

# TC-6: garbage on stdin is fail-open — exit 0, no opener.
: > "$log"
printf 'not json' | DEV_SKILLS_OPEN_CMD="$stub" "$hook"
assert_exit 0 "TC-6: hook exits 0 on unparseable input" || fail "TC-6"
assert_eq "" "$(cat "$log")" "TC-6: opener not called on garbage" || fail "TC-6"

# run_hook_patch PATH — feeds the hook an apply_patch payload whose body adds
# PATH, the same shape Codex's own patch tool would send, rather than the
# Write-shaped tool_input the run_hook helper above builds.
run_hook_patch() {
  local path="$1" payload
  : > "$log"
  payload=$(python3 - "$path" <<'PY'
import json, sys
path = sys.argv[1]
patch = "*** Begin Patch\n*** Add File: " + path + "\n+<h1>M-1</h1>\n*** End Patch"
print(json.dumps({"tool_name": "apply_patch", "tool_input": {"command": patch}}))
PY
)
  printf '%s' "$payload" | DEV_SKILLS_OPEN_CMD="$stub" "$hook"
  rc=$?
}

# TC-8: a prototype written by apply_patch rather than Write is still opened.
run_hook_patch "$proto"
assert_eq 0 "$rc" "TC-8: hook exits 0" || fail "TC-8"
opened_within || fail "TC-8: opener never called for a prototype written by apply_patch"
assert_eq "$proto" "$(cat "$log")" "TC-8: opener called with the prototype's path" || fail "TC-8"

exit 0
