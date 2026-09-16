#!/usr/bin/env bash
# PreToolUse guard: in opt-in repos (a `.branch-guard` file at the repo root),
# deny file mutations and git commits while on the default branch, forcing a
# dedicated branch/worktree first. Fail-open on any uncertainty.
#
# Exception: the domain docs — CONTEXT.md and docs/adr/** — are always allowed.
# Domain knowledge belongs on the main line, and the human may ask for it to be
# recorded while standing on the default branch. Nothing writes these on its own
# any more: dev-skills:domain-modeling offers, the human decides, and this exemption only
# means the guard does not stand in the way once they have.
#
# Exception: .ai-workflow/** — git-ignored scratch (epics, plans, run
# workspaces). The grilling and the plan are written before the branch exists, and
# nothing under there can reach a commit, so blocking them buys no isolation.

input="$(cat 2>/dev/null || true)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"

# A repo-relative or absolute path the guard always allows: a domain doc, or
# anything under the git-ignored .ai-workflow/ scratch tree.
is_doc_path() {
  case "$1" in
    CONTEXT.md|*/CONTEXT.md|docs/adr/*|*/docs/adr/*) return 0 ;;
    .ai-workflow/*|*/.ai-workflow/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Every path an apply_patch body names — Add/Update/Delete File, and the
# destination of a Move to (a move's own header line is an Update File, so
# its source is already covered) — one per line. A trailing \r is stripped
# so a CRLF-terminated payload does not turn "CONTEXT.md\r" into a path that
# no longer matches the exempt-path patterns above.
extract_patch_paths() {
  printf '%s' "$1" | tr -d '\r' | sed -n \
    -e 's/^\*\*\* Add File: \(.*\)$/\1/p' \
    -e 's/^\*\*\* Update File: \(.*\)$/\1/p' \
    -e 's/^\*\*\* Delete File: \(.*\)$/\1/p' \
    -e 's/^\*\*\* Move to: \(.*\)$/\1/p'
}

case "$tool" in
  Edit|MultiEdit|Write|NotebookEdit)
    path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null || true)"
    is_doc_path "$path" && exit 0
    dir="$(dirname "$path" 2>/dev/null || true)"; [ -d "$dir" ] || dir="."
    ;;
  apply_patch)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
    protected=0
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      is_doc_path "$p" || protected=1
    done <<PATCH_PATHS
$(extract_patch_paths "$cmd")
PATCH_PATHS
    [ "$protected" -eq 1 ] || exit 0
    dir="."
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
    printf '%s' "$cmd" | grep -qE 'git[[:space:]]+commit' || exit 0
    dir="."
    # Allow a commit whose staged changes are all domain docs.
    droot="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$droot" ]; then
      staged="$(git -C "$droot" diff --cached --name-only 2>/dev/null || true)"
      if [ -n "$staged" ] && ! printf '%s\n' "$staged" | grep -qvE '(^|/)CONTEXT\.md$|(^|/)docs/adr/'; then
        exit 0
      fi
    fi
    ;;
  *) exit 0 ;;
esac

root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$root" ] && exit 0
[ -f "$root/.branch-guard" ] || exit 0

branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ -z "$branch" ] && exit 0
[ "$branch" = "HEAD" ] && exit 0

def="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
if [ -z "$def" ]; then
  if git -C "$root" show-ref --verify --quiet refs/heads/main 2>/dev/null; then def="main"
  elif git -C "$root" show-ref --verify --quiet refs/heads/master 2>/dev/null; then def="master"
  else def="main"; fi
fi

if [ "$branch" = "$def" ]; then
  jq -cn --arg b "$branch" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Blocked: on the default branch (" + $b + ") in a dev-skills repo. Work is isolated first — dev-skills:implement settles that at its first step, offering a worktree, a branch here, or the current branch. Enforced, not advised. (CONTEXT.md, docs/adr/ and .ai-workflow/ are exempt.)")}}' \
    2>/dev/null
fi
exit 0
