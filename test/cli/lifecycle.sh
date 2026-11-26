# Explicit consent for throwaway fixtures; production approval tests use cli directly.
approve_plan() {
  local consent_plan="$1" validation
  validation=$(cli approve "$@") || { printf '%s\n' "$validation"; return 1; }
  [ -f "${consent_plan%.md}.run.toml" ] || { printf '%s\n' "$validation"; return 0; }
  local consent
  consent=$(approve_revision "$consent_plan") || { printf '%s\n' "$consent"; return 1; }
  printf '%s\n' "$consent" | sed -n '/^facts: /p'
  printf '%s\n' "$validation"
}

approve_revision() {
  local revision
  revision=$(cli plan review "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])') || return
  cli plan approve "$1" --revision "$revision" --by 'Fixture Human' --words 'Fixture plan and run approved'
}

report_phase() {
  cli phase report "$@" --check scripts/check 'failed: scripts/check is missing in the throwaway repository'
}

complete_review() {
  local review_brief review_command
  review_brief=$(cli brief reviewer "$@") || return
  review_command=$(sed -n 's/^- Complete the review: //p' "$review_brief")
  [[ -n "$review_command" ]] && bash -c "$review_command" >/dev/null
}
