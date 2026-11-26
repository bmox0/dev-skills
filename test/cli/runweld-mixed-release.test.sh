#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/cli/lifecycle.sh"
sandbox=$(mktemp_dir)
sandbox=$(cd "$sandbox" && pwd -P)
export PATH="$sandbox/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
cli() { "$launcher" "$@"; }

# Two releases share the store; each task executes its pinned engine.
preceding="$sandbox/release-a"
mkdir "$sandbox/project with spaces" "$preceding"
cp -R "$repo_root/." "$preceding/"
printf '\nRelease A fixture.\n' >> "$preceding/README.md"
launcher="$sandbox/bin/runweld"
"$preceding/scripts/install-runweld" --prefix "$sandbox" >/dev/null
a=$(cat "$sandbox/lib/runweld/default")
bundle="$sandbox/lib/runweld/releases/$a"
cd "$sandbox/project with spaces"
git init -qb main
git commit --allow-empty -qm base
cli init --non-interactive --provider Test --primary-model main --secondary-model helper >/dev/null
previous=(previous-draft previous-active previous-plan previous-repair)
for id in "${previous[@]}"; do
  entry=$(cli task start "$id" --finish-how ff-only --finish-target main --json)
  python3 -c 'import json,sys; print(json.load(sys.stdin)["plan"])' <<< "$entry" > "$sandbox/$id.plan"
  if [[ "$id" != previous-draft ]]; then
    reserved=$(cat "$sandbox/$id.plan")
    cli grill skip "$reserved" --reason 'The fixture has no open questions' >/dev/null
    cli prototype skip "$reserved" --reason 'The fixture needs no prototype' >/dev/null
  fi
done
plan=$(cat "$sandbox/previous-active.plan")
base=$(git rev-parse HEAD)
cat > "$plan" <<PLAN
# Plan: Retain pinned guidance

Status: draft · branch \`runweld/previous-active\` · base \`$base\`

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

\`\`\`text
Grants: extra.txt
Skills to read first: none
\`\`\`

## Checks

- Gate: small — fixture

## Done

1. Resume → the release does not change.

## Spec

none
PLAN
for id in previous-plan previous-repair; do
  sed "s|runweld/previous-active|runweld/$id|" "$plan" > "$(cat "$sandbox/$id.plan")"
done
repair=$(cat "$sandbox/previous-repair.plan")
cli approve "$repair" >/dev/null
rm "${repair%.md}.json"
approve_plan "$plan" >/dev/null
cli build start "$plan" >/dev/null
cli phase start "$plan" 1 >/dev/null
cp "${plan%.md}.json" "$sandbox/approved.json"
record_status() {
  local id="$1" destination="$2" format="$3" code=0
  shift 3
  local opts=(status --current --provider Test)
  if [[ "$format" == json ]]; then
    opts+=(--json)
  fi
  (cd ".runweld/workflow/trees/$id" && "$@" "${opts[@]}") > "$destination.out" 2> "$destination.err" || code=$?
  printf '%s\n' "$code" > "$destination.code"
}

check_status() {
  local id="$1" expected="$2" format="$3" stream
  record_status "$id" "$sandbox/$id.$format.actual" "$format" cli
  for stream in code out err; do
    if ! diff -u "$expected.$stream" "$sandbox/$id.$format.actual.$stream"; then
      echo "distribution#project-lock run#task-worktree: $id $format $stream differs from pinned native scoped inventory" >&2
      exit 1
    fi
  done
}

for id in "${previous[@]}"; do
  reserved=$(cat "$sandbox/$id.plan")
  cp "${reserved%.md}.task.json" "$sandbox/$id.json"
  for format in text json; do
    record_status "$id" "$sandbox/$id.$format.native" "$format" python3 "$bundle/workflow/build/pipeline.py"
    [[ $(cat "$sandbox/$id.$format.native.code") == 0 ]]
  done
done
cp "$plan" "$sandbox/active.md"
: > "$plan"
for format in text json; do
  record_status previous-active "$sandbox/broken.$format.native" "$format" python3 "$bundle/workflow/build/pipeline.py"
  [[ $(cat "$sandbox/broken.$format.native.code") == 1 ]]
  assert_contains "$(cat "$sandbox/broken.$format.native.out")" 'no-plan:' 'distribution#project-lock: the native status refusal uses stdout'
done
cp "$sandbox/active.md" "$plan"

"$repo_root/scripts/install-runweld" --prefix "$sandbox" >/dev/null
launcher="$sandbox/bin/runweld"
cli update --project >/dev/null
b=$(cat "$sandbox/lib/runweld/default")
[[ "$a" != "$b" ]]
current_entry=$(cli task start current --finish-how ff-only --finish-target main --json)
same_plan=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["plan"])' <<< "$current_entry")
cp .runweld/runweld.lock "$sandbox/lock"

cli status --json > "$sandbox/inventory"
bundle_b="$sandbox/lib/runweld/releases/$b"
(cd .runweld/workflow/trees/previous-active && cli next --json --provider Test) > "$sandbox/older-next.json"
python3 - "$sandbox/older-next.json" "$a" <<'PY'
import json
from pathlib import Path
import sys
view = json.loads(Path(sys.argv[1]).read_text())
assert view["task"]["id"] == "previous-active" and view["task"]["release"] == sys.argv[2]
assert view["stage"] == "build" and view["task"]["goal"] == "Resume without changing releases."
assert any(sys.argv[2] in a["argv"] for a in view["actions"] if a["kind"] == "run")
PY
assert_contains "$(cli next previous-draft)" "$a grill --plan" 'distribution#system-cli: next retains the pinned planning instruction'
for format in text json; do
  record_status current "$sandbox/current.$format.native" "$format" python3 "$bundle_b/workflow/build/pipeline.py"
done
# An unrelated plan and task record must not be read, even by a retained engine.
unrelated=".runweld/workflow/plans/1900-01-01-unrelated"
mkdir "$unrelated"
printf '%s\n' 'not json' > "$unrelated/unrelated.task.json"
printf '%s\n' 'not json' > .runweld/workflow/plans/unrelated.json
touch .runweld/workflow/plans/unrelated.md
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
assert rows == dict.fromkeys(('previous-draft', 'previous-active', 'previous-plan', 'previous-repair'), a) | {'current': b}
for id in rows:
    row, = json.loads((root / f'{id}.json.actual.out').read_text())
    assert row['plan'] == id and row['release'] == rows[id]
    steps = row['workflow']['actions']
    if id == 'previous-active':
        assert row['status'] == 'building'
        action = next(s for s in steps if s['kind'] == 'run' and s.get('role') == 'implementer')
        brief = subprocess.check_output(action['argv'], text=True, cwd=root).strip()
        assert f'{root}/lib/runweld/releases/{a}/agents/implementer.md' in Path(brief).read_text()
    elif id == 'previous-plan':
        assert row['status'] == 'draft' and row['nostate'] and row['ready'] == [] and row['state_repair'] is None
        assert any(action['kind'] == 'run' and action['argv'][-4:] == ['--release', a, 'approve', row['path']] for action in steps)
    elif id == 'previous-repair':
        restore = f"restore {Path(row['path']).with_suffix('.json')}"
        assert row['nostate'] and row['ready'] == [] and row['state_repair'] == restore
        action, = steps
        assert action['assignment']['kind'] == 'repair-file' and action['action'] == restore
    else:
        assert row['status'] == 'planning' and row['ready'] == []
        assert steps[0]['assignment']['kind'] == 'grill'
PY

: > "$plan"
for format in text json; do
  check_status previous-active "$sandbox/broken.$format.native" "$format"
done
cp "$sandbox/active.md" "$plan"
rm "$unrelated/unrelated.task.json" .runweld/workflow/plans/unrelated.{json,md}
rmdir "$unrelated"

# Also compare the same-release launcher to the native command as a new task gains and loses state.
cli grill skip "$same_plan" --reason 'The fixture has no open questions' >/dev/null
cli prototype skip "$same_plan" --reason 'The fixture needs no prototype' >/dev/null
sed 's|runweld/previous-plan|runweld/current|' "$(cat "$sandbox/previous-plan.plan")" > "$same_plan"
for state in draft active unreadable repair; do
  expected_code=0
  case "$state" in
    active)
      approve_plan "$same_plan" >/dev/null
      cli build start "$same_plan" >/dev/null
      cli phase start "$same_plan" 1 >/dev/null
      ;;
    unreadable)
      printf '%s\n' 'not json' > "${same_plan%.md}.json"
      expected_code=1
      ;;
    repair) rm "${same_plan%.md}.json" ;;
  esac
  for format in text json; do
    record_status current "$sandbox/current.$format.native" "$format" python3 "$bundle_b/workflow/build/pipeline.py"
    [[ $(cat "$sandbox/current.$format.native.code") == "$expected_code" ]]
    check_status current "$sandbox/current.$format.native" "$format"
  done
done
current_record="${same_plan%.md}.task.json"
cp "$current_record" "$sandbox/current-record.json"
printf '%s\n' 'not json' > "$current_record"
record_status current "$sandbox/current-corrupt.native" json python3 "$bundle_b/workflow/build/pipeline.py"
[[ $(cat "$sandbox/current-corrupt.native.code") == 1 ]]
assert_contains "$(cat "$sandbox/current-corrupt.native.err")" "$current_record" 'distribution#project-lock: corrupt task metadata identifies the record on stderr'
check_status current "$sandbox/current-corrupt.native" json
cp "$sandbox/current-record.json" "$current_record"
mv "$bundle_b" "$sandbox/missing-b"
assert_contains "$(cd .runweld/workflow/trees/previous-active && cli status --current --json)" "$a" 'distribution#project-lock: pinned current guidance does not require the project release'
mv "$sandbox/missing-b" "$bundle_b"
printf 'damaged fixture\n' > "$bundle/references/SESSIONS.md"
for id in "${previous[@]}"; do
  if output=$(cd ".runweld/workflow/trees/$id" && cli status --current --json 2>&1); then
    echo "distribution#project-lock: $id accepted a damaged pinned release" >&2
    exit 1
  fi
  assert_contains "$output" "$a" 'distribution#project-lock: recovery names the exact pinned release'
  assert_contains "$output" 'install this exact release' 'distribution#project-lock: recovery explains how to repair it'
  reserved=$(cat "$sandbox/$id.plan")
  cmp "${reserved%.md}.task.json" "$sandbox/$id.json"
done
mv "$bundle" "$sandbox/damaged-a"
if output=$(cd .runweld/workflow/trees/previous-repair && cli status --current 2>&1); then
  echo 'distribution#project-lock: scoped repair guidance cannot use a different release' >&2
  exit 1
fi
assert_contains "$output" "$a" 'distribution#project-lock: a missing pin names the exact release to reinstall'
mv "$sandbox/damaged-a" "$bundle"
cmp "${plan%.md}.json" "$sandbox/approved.json"
cmp .runweld/runweld.lock "$sandbox/lock"

# Reinstall A for its exact bytes, then B to restore the shared router and default.
"$preceding/scripts/install-runweld" --prefix "$sandbox" >/dev/null
cmp .runweld/runweld.lock "$sandbox/lock"
cmp "$preceding/bin/runweld" "$sandbox/bin/runweld"
assert_eq "$a" "$(cat "$sandbox/lib/runweld/default")"
"$repo_root/scripts/install-runweld" --prefix "$sandbox" >/dev/null
cmp .runweld/runweld.lock "$sandbox/lock"
cmp "$repo_root/bin/runweld" "$sandbox/bin/runweld"
assert_eq "$b" "$(cat "$sandbox/lib/runweld/default")"
# The advertised command above prepared a real brief after the original native snapshot.
record_status previous-active "$sandbox/previous-active.json.native" json python3 "$bundle/workflow/build/pipeline.py"
assert_contains "$(cat "$sandbox/previous-active.json.native.out")" '"dispatch": "unverified"' 'distribution#system-cli: release A recovers the prepared assignment'
for id in "${previous[@]}"; do
  check_status "$id" "$sandbox/$id.json.native" json
done
