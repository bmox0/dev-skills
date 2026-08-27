#!/usr/bin/env bash
# PostToolUse hook: the moment a prototype is written to disk, open it in the
# browser. The prototyper draws `.ai-workflow/plans/<plan>/prototypes/M-<n>.html`
# as a self-contained file that opens straight from disk, and the human used to
# have to ask for it to be opened every time. Now it just is.
#
# Fires only on a Write whose path is a .html file under a prototypes/
# directory. Anything else — another tool, another path — exits silently.
# Never blocks: the file is already written by the time this runs, and a
# missing opener is not the model's problem.
#
# DEV_SKILLS_OPEN_CMD overrides the opener (a browser of choice, or a stub
# under test). Without it: `open` on macOS, `xdg-open` elsewhere, nothing if
# neither is there.

input="$(cat 2>/dev/null || true)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
[ "$tool" = "Write" ] || exit 0

path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
case "$path" in
  */prototypes/*.html) ;;
  *) exit 0 ;;
esac
[ -f "$path" ] || exit 0

if [ -n "${DEV_SKILLS_OPEN_CMD:-}" ]; then
  opener="$DEV_SKILLS_OPEN_CMD"
elif [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
  opener="open"
elif command -v xdg-open >/dev/null 2>&1; then
  opener="xdg-open"
else
  exit 0
fi

$opener "$path" >/dev/null 2>&1 </dev/null &
exit 0
