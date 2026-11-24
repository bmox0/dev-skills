#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
pipeline="$repo_root/skills/build/pipeline.py"
. "$repo_root/test/lib/harness.sh"
. "$here/lifecycle.sh"
cli() { python3 -B "$pipeline" "$@"; }

fixture=$(mktemp_dir)
mkdir "$fixture/repo with spaces"
cd "$fixture/repo with spaces"
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git -c commit.gpgsign=false commit --allow-empty -qm base
git tag v0
mkdir -p .ai-workflow/plans
plan="$(pwd -P)/.ai-workflow/plans/2026-11-24-recovery.md"
cat > "$plan" <<'PLAN'
# Plan: Recovery

Status: draft · branch `recovery` · base `<sha>`

## Result

Recover a check.

## Approach

Keep the original transition.

## Out of scope

- External processes

## Phases

### 1. Work — `waiting`

Do work.
Territory: `src/`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture

## Done

1. Recover a check → the original transition closes.

## Spec

none
PLAN
sed 's|^full = .*$|full = ["echo started >> .ai-workflow/suite-starts", "python3 .ai-workflow/controlled-check.py"]|' \
  "$repo_root/skills/run-file/references/example.run.toml" > "${plan%.md}.run.toml"
approve_plan "$plan" >/dev/null
cli build start "$plan" --base v0 >/dev/null
cli phase start "$plan" 1 >/dev/null
mkdir src
touch src/start
git add src/start
git commit -qm phase
report_phase "$plan" 1 --became ready --commit "$(git rev-parse HEAD)" >/dev/null
cli phase done "$plan" 1 >/dev/null

python3 "$here/check-recovery.py" "$pipeline" "$plan"
