#!/usr/bin/env bash
input="$(cat 2>/dev/null || true)"
case "$input" in *git*) ;; *) exit 0 ;; esac
command -v python3 >/dev/null 2>&1 || exit 0
printf '%s' "$input" | python3 "$(dirname "${BASH_SOURCE[0]}")/git-guard.py" 2>/dev/null
exit 0
