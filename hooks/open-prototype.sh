#!/usr/bin/env bash
# PostToolUse hook: the moment a prototype is written to disk, open it in the
# browser. The prototyper draws `.ai-workflow/plans/<plan>/prototypes/M-<n>.html`
# as a self-contained file that opens straight from disk, and the human used to
# have to ask for it to be opened every time. Now it just is.
#
# Fires on a Write, or an apply_patch whose body adds/updates one, whose
# path is a .html file under a prototypes/ directory. Anything else —
# another tool, another path — exits silently. Never blocks: the file is
# already written by the time this runs, and a missing opener is not the
# model's problem.
#
# DEV_SKILLS_OPEN_CMD overrides the opener (a browser of choice, or a stub
# under test). Without it: `open` on macOS, `xdg-open` elsewhere, nothing if
# neither is there.

input="$(cat 2>/dev/null || true)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"

# Every path an apply_patch body names — Add/Update/Delete File, and the
# destination of a Move to. Kept local rather than shared with
# branch-guard.sh's copy: two hooks, a dozen lines each, and a sourced file
# would have to resolve its own path in both harnesses.
extract_patch_paths() {
  printf '%s' "$1" | tr -d '\r' | sed -n \
    -e 's/^\*\*\* Add File: \(.*\)$/\1/p' \
    -e 's/^\*\*\* Update File: \(.*\)$/\1/p' \
    -e 's/^\*\*\* Delete File: \(.*\)$/\1/p' \
    -e 's/^\*\*\* Move to: \(.*\)$/\1/p'
}

case "$tool" in
  Write)
    paths="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
    ;;
  apply_patch)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
    paths="$(extract_patch_paths "$cmd")"
    ;;
  *) exit 0 ;;
esac

opener=""
while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    */prototypes/*.html) ;;
    *) continue ;;
  esac
  [ -f "$path" ] || continue

  if [ -z "$opener" ]; then
    if [ -n "${DEV_SKILLS_OPEN_CMD:-}" ]; then
      opener="$DEV_SKILLS_OPEN_CMD"
    elif [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
      opener="open"
    elif command -v xdg-open >/dev/null 2>&1; then
      opener="xdg-open"
    else
      opener="none"
    fi
  fi
  [ "$opener" = "none" ] && continue

  $opener "$path" >/dev/null 2>&1 </dev/null &
done <<PATHS
$paths
PATHS

exit 0
