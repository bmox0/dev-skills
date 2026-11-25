#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/cli/lifecycle.sh"
sandbox=$(mktemp_dir)
sandbox=$(cd "$sandbox" && pwd -P)
export PATH="$sandbox/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
cli() { ds "$@"; }

# distribution#project-lock: use a preceding source or model its strict three-field contract without Git history.
preceding=${DS_TEST_PRECEDING:-$sandbox/preceding}
mkdir "$sandbox/project with spaces"
if [[ -z ${DS_TEST_PRECEDING:-} ]]; then
  mkdir "$preceding"
  cp -R "$repo_root/." "$preceding/"
  python3 - "$preceding/skills/build" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for name, replacements in {
    'ds_release.py': [('set(value) not in (fields, fields | {"release"})', 'set(value) != fields')],
    'pipeline.py': [(', "ready": False, "release": bundle.name}', ', "ready": False}'),
                    ('("base", "ready", "branch", "release")', '("base", "ready", "branch")'),
                    ('def main(*, current_task=None):', 'def main():\n    current_task = None')],
}.items():
    path = root / name
    code = path.read_text()
    for before, after in replacements:
        assert code.count(before) == 1, before
        code = code.replace(before, after)
    path.write_text(code)
PY
fi
"$preceding/scripts/install-ds" --prefix "$sandbox" >/dev/null
a=$(ds --version)
bundle="$sandbox/lib/dev-skills/releases/$a"
cd "$sandbox/project with spaces"
git init -qb main
git commit --allow-empty -qm base
ds init --non-interactive --provider Test --primary-model main --secondary-model helper >/dev/null
previous=(previous-draft previous-active previous-plan previous-repair previous-adopt)
for id in "${previous[@]}"; do
  ds task start "$id" >/dev/null
done
plan="$PWD/.ds/workflow/plans/previous-active.md"
base=$(git rev-parse HEAD)
cat > "$plan" <<PLAN
# Plan: Retain pinned guidance

Status: draft · branch \`ds/previous-active\` · base \`$base\`

## Result

Resume without changing releases.

## Approach

Use the release selected by the run.

## Out of scope

- Plugin setup.

## Phases

### 1. Change — \`waiting\`
Territory: \`fixture.txt\`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture

## Done

1. Resume → the release does not change.

## Spec

none
PLAN
for id in previous-plan previous-repair previous-adopt; do
  sed "s|ds/previous-active|ds/$id|" "$plan" > "${plan%/*}/$id.md"
done
ds approve "${plan%/*}/previous-repair.md" >/dev/null
rm "${plan%/*}/previous-repair.json"
sed 's/Status: draft/Status: building/' "${plan%/*}/previous-adopt.md" > "$sandbox/adopt.md"
mv "$sandbox/adopt.md" "${plan%/*}/previous-adopt.md"
approve_plan "$plan" >/dev/null
ds build start "$plan" >/dev/null
ds phase start "$plan" 1 >/dev/null
cp "${plan%.md}.json" "$sandbox/approved.json"
record_status() {
  local id="$1" destination="$2" format="$3" code=0
  shift 3
  local opts=(status --current --provider Test)
  if [[ "$format" == json ]]; then
    opts+=(--json)
  fi
  (cd ".ds/workflow/trees/$id" && "$@" "${opts[@]}") > "$destination.out" 2> "$destination.err" || code=$?
  printf '%s\n' "$code" > "$destination.code"
}

check_status() {
  local id="$1" expected="$2" format="$3" stream
  record_status "$id" "$sandbox/$id.$format.actual" "$format" ds
  for stream in code out err; do
    if ! diff -u "$expected.$stream" "$sandbox/$id.$format.actual.$stream"; then
      echo "distribution#project-lock run#task-worktree: $id $format $stream differs from pinned native scoped inventory" >&2
      exit 1
    fi
  done
}

for id in "${previous[@]}"; do
  cp ".ds/workflow/tasks/$id.json" "$sandbox/$id.json"
  for format in text json; do
    record_status "$id" "$sandbox/$id.$format.native" "$format" python3 "$bundle/skills/build/pipeline.py"
    [[ $(cat "$sandbox/$id.$format.native.code") == 0 ]]
  done
done
cp "$plan" "$sandbox/active.md"
: > "$plan"
for format in text json; do
  record_status previous-active "$sandbox/broken.$format.native" "$format" python3 "$bundle/skills/build/pipeline.py"
  [[ $(cat "$sandbox/broken.$format.native.code") == 1 ]]
  assert_contains "$(cat "$sandbox/broken.$format.native.out")" 'no-plan:' 'distribution#project-lock: the native status refusal uses stdout'
done
cp "$sandbox/active.md" "$plan"

"$repo_root/scripts/install-ds" --prefix "$sandbox" >/dev/null
ds update >/dev/null
b=$(ds --version)
[[ "$a" != "$b" ]]
ds task start current >/dev/null
cp .ds/ds.lock "$sandbox/lock"

ds status --json > "$sandbox/inventory"
bundle_b="$sandbox/lib/dev-skills/releases/$b"
for format in text json; do
  record_status current "$sandbox/current.$format.native" "$format" python3 "$bundle_b/skills/build/pipeline.py"
done
# An unrelated plan and task record must not be read, even by a retained engine.
printf '%s\n' 'not json' > .ds/workflow/tasks/unrelated.json
printf '%s\n' 'not json' > .ds/workflow/plans/unrelated.json
touch .ds/workflow/plans/unrelated.md
for id in "${previous[@]}" current; do
  for format in text json; do
    check_status "$id" "$sandbox/$id.$format.native" "$format"
  done
done
python3 - "$sandbox" "$a" "$b" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

root, a, b = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
rows = {r['plan']: r['release'] for r in json.loads((root / 'inventory').read_text())}
assert rows == dict.fromkeys(('previous-draft', 'previous-active', 'previous-plan', 'previous-repair', 'previous-adopt'), a) | {'current': b}
for id in rows:
    row, = json.loads((root / f'{id}.json.actual.out').read_text())
    assert row['plan'] == id and row['release'] == rows[id]
    steps = row['workflow']['actions']
    if id == 'previous-active':
        assert row['status'] == 'building'
        action = next(s for s in steps if s['kind'] == 'run' and s.get('role') == 'implementer')
        brief = subprocess.check_output(action['argv'], text=True, cwd=root).strip()
        assert f'{root}/lib/dev-skills/releases/{a}/agents/implementer.md' in Path(brief).read_text()
    elif id == 'previous-plan':
        assert row['status'] == 'draft' and row['nostate'] and row['ready'] == [] and row['state_repair'] is None
        action, = steps
        assert action['kind'] == 'run' and action['argv'][-4:] == ['--release', a, 'approve', row['path']]
    elif id == 'previous-repair':
        restore = f"restore {Path(row['path']).with_suffix('.json')}"
        assert row['nostate'] and row['ready'] == [] and row['state_repair'] == restore
        action, = steps
        assert action['assignment']['kind'] == 'repair-file' and action['action'] == restore
    elif id == 'previous-adopt':
        assert row['status'] == 'building' and row['nostate'] and row['state_repair'] is None
        assert steps[0]['assignment']['kind'] == 'adopt-plan'
    else:
        assert row['status'] == 'planning' and row['ready'] == []
        assert steps[0]['assignment']['kind'] == 'grill'
PY

: > "$plan"
for format in text json; do
  check_status previous-active "$sandbox/broken.$format.native" "$format"
done
cp "$sandbox/active.md" "$plan"
rm .ds/workflow/tasks/unrelated.json .ds/workflow/plans/unrelated.{json,md}

# Also compare the same-release launcher to the native command as a new task gains and loses state.
same_plan="${plan%/*}/current.md"
sed 's|ds/previous-plan|ds/current|' "${plan%/*}/previous-plan.md" > "$same_plan"
for state in draft active unreadable repair; do
  expected_code=0
  case "$state" in
    active)
      approve_plan "$same_plan" >/dev/null
      ds build start "$same_plan" >/dev/null
      ds phase start "$same_plan" 1 >/dev/null
      ;;
    unreadable)
      printf '%s\n' 'not json' > "${same_plan%.md}.json"
      expected_code=1
      ;;
    repair) rm "${same_plan%.md}.json" ;;
  esac
  for format in text json; do
    record_status current "$sandbox/current.$format.native" "$format" python3 "$bundle_b/skills/build/pipeline.py"
    [[ $(cat "$sandbox/current.$format.native.code") == "$expected_code" ]]
    check_status current "$sandbox/current.$format.native" "$format"
  done
done
current_record=.ds/workflow/tasks/current.json
cp "$current_record" "$sandbox/current-record.json"
printf '%s\n' 'not json' > "$current_record"
record_status current "$sandbox/current-corrupt.native" json python3 "$bundle_b/skills/build/pipeline.py"
[[ $(cat "$sandbox/current-corrupt.native.code") == 1 ]]
assert_contains "$(cat "$sandbox/current-corrupt.native.err")" "$current_record" 'distribution#project-lock: corrupt task metadata identifies the record on stderr'
check_status current "$sandbox/current-corrupt.native" json
cp "$sandbox/current-record.json" "$current_record"
mv "$bundle_b" "$sandbox/missing-b"
assert_contains "$(cd .ds/workflow/trees/previous-active && ds status --current --json)" "$a" 'distribution#project-lock: pinned current guidance does not require the project release'
mv "$sandbox/missing-b" "$bundle_b"
printf 'damaged fixture\n' > "$bundle/references/SESSIONS.md"
for id in "${previous[@]}"; do
  if output=$(cd ".ds/workflow/trees/$id" && ds status --current --json 2>&1); then
    echo "distribution#project-lock: $id accepted a damaged pinned release" >&2
    exit 1
  fi
  assert_contains "$output" "$a" 'distribution#project-lock: recovery names the exact pinned release'
  assert_contains "$output" 'install this exact release' 'distribution#project-lock: recovery explains how to repair it'
  cmp ".ds/workflow/tasks/$id.json" "$sandbox/$id.json"
done
mv "$bundle" "$sandbox/damaged-a"
if output=$(cd .ds/workflow/trees/previous-repair && ds status --current 2>&1); then
  echo 'distribution#project-lock: scoped repair guidance cannot use a different release' >&2
  exit 1
fi
assert_contains "$output" "$a" 'distribution#project-lock: a missing pin names the exact release to reinstall'
mv "$sandbox/damaged-a" "$bundle"
cmp "${plan%.md}.json" "$sandbox/approved.json"
cmp .ds/ds.lock "$sandbox/lock"

# Reinstall A for its exact bytes, then B to restore the shared router and default.
"$preceding/scripts/install-ds" --prefix "$sandbox" >/dev/null
cmp .ds/ds.lock "$sandbox/lock"
cmp "$preceding/bin/ds" "$sandbox/bin/ds"
assert_eq "$a" "$(cat "$sandbox/lib/dev-skills/default")"
"$repo_root/scripts/install-ds" --prefix "$sandbox" >/dev/null
cmp .ds/ds.lock "$sandbox/lock"
cmp "$repo_root/bin/ds" "$sandbox/bin/ds"
assert_eq "$b" "$(cat "$sandbox/lib/dev-skills/default")"
for id in "${previous[@]}"; do
  check_status "$id" "$sandbox/$id.json.native" json
done
