# Explicit consent for throwaway fixtures; production approval tests use cli directly.
approve_plan() {
  local consent_plan="$1" consent_summary="${1%.md}.summary.md" validation
  validation=$(cli approve "$@") || { printf '%s\n' "$validation"; return 1; }
  [ -f "${consent_plan%.md}.run.toml" ] || { printf '%s\n' "$validation"; return 0; }
  cli run approve "$consent_plan" --by user --words 'Fixture run approved' || return
  printf 'Build [this plan](%s) through its phases, Spec and checks. Limits are in the plan.\n' "$(basename "$consent_plan")" > "$consent_summary"
  cli summary approve "$consent_plan" --file "$consent_summary" --by user --words 'Fixture summary approved' >/dev/null || return
  printf '%s\n' "$validation"
}
