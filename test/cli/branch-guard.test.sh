#!/usr/bin/env bash
# Pins hooks/branch-guard.sh's handling of an apply_patch payload: TC-4
# through TC-7. The pre-existing Edit/Write/Bash branches are untouched by
# this plan and are not re-pinned here.
#
# A denial never changes the hook's own exit code — every path through
# branch-guard.sh ends in `exit 0`; a deny is signalled by
# hookSpecificOutput.permissionDecision in stdout, never by the process exit
# status. Every assertion below checks stdout for that reason.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/lib/gitfixture.sh"

hook="$repo_root/hooks/branch-guard.sh"

fail() {
  echo "branch-guard.test.sh: $1" >&2
  exit 1
}

# a guarded repository, on its default branch (main, per gitfixture_new)
repo=$(gitfixture_new)
: > "$repo/.branch-guard"

# run_hook TOOL COMMAND — feeds branch-guard.sh the apply_patch payload
# Claude/Codex would, from inside the repo (so its "." cwd resolution finds
# the same git root the Bash branch already relies on). Sets $out and $rc.
run_hook() {
  local tool="$1" cmd="$2" payload
  payload=$(python3 - "$tool" "$cmd" <<'PY'
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))
PY
)
  out=$(cd "$repo" && printf '%s' "$payload" | "$hook")
  rc=$?
}

is_denied() {
  case "$out" in
    *'"permissionDecision":"deny"'*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- TC-4: adds an exempt path first, updates a protected path second ------
# then: it denies

patch_tc4=$(cat <<'EOF'
*** Begin Patch
*** Add File: CONTEXT.md
+hello
*** Update File: src/protected.txt
@@
-old
+new
*** End Patch
EOF
)

run_hook apply_patch "$patch_tc4"
assert_eq 0 "$rc" "TC-4: the hook itself still exits 0" || fail "TC-4 exit"
is_denied || fail "TC-4: a patch that also touches a protected path (src/protected.txt) should deny, got: $out"

# --- TC-5: touches only exempt paths ----------------------------------------
# then: it exits 0 and emits nothing

patch_tc5=$(cat <<'EOF'
*** Begin Patch
*** Add File: CONTEXT.md
+hello
*** Add File: docs/adr/0001-example.md
+adr body
*** Update File: .ai-workflow/notes.md
@@
-old
+new
*** End Patch
EOF
)

run_hook apply_patch "$patch_tc5"
assert_eq 0 "$rc" "TC-5: hook exits 0" || fail "TC-5 exit"
assert_eq "" "$out" "TC-5: a patch touching only exempt paths should emit nothing, got: $out" || fail "TC-5 output"

# --- TC-6: *** Move to: destination is protected, source is exempt ---------
# then: it denies

patch_tc6=$(cat <<'EOF'
*** Begin Patch
*** Update File: docs/adr/0001-old.md
*** Move to: src/protected-renamed.txt
@@
-old
+new
*** End Patch
EOF
)

run_hook apply_patch "$patch_tc6"
assert_eq 0 "$rc" "TC-6: the hook itself still exits 0" || fail "TC-6 exit"
is_denied || fail "TC-6: a move whose destination (src/protected-renamed.txt) is protected should deny, got: $out"

# --- TC-7: robustness of the path extraction --------------------------------
# then: every one of those paths is judged, and none is silently skipped.
# Each property is isolated in its own patch so a failure names exactly
# which form broke extraction, rather than one pass/fail bit covering all
# four at once.

# TC-7a: a path with a space, alone and protected — must still be judged.
patch_tc7a=$(cat <<'EOF'
*** Begin Patch
*** Add File: src/needs a space.txt
+content
*** End Patch
EOF
)
run_hook apply_patch "$patch_tc7a"
assert_eq 0 "$rc" "TC-7a: the hook itself still exits 0" || fail "TC-7a exit"
is_denied || fail "TC-7a: a protected path containing a space must not be silently skipped, got: $out"

# TC-7b: an absolute path, alone and protected — must still be judged.
patch_tc7b=$(cat <<'EOF'
*** Begin Patch
*** Add File: /var/tmp/dev-skills-fixture/src/protected.txt
+content
*** End Patch
EOF
)
run_hook apply_patch "$patch_tc7b"
assert_eq 0 "$rc" "TC-7b: the hook itself still exits 0" || fail "TC-7b exit"
is_denied || fail "TC-7b: a protected path given in absolute form must not be silently skipped, got: $out"

# TC-7c: a repository-relative path, alone and protected — must still be
# judged (the plain counterpart to TC-7b, both named by the case).
patch_tc7c=$(cat <<'EOF'
*** Begin Patch
*** Add File: src/protected-relative.txt
+content
*** End Patch
EOF
)
run_hook apply_patch "$patch_tc7c"
assert_eq 0 "$rc" "TC-7c: the hook itself still exits 0" || fail "TC-7c exit"
is_denied || fail "TC-7c: a protected path given in repository-relative form must not be silently skipped, got: $out"

# TC-7d: a CRLF-terminated payload, touching only an exempt path (CONTEXT.md).
# This is the case the plan's own How section names directly: a trailing \r
# left on the extracted path turns "CONTEXT.md\r" into a string that no
# longer matches the exact "CONTEXT.md" exemption, so an un-stripped \r would
# make this exempt file look protected and wrongly deny.
crlf_patch=$(python3 -c "
import sys
lines = ['*** Begin Patch', '*** Add File: CONTEXT.md', '+hello', '*** End Patch']
sys.stdout.write('\r\n'.join(lines) + '\r\n')
")
run_hook apply_patch "$crlf_patch"
assert_eq 0 "$rc" "TC-7d: the hook itself still exits 0" || fail "TC-7d exit"
assert_eq "" "$out" "TC-7d: a CRLF-terminated patch touching only CONTEXT.md must not be misread as protected by a stray carriage return, got: $out" || fail "TC-7d output"

exit 0
