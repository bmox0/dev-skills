#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"
tmp=$(mktemp_dir)
mkdir -p "$tmp/bin"
cat > "$tmp/bin/qodercli" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--version']:
    print('Qoder fixture-1.2.3')
elif sys.argv[1:3] == ['plugin', 'validate']:
    print(json.dumps({'ok': os.environ.get('FAIL_VALIDATE') != '1'}))
elif sys.argv[1:3] == ['plugin', 'list']:
    from pathlib import Path
    root = Path(sys.argv[-1])
    print(json.dumps([{'name': 'dev-skills', 'enabled': True,
                      'installPath': str(root), 'version': json.loads((root/'.qoder-plugin/plugin.json').read_text())['version'],
                      'resources': {'skills': [{'name': p.parent.name} for p in (root/'skills').glob('*/SKILL.md')],
                                    'agents': [{'name': 'dev-skills:'+p.stem} for p in (root/'agents').glob('*.md')],
                                    'hooks': [{'event': 'SessionStart'}, {'event': 'PostToolUse'}]}}]))
else:
    sys.exit(99)
STUB
chmod +x "$tmp/bin/qodercli"
# validation#selected-host-checks: the explicitly selected native validator names its coverage.
out=$(PATH="$tmp/bin:$PATH" python3 -B "$repo_root/scripts/check" --host qoder 2>&1)
assert_contains "$out" "Qoder fixture-1.2.3" "Qoder version is named"
assert_contains "$out" "live execution not checked" "loader does not claim execution"
if PATH="$tmp/bin:$PATH" FAIL_VALIDATE=1 python3 -B "$repo_root/scripts/check" --host qoder > "$tmp/failure" 2>&1; then
  echo "validation#selected-host-checks: failed Qoder validation passed" >&2; exit 1
fi
mkdir -p "$tmp/no-client"
ln -s "$(command -v python3)" "$tmp/no-client/python3"
if PATH="$tmp/no-client" "$tmp/no-client/python3" -B "$repo_root/scripts/check" --host qoder > "$tmp/missing" 2>&1; then
  echo "validation#selected-host-checks: unavailable Qoder passed" >&2; exit 1
fi
assert_contains "$(cat "$tmp/missing")" "'qodercli' is not on PATH" "missing selected host is named"
# distribution#shared-resources: relocated code uses its resources and the target's profiles.
python3 -B - "$repo_root" "$tmp" <<'PYRELOCATED'
import hashlib, json, os, pathlib, shutil, subprocess, sys
source, tmp = (pathlib.Path(p).resolve() for p in sys.argv[1:])
package = tmp / 'relocated package $'
shutil.copytree(source, package, ignore=shutil.ignore_patterns('.git', '.runweld/workflow', '__pycache__'))
project = tmp / 'target'
project.mkdir()
subprocess.run(['git', 'init', '-q', str(project)], check=True)
(project / 'AGENTS.md').write_text('''## Executors

```toml
[executors."Fixture".primary]
model = "project-primary"
[executors."Fixture".secondary]
model = "project-secondary"
```
''')
run = subprocess.run([sys.executable, '-B', str(package / 'scripts/check')], cwd=project,
                     capture_output=True, text=True)
assert run.returncode == 0, run
run = subprocess.run([sys.executable, '-B', str(package / 'skills/build/pipeline.py'),
                      'executor', 'show', '--provider', 'Fixture'], cwd=project, capture_output=True, text=True)
assert run.returncode == 0 and 'project-primary' in run.stdout and str(project / 'AGENTS.md') in run.stdout, run
assert not (project / 'skills').exists() and not (package / '.runweld/workflow').exists()
for folder in ('agents', 'references', 'skills', 'hooks', 'scripts', 'adapters'):
    for original in (source / folder).rglob('*'):
        if original.is_file() and '__pycache__' not in original.parts:
            copied = package / original.relative_to(source)
            assert hashlib.sha256(original.read_bytes()).digest() == hashlib.sha256(copied.read_bytes()).digest(), copied
            assert original.stat().st_mode & 0o111 == copied.stat().st_mode & 0o111, copied
plans = project / '.runweld/workflow/plans'
plans.mkdir(parents=True)
(plans / 'fixture.json').write_text('{}')
variables = ('CLAUDE_PLUGIN_ROOT', 'PLUGIN_ROOT', 'QODER_PLUGIN_ROOT')
env = {k: v for k, v in os.environ.items() if k not in variables}
for host, variable in zip(('claude', 'codex', 'qoder'), variables):
    manifest = json.loads((package / f'.{host}-plugin/plugin.json').read_text())
    hooks = json.loads((package / manifest['hooks']).read_text())['hooks']
    command = hooks['PostToolUse'][0]['hooks'][0]['command']
    payload = {'hook_event_name': 'PostToolUse', 'tool_name': 'Write', 'cwd': str(project),
               'tool_input': {'file_path': str(plans / 'fixture.notes.md')}}
    run = subprocess.run(['bash', '-c', command], input=json.dumps(payload), cwd=project,
                         env=dict(env, **{variable: str(package)}), capture_output=True, text=True)
    assert run.returncode == 0 and 'note add|edit|drop' in run.stdout and not run.stderr, (host, run)
assert not list(package.rglob('__pycache__'))
PYRELOCATED

echo ok
