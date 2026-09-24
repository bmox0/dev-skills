#!/usr/bin/env bash
# PreToolUse(Bash) — while a run is open, history surgery goes through
# dev-skills:finish and nowhere else.
#
# Armed only by a run marker (.ai-workflow/run/<plan>/RUN, written by
# dev-skills:implement and cleared by dev-skills:finish). Outside a run this hook does nothing:
# an unconditional block on reset/merge/rebase would break ordinary work in every
# repository, which is why the marker exists at all.
#
# One exception: while the marker is armed, a merge whose source ref is under
# this run's own run/<slug>/ namespace is permitted, so an orchestrator can
# merge this run's own worker, tester and join branches without a human
# typing git by hand. The slug is read from the marker's own plan= line —
# never a template, never another run's marker — so a different run's
# run/<other-slug>/… stays denied, and every other merge is still routed
# through dev-skills:finish.
#
# Every rule below matches a git invocation in command position — the start of
# a line, or right after one of ; & | ( { , with optional whitespace between —
# via git_cmd_matches. A command that only quotes or describes a blocked
# invocation, in a grep pattern, a heredoc body, or an echoed sentence, has its
# "git" in some other position and is not matched.
#
# The script itself is not exempted and does not need to be: PreToolUse sees the
# command the model runs (`finish squash …`), and the git calls inside the
# script never pass through a hook.
#
# Fail-open: on any parsing error, or on any command whose git invocation
# git_cmd_matches cannot find in command position, the command is allowed. A
# guard that blocks by accident is worse than one that misses.

input="$(cat 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# git_cmd_matches ERE — true when $cmd contains a git invocation in command
# position whose text matches ERE. ERE is written exactly as it is today,
# starting with `git`; the function supplies the command-position anchor in
# front of it. Command position: start of a line, or after one of ; & | ( { ,
# with optional whitespace between.
git_cmd_matches() { printf '%s' "$cmd" | grep -qE "(^|[;&|({])[[:space:]]*$1"; }

# Cheap pre-filter: nothing here concerns a command without git in it.
git_cmd_matches 'git([[:space:]]|$)' || exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$root" ] && exit 0
runs="$root/.ai-workflow/run"
[ -d "$runs" ] || exit 0

marker="$(find "$runs" -mindepth 2 -maxdepth 2 -name RUN -type f 2>/dev/null | head -1)"
[ -n "$marker" ] || exit 0

plan="$(sed -n 's/^plan=//p' "$marker" 2>/dev/null | head -1)"

deny() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null
  exit 0
}

blocked() {
  deny "Blocked by finish-guard: a run is in progress (plan: ${plan:-unknown}), so $1

$2

If this run is over, clear the marker: dev-skills:implement's scripts/run-state end"
}

# --- history surgery that belongs to dev-skills:finish ------------------------------
if git_cmd_matches 'git[[:space:]]+reset[[:space:]]+(-[[:alnum:]]*[[:space:]]+)*--(hard|soft|mixed|merge|keep)'; then
  blocked "moving HEAD is dev-skills:finish's job." \
    "The squash is 'finish squash <message file>' — it records a numbered recovery ref first and compares tree hashes after. To undo one: 'finish recover' to list the attempts, then 'finish recover <attempt>'. Unstaging a path ('git reset -- <path>') is not blocked."
fi

if git_cmd_matches 'git[[:space:]]+rebase' \
   && ! git_cmd_matches 'git[[:space:]]+rebase[[:space:]]+--(continue|abort|skip|quit|edit-todo)'; then
  blocked "rebasing is dev-skills:finish's job." \
    "Use 'finish rebase' — it reports how the base moved and whether it touched this run's paths, which decides whether the acceptance still stands. Finishing an in-progress rebase (--continue / --abort / --skip) is not blocked."
fi

if git_cmd_matches 'git[[:space:]]+merge' \
   && ! git_cmd_matches 'git[[:space:]]+merge[[:space:]]+--(abort|continue|quit)'; then
  slug=""
  [ -n "$plan" ] && slug="$(basename "$plan" .md)"
  if ! { [ -n "$slug" ] && git_cmd_matches "git[[:space:]]+merge[[:space:]]+(--[[:alnum:]-]+[[:space:]]+)*run/${slug}/[^[:space:]]+"; }; then
    blocked "integrating is dev-skills:finish's job." \
      "Use 'finish integrate --ff-only', after the human's acceptance. Fast-forward is the only mode offered: anything else means the base moved, and the answer to that is a rebase. A merge under this run's own run/<slug>/… namespace is permitted."
  fi
fi

# --- things that destroy the run's recovery points --------------------------
if git_cmd_matches 'git[[:space:]]+commit[[:space:]]+(.*[[:space:]])?--amend'; then
  blocked "amending would move an already-read range under the gate's feet." \
    "Fixes land as separate commits on top. Everything collapses into one commit at dev-skills:finish anyway."
fi

if git_cmd_matches 'git[[:space:]]+(branch[[:space:]]+(-[[:alnum:]]*[[:space:]]+)*(-d|-D|--delete)|worktree[[:space:]]+remove)'; then
  blocked "the run's branch and worktree are its recovery points." \
    "Cleanup happens in 'finish cleanup', after integration is proven — and only for a worktree this workflow created."
fi

if git_cmd_matches 'git[[:space:]]+push[[:space:]]+.*(--force([^-]|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$))'; then
  blocked "a force-push during a run rewrites what the gates already read." \
    "A rejected push means the remote moved. Investigate; force-push only on your human partner's explicit request, after the run is closed."
fi

exit 0
