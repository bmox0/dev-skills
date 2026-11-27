#!/usr/bin/env bash
set -euo pipefail
unset CODEX_THREAD_ID CLAUDECODE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/cli/lifecycle.sh"

sandbox=$(mktemp_dir)
sandbox=$(cd "$sandbox" && pwd -P)

prefix="$sandbox/install prefix"
project="$sandbox/project with spaces"
export PATH="$prefix/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# distribution#system-cli: a terminal outside the source tree uses standalone help and resources.
if ! install=$(cd "$sandbox" && "$repo_root/scripts/install-runweld" --prefix "$prefix" 2>&1); then
  echo "distribution#system-cli: an outside terminal can install Runweld: $install" >&2
  exit 1
fi
cli() { runweld "$@"; }
entry_field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
a=$(cat "$prefix/lib/runweld/default")
assert_eq "${a%%@*}" "$(cd "$sandbox" && runweld --version)" 'distribution#system-cli: show the ordinary CLI version'
version_details() { printf 'CLI version: %s\nBuild ID: %s\n' "${1%%@*}" "$1"; }
assert_eq "$(version_details "$a")" "$(cd "$sandbox" && runweld --version --verbose)" 'distribution#system-cli: label the exact build separately'
engine_a="$prefix/lib/runweld/releases/$a"
assert_contains "$(cd "$sandbox" && runweld --help)" 'runweld COMMAND [ARGS...]' 'distribution#system-cli: runweld uses terminal-facing help'
assert_contains "$(cd "$sandbox" && runweld help agents)" "$a" 'distribution#system-cli: help points to the installed protocol'
assert_contains "$(node "$engine_a/workflow/browser-test/tab.mjs" --help)" "one persistent tab" 'distribution#system-cli: the installed browser helper runs'
[[ -r "$engine_a/agents/implementer.md" ]] || { echo 'distribution#system-cli: the release includes role instructions' >&2; exit 1; }

mkdir -p "$project/.runweld"
cd "$project"
git init -q -b main
git commit --allow-empty -qm base
runweld init --non-interactive --provider Test --primary-model primary --secondary-model secondary >/dev/null
if out=$(runweld run new docs/solo.md 2>&1); then
  echo 'run#task-worktree: standalone run new cannot bypass task entry' >&2
  exit 1
fi
assert_contains "$out" 'runweld task start' 'run#task-worktree: standalone run new tells the user how to start a task'
[[ ! -e docs/solo.run.toml && $(git branch --show-current) == main ]]
base=$(git rev-parse HEAD)
entry=$(runweld task start run-a --finish-how ff-only --finish-target main --json)
plan=$(entry_field plan <<< "$entry")
repo_worktree=$(entry_field tree <<< "$entry")
cat > "$plan" <<PLAN
# Plan: A run bound to its installed release

Status: draft · branch \`runweld/run-a\` · base \`$base\`

## Result

Keep the run on A.

## Approach

Use the installed workflow.

## Out of scope

- Host plugins.

## Phases

### 1. Add a fixture — \`waiting\`

Territory: \`src/\`
Skills: \`workflow/tdd/GUIDE.md\`
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture only

## Done

1. Install A → the run stays on A.

## Spec

none
PLAN
runweld grill skip "$plan" --reason 'The fixture has no open questions' >/dev/null
runweld prototype skip "$plan" --reason 'The fixture needs no prototype' >/dev/null
cp "${plan%.md}.run.toml" "$sandbox/run-a.toml"
mkdir docs
sed 's|runweld/run-a|solo|' "$plan" > docs/solo.md
cp "$sandbox/run-a.toml" docs/solo.run.toml
refuse_solo() {
  local out
  if out=$(runweld "$@" docs/solo.md 2>&1); then
    echo "run#task-worktree: $* accepted a copied release pin for an unregistered draft" >&2
    exit 1
  fi
  assert_contains "$out" 'runweld task start' 'run#task-worktree: rejection directs the user to task entry'
}
refuse_solo run check
refuse_solo approve
refuse_solo plan review
refuse_solo plan approve --revision old --by 'Fixture Human' --words 'Fixture consent'
refuse_solo build start --base main --note 'Fixture override'
[[ ! -e docs/solo.json && $(git branch --show-current) == main ]]
rm docs/solo.md docs/solo.run.toml
approve_plan "$plan" >/dev/null
runweld build start "$plan" >/dev/null
release_task=$(runweld task start release-task --finish-how ff-only --finish-target main --json)
release_task_tree=$(entry_field tree <<< "$release_task")
release_task_plan=$(entry_field plan <<< "$release_task")
release_task_run="${release_task_plan%.md}.run.toml"
cp "$release_task_run" "$sandbox/task-a.toml"

# run#starts-from-last: a draft cannot remove its registered release before compilation or approval.
sed '/^\[workflow\]$/{N;N;d;}' "$sandbox/task-a.toml" > "$release_task_run"
if out=$(runweld run check "${release_task_run%.run.toml}.md" 2>&1); then
  echo 'run#starts-from-last: a task without its entry pin cannot validate' >&2
  exit 1
fi
assert_contains "$out" '[workflow]' 'run#starts-from-last: a missing entry pin identifies the field to restore'
cp "$sandbox/task-a.toml" "$release_task_run"

# distribution#project-lock: a project update keeps an existing task on its release.
previous_entry=$(runweld task start previous-record --finish-how ff-only --finish-target main --json)
previous_plan=$(entry_field plan <<< "$previous_entry")
previous_artifacts=$(entry_field artifacts <<< "$previous_entry")
previous="${previous_plan%.md}.task.json"
cp "$previous" "$sandbox/previous-record.json"

# distribution#project-lock: an interrupted entry retains A even if the project lock moves before retry.
interrupted=$(runweld task start interrupted --finish-how ff-only --finish-target main --json)
interrupted_plan=$(entry_field plan <<< "$interrupted")
interrupted_run="${interrupted_plan%.md}.run.toml"
rm "$interrupted_run"
python3 - "${interrupted_plan%.md}.task.json" <<'PY'
import json
from pathlib import Path
import sys
record = Path(sys.argv[1])
value = json.loads(record.read_text())
value['ready'] = False
value['finish'] = {'how': 'merge-request', 'target': 'main'}
record.write_text(json.dumps(value))
PY

# distribution#project-lock: a side-by-side install changes no project until explicit update.
source_b="$sandbox/source b"
mkdir "$source_b"
cp -R "$repo_root/." "$source_b/"
python3 - "$source_b/VERSION" "$source_b/workflow/build/pipeline.py" "$source_b/workflow/build/cli_help.py" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text("9.99.0\n")
engine, help_source = map(Path, sys.argv[2:])
engine.write_text(engine.read_text().replace('Read the {guide} instructions for this task.', 'Continue using release B.'))
help_source.write_text(help_source.read_text().replace('Plan, build, verify, and finish work in a Git repository.',
                                                      'Terminal help from release B.', 1))
PY
cp "$source_b/references/workflow.toml" "$sandbox/workflow.toml"
sed 's|workflow/browser-test/tab.mjs|workflow/browser-test/missing.mjs|' "$sandbox/workflow.toml" > "$source_b/references/workflow.toml"
if out=$("$source_b/scripts/install-runweld" --prefix "$prefix" 2>&1); then
  echo 'installer accepted a missing conditional tool' >&2
  exit 1
fi
assert_contains "$out" 'missing stage inputs: workflow/browser-test/missing.mjs' 'distribution#project-lock: invalid stage input identifies the missing file'
cp "$sandbox/workflow.toml" "$source_b/references/workflow.toml"
sed 's/^grill = "ask"/grill = "skip"/' "$sandbox/workflow.toml" > "$source_b/references/workflow.toml"

# distribution#system-cli: neither advertised guides nor the instructions they link to are optional.
for missing in references/WORKFLOW-PATHS.md workflow/plan/references/environment-contract.md workflow/build/cli_help.py; do
  mv "$source_b/$missing" "$sandbox/removed-resource"
  if out=$("$source_b/scripts/install-runweld" --prefix "$prefix" 2>&1); then
    echo "distribution#system-cli: installation accepted an incomplete candidate missing $missing" >&2
    exit 1
  fi
  assert_contains "$out" "$missing" 'distribution#system-cli: the rejected candidate names the missing guide'
  assert_eq "$(version_details "$a")" "$(cd "$sandbox" && runweld --version --verbose)" 'distribution#project-lock: a rejected candidate does not become the default'
  mv "$sandbox/removed-resource" "$source_b/$missing"
done
printf '\nInterview instructions from build B.\n' >> "$source_b/workflow/grill/references/INTERVIEW.md"
adr_reference=workflow/domain-modeling/references/ADR-FORMAT.md
printf '\nADR reference from build B.\n' >> "$source_b/$adr_reference"
"$source_b/scripts/install-runweld" --prefix "$prefix" >/dev/null
b=$(cat "$prefix/lib/runweld/default")
engine_b="$prefix/lib/runweld/releases/$b"
[[ "$b" != "$a" ]] || { echo 'distribution#project-lock: A and B can be installed separately' >&2; exit 1; }
project_versions() { printf 'CLI: %s\nProject: %s\n' "${1%%@*}" "${2%%@*}"; }
assert_eq "$(project_versions "$b" "$a")" "$(cd "$repo_worktree" && runweld --version)" 'distribution#project-lock: show both the installed and pinned versions'
assert_eq "$(project_versions "$b" "$a")
CLI build ID: $b
Project build ID: $a" "$(cd "$repo_worktree" && runweld --version --verbose)" 'distribution#project-lock: installing B does not change the lock in any worktree'
assert_contains "$(cd "$repo_worktree" && runweld help agents)" "$a" 'distribution#project-lock: linked help uses A before update'
assert_contains "$(cd "$repo_worktree" && runweld --help)" 'Plan, build, verify, and finish work' 'distribution#project-lock: terminal help uses the selected release'
(cd "$repo_worktree" && runweld update --project) >/dev/null
assert_eq "$(project_versions "$b" "$b")" "$(runweld --version)" 'distribution#project-lock: update changes the main checkout selection'
assert_contains "$(runweld grill)" 'Interview instructions from build B.' 'project guide follows B'
assert_contains "$(runweld reference "$adr_reference")" 'ADR reference from build B.' 'distribution#system-cli: project references follow B'
if [[ $(cd "$repo_worktree" && runweld grill) == *'Interview instructions from build B.'* ||
      $(runweld grill --plan "$plan") == *'Interview instructions from build B.'* ||
      $(runweld reference "$adr_reference" --plan "$plan") == *'ADR reference from build B.'* ]]; then
  echo 'task guide and references must retain release A' >&2
  exit 1
fi
assert_contains "$(runweld help agents)" "$b" 'distribution#project-lock: project help now uses B'
assert_contains "$(runweld --help)" 'Terminal help from release B.' 'distribution#project-lock: terminal help uses B after update'
assert_eq "$(runweld --help)" "$(runweld help)" 'distribution#command-help: both help spellings use the selected release'
assert_contains "$(runweld --release "$a" help)" 'Plan, build, verify, and finish work' 'distribution#project-lock: explicit terminal help still uses A'
assert_contains "$(runweld task resume previous-record --json)" "$a" 'distribution#project-lock: a pinned task still resumes on A'
assert_eq "$previous_artifacts/browser-test" "$(runweld task path previous-record browser-test)" 'distribution#project-lock: pinned task paths still resolve'
assert_contains "$(runweld run show "$previous_plan" --json)" "${a#*@}" 'distribution#project-lock: a pinned run still shows A'
assert_contains "$(runweld status --json)" 'previous-record' 'distribution#project-lock: project inventory finds pinned tasks'
cmp "$previous" "$sandbox/previous-record.json"
assert_contains "$(runweld task start interrupted --json)" "$a" 'distribution#project-lock: retry retains the entry release after update'
assert_contains "$(cat "$interrupted_run")" 'how = "merge-request"' 'run#starts-from-last: retry retains the finish choice'
fresh_entry=$(runweld task start run-b --finish-how ff-only --finish-target main --json)
fresh=$(entry_field plan <<< "$fresh_entry")
assert_contains "$(runweld run show "$fresh" --json)" "${b#*@}" 'run#starts-from-last: a new run snapshots the newly locked release B'
assert_contains "$(cd "$release_task_tree" && runweld run show "${release_task_plan#"$project"/}" --json)" "${a#*@}" 'distribution#project-lock: relative plan commands in a task tree use its earlier release'
assert_contains "$(cd "$release_task_tree" && runweld task resume release-task --json)" "$a" 'distribution#project-lock: resume reports the release captured at task entry'
assert_contains "$(cd "$release_task_tree" && runweld next --json)" "$a" 'distribution#system-cli: next in the old task uses its release'
assert_contains "$(runweld next run-b --json)" 'Continue using release B.' 'distribution#system-cli: next in the new task uses its release'
runweld status --current --json | python3 -c '
import json, sys
rows = {r["plan"]: r for r in json.load(sys.stdin)}
assert rows["release-task"]["workflow"]["actions"][0]["action"] == "Read the grill instructions for this task."
assert rows["previous-record"]["release"] == rows["release-task"]["release"]
assert rows["run-b"]["workflow"]["actions"][0]["action"] == "Continue using release B."
assert rows["release-task"]["workflow"]["stage"] == "grill"
assert rows["run-b"]["workflow"]["stage"] == "prototype", "planning#run-route: a run follows its own release defaults"
'
sed -e "s/^version = .*/version = \"${b%%@*}\"/" -e "s/${a#*@}/${b#*@}/" "$sandbox/task-a.toml" > "$release_task_run"
if out=$(runweld task resume release-task 2>&1); then
  echo 'run#starts-from-last: an edited draft cannot move a registered task to the current project release' >&2
  exit 1
fi
assert_contains "$out" "$a" 'run#starts-from-last: replacing the draft pin identifies its entry release'
cp "$sandbox/task-a.toml" "$release_task_run"

# Approved snapshots take priority over edited run files and the new project lock.
sed -e "s/^version = .*/version = \"${b%%@*}\"/" -e "s/${a#*@}/${b#*@}/" "$sandbox/run-a.toml" > "${plan%.md}.run.toml"
assert_contains "$(cd "$sandbox" && runweld run show "$plan" --json)" "${a#*@}" 'distribution#project-lock: an approved run retains A'
assert_contains "$(cd "$sandbox" && runweld help agents --plan "$plan")" "$a" 'distribution#project-lock: help can follow the run from another directory'
sed '/^\[workflow\]$/{N;N;d;}' "$sandbox/run-a.toml" > "${plan%.md}.run.toml"
if out=$(cd "$sandbox" && runweld plan approve "$plan" --revision old --by 'Fixture Human' --words 'Accept edited checks' 2>&1); then
  echo 'run#changes-through-approve: approving other edits cannot unpin an active run' >&2
  exit 1
fi
assert_contains "$out" '[workflow]' 'run#changes-through-approve: the refusal identifies the removed pin'
cp "$sandbox/run-a.toml" "${plan%.md}.run.toml"
(cd "$sandbox" && runweld phase start "$plan" 1) >/dev/null
brief=$(cd "$sandbox" && runweld brief implementer "$plan" 1 --provider Test)
assert_contains "$(cat "$brief")" "$engine_a/agents/implementer.md" 'distribution#project-lock: run briefs still use A'
assert_contains "$(cat "$brief")" 'runweld tdd' 'distribution#system-cli: a phase can depend on an installed skill'
(cd "$repo_worktree" && runweld status --current --json --provider Test) > "$sandbox/status.json"
python3 - "$sandbox/status.json" "$brief" "$engine_a" <<'PY'
import json, sys
from pathlib import Path
view, brief, release = sys.argv[1:]
row, = json.loads(Path(view).read_text())
step, = (s for s in row['workflow']['actions'] if s.get('role') == 'implementer' and s['kind'] == 'work')
assert step['assignment']['brief'] == {'path': brief, 'dispatch': 'unverified'}
assert not any(s['kind'] == 'run' and s.get('role') == 'implementer' for s in row['workflow']['actions'])
assert step['assignment']['role_source'] == f'{release}/agents/implementer.md'
PY

# Missing or changed contents must not select a fallback or alter the lock or run.
cp .runweld/runweld.lock "$sandbox/lock-before"
printf 'broken\n' > "$engine_a/references/SESSIONS.md"
if out=$(runweld update --project "$a" 2>&1); then
  echo 'distribution#project-lock: a damaged candidate must not update the lock' >&2
  exit 1
fi
assert_contains "$out" 'references/SESSIONS.md' 'distribution#project-lock: update identifies damaged contents'
cmp .runweld/runweld.lock "$sandbox/lock-before"
cp "${plan%.md}.json" "$sandbox/run-before"
if out=$(cd "$sandbox" && runweld phase done "$plan" 1 2>&1); then
  echo 'distribution#project-lock: a damaged locked run cannot execute' >&2
  exit 1
fi
assert_contains "$out" "$a" 'distribution#project-lock: a damaged run names its release'
if out=$(cd "$release_task_tree" && runweld task resume release-task 2>&1); then
  echo 'distribution#project-lock: a task resume cannot substitute the current release' >&2
  exit 1
fi
assert_contains "$out" "$a" 'distribution#project-lock: resume identifies the damaged task release'
if out=$(runweld task path release-task browser-test 2>&1); then
  echo 'distribution#project-lock: task artifact routing cannot substitute the current release' >&2
  exit 1
fi
assert_contains "$out" "$a" 'distribution#project-lock: task path names the damaged entry release'
if out=$(cd "$release_task_tree" && runweld status --current --json 2>&1); then
  echo 'distribution#project-lock: current task guidance cannot substitute the current release' >&2
  exit 1
fi
assert_contains "$out" "$a" 'distribution#project-lock: current task guidance names the damaged entry release'
cmp "${plan%.md}.json" "$sandbox/run-before"
if out=$(cd "$sandbox" && runweld --release "$b" phase done "$plan" 1 2>&1); then
  echo 'distribution#project-lock: an issued selector cannot override the run snapshot' >&2
  exit 1
fi
assert_contains "$out" "this run selects $a" 'distribution#project-lock: an explicit mismatch must name the approved release'
cmp "${plan%.md}.json" "$sandbox/run-before"
mv "$engine_a" "$sandbox/missing-a"
if out=$(cd "$sandbox" && runweld brief implementer "$plan" 1 2>&1); then
  echo 'distribution#project-lock: a missing run release must not fall back to B' >&2
  exit 1
fi
assert_contains "$out" 'install' 'distribution#project-lock: a missing run release explains recovery'
assert_contains "$out" "$a" 'distribution#project-lock: a missing run names its exact release'

# Exact repair restores old issued commands without changing the project lock.
mv "$sandbox/missing-a" "$engine_a"
if ! out=$(cd "$sandbox" && "$repo_root/scripts/install-runweld" --prefix "$prefix" 2>&1); then
  echo "distribution#project-lock: reinstalling the exact damaged release repairs it: $out" >&2
  exit 1
fi
cmp .runweld/runweld.lock "$sandbox/lock-before"
assert_contains "$(cd "$sandbox" && runweld help agents --plan "$plan")" "$a" 'distribution#project-lock: the repaired run can use A again'
