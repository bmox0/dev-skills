#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PIPELINE="$here/../../workflow/build/pipeline.py"
export SUMMARY_FIXTURE="$here/../lib/summary.md"
python3 -B <<'PY'
import json, os, pathlib, shlex, subprocess, tempfile, tomllib

presets = '''## Executors

```toml
[executors."GPT".primary]
model = "gpt-custom"
effort = "ultra"
[executors."GPT".secondary]
model = "gpt-custom"
effort = "high"
[executors."Claude".primary]
model = "opus-custom"
[executors."Claude".secondary]
model = "sonnet-custom"
effort = "medium"
[executors."Qwen".primary]
model = "qwen-custom"
effort = "xhigh"
[executors."Qwen".secondary]
model = "qwen-custom"
[executors."Other / provider".primary]
model = "arbitrary model"
[executors."Other / provider".secondary]
model = "another model"
```
'''
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory).resolve()
    def command(*args):
        return subprocess.run(args, cwd=root, text=True, capture_output=True)
    def git(*args):
        result = command('git', *args)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()
    def cli(*args, ok=True, code=None):
        result = command('python3', '-B', os.environ['PIPELINE'], *map(str, args))
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        if code:
            assert code in result.stdout, result.stdout
        return result.stdout
    git('init', '-q', '-b', 'main')
    git('config', 'user.name', 'Test')
    git('config', 'user.email', 'test@example.org')
    agents = root / 'AGENTS.md'
    agents.write_text(presets)
    (root / 'src').mkdir()
    (root / 'src/a').write_text('base\n')
    git('add', '.')
    git('commit', '-qm', 'base')
    plans = root / '.runweld/workflow/plans'
    plans.mkdir(parents=True)
    plan = plans / '2026-11-17-executors.md'
    # run#starts-from-last: all current providers replace copied presets; task scalars stay as written.
    cli('run', 'new', plan)
    run = plan.with_suffix('.run.toml')
    values = tomllib.loads(run.read_text())
    assert values['run'] == {}
    assert set(values.get('executors', {})) == {'GPT', 'Qwen', 'Claude', 'Other / provider'}, 'new runs must snapshot all current AGENTS providers'
    # run#executor-presets: planning helpers select current AGENTS without a plan.
    selected = json.loads(cli('executor', 'show', '--provider', 'Other / provider', '--json'))
    assert selected['primary'] == {'model': 'arbitrary model'}
    assert selected['source'] == str(agents)
    for provider in ['', ' ', 'GPT\nQwen']:
        cli('executor', 'show', '--provider', provider, ok=False, code='bad-provider')
    task_values = 'gpt_primary_model = "task-owned"\nquota = 33\nadmin_pwd = "keychain:app/admin"\nmessage = """\n[executors.fake.primary]\nmodel = "task data"\n"""\n'
    run.write_text(run.read_text() + task_values)
    agents.write_text(presets.replace('gpt-custom', 'new-gpt'))
    copied_plan = plans / '2026-11-18-copied.md'
    cli('run', 'new', copied_plan)
    copied = copied_plan.with_suffix('.run.toml').read_text()
    assert task_values in copied
    assert tomllib.loads(copied)['executors']['GPT']['primary']['model'] == 'new-gpt'
    cli('run', 'check', copied_plan)
    # A header-looking line inside a fixed string cannot move the snapshot into that string.
    copied_plan.with_suffix('.run.toml').write_text(copied.replace('dev = "npm run dev -- --port {port}"', 'dev = """echo\n[run]\n"""'))
    another_plan = plans / '2026-11-19-another.md'
    cli('run', 'new', another_plan)
    another = tomllib.loads(another_plan.with_suffix('.run.toml').read_text())
    assert another['checks']['dev'] == 'echo\n[run]\n'
    assert another['executors']['GPT']['primary']['model'] == 'new-gpt'
    # run#contract-checked: fixed nested fields name their complete paths; identifiers are opaque.
    good = run.read_text()
    for old, new, path in [
        ('model = "gpt-custom"', 'models = "wrong"', 'executors."GPT".primary.models'),
        ('[executors."GPT".secondary]', '[executors."GPT".helper]', 'executors."GPT".helper'),
        ('model = "gpt-custom"', 'model = "  "', 'executors."GPT".primary.model'),
        ('model = "gpt-custom"', 'model = 42', 'executors."GPT".primary.model'),
        ('effort = "ultra"', 'effort = "\\n"', 'executors."GPT".primary.effort'),
        ('[executors."GPT".primary]', '[executors."".primary]', 'executors.""'),
    ]:
        run.write_text(good.replace(old, new, 1))
        cli('run', 'check', plan, ok=False, code=path)
    run.write_text(good)
    agents.write_text(presets.replace('effort = "ultra"', 'strength = "ultra"'))
    missing = plans / '2026-11-19-bad.md'
    cli('run', 'new', missing, ok=False, code='executors."GPT".primary.strength')
    assert not missing.with_suffix('.run.toml').exists()
    agents.write_text('## Environment\n')
    cli('run', 'new', missing, ok=False, code='Executors')
    # run#executor-presets: host imports cannot replace literal project-root profiles.
    (root / 'profiles.md').write_text(presets)
    agents.write_text('@profiles.md\n')
    cli('executor', 'show', '--provider', 'GPT', ok=False, code='executors-missing')
    agents.write_text(presets)
    # run#changes-through-approve: selection freezes on consent, even after AGENTS changes.
    plan.write_text('''# Plan: executors

Status: draft · branch `executors` · base `<sha>`
Prototype: none

## Result

R.

## Approach

A.

## Out of scope

- n

## Phases

### 1. One — `waiting`

Territory: `src/`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — CLI

## Done

1. a → b

## Spec

none
''')
    run.write_text(good.replace('full = ["scripts/check", "scripts/test"]', 'full = []'))
    cli('approve', plan)
    agents.write_text(presets.replace('gpt-custom', 'current-gpt'))
    assert json.loads(cli('executor', 'show', plan, '--provider', 'GPT', '--json'))['primary']['model'] == 'current-gpt'
    plan.with_suffix(".summary.md").write_bytes(pathlib.Path(os.environ["SUMMARY_FIXTURE"]).read_bytes())
    review = json.loads(cli('plan', 'review', plan, '--json'))
    cli('plan', 'approve', plan, '--revision', review['revision'], '--by', 'Mina', '--words', 'approve fixture plan and run')
    agents.write_text('## Executors\n\n```toml\ninvalid TOML\n```\n')
    selected = json.loads(cli('executor', 'show', plan, '--provider', 'Claude', '--json'))
    assert selected['primary'] == {'model': 'opus-custom'}
    assert selected['secondary'] == {'model': 'sonnet-custom', 'effort': 'medium'}
    assert selected['source'] == 'approved run snapshot'
    refused = cli('executor', 'show', plan, '--provider', 'Missing', ok=False, code='executors."Missing"')
    assert 'renewed human approval' in refused
    # Removing the approved presets must not produce a new worker assignment.
    state_file = plan.with_suffix('.json')
    saved_state = state_file.read_bytes()
    without_profiles = json.loads(saved_state)
    del without_profiles['run']['executors']
    state_file.write_text(json.dumps(without_profiles))
    cli('executor', 'show', plan, '--provider', 'GPT', ok=False, code='executors."GPT"')
    cli('brief', 'implementer', plan, '1', ok=False, code='approval-snapshot')
    state_file.write_bytes(saved_state)
    cli('build', 'start', plan, '--base', 'main', ok=False, code='provider-required')
    cli('build', 'start', plan, '--base', 'main', '--provider', 'GPT')
    def brief(kind, tier, *extra):
        path = pathlib.Path(cli('brief', kind, plan, *extra, '--provider', 'GPT').strip())
        text = path.read_text()
        assert f'Executor tier: {tier}' in text, text
        assert 'Executor model: gpt-custom' in text, text
        assert f'Executor effort: {"ultra" if tier == "primary" else "high"}' in text, text
        assert 'AGENTS.md' in text and 'CLAUDE.md' not in text
        # build#worker-role-bound: every brief binds its authoritative role and protocol.
        package = pathlib.Path(os.environ['PIPELINE']).resolve().parents[2]
        role = 'implementer' if kind in ('implementer', 'fix', 'round') else kind
        source = package / ('workflow/verify/GUIDE.md' if role == 'verify' else f'agents/{role}.md')
        assert f'Role: {role}' in text, text
        assert f'Role source: {source}' in text, text
        assert f'Protocol: {package / "references/SESSIONS.md"}' in text, text
        assert 'Initialization evidence:' in text and 'Continuation:' in text, text
        assert 'confirmed stopped' in text and 'write-capable jobs' in text, text
        assert 'Return contact: dispatching build coordinator' in text, text
        return text
    def complete_review(text):
        prefix = '- Complete the review: '
        args = shlex.split(next(line.removeprefix(prefix) for line in text.splitlines() if line.startswith(prefix)))
        result = command(*args)
        assert result.returncode == 0, result.stdout + result.stderr
    brief('implementer', 'secondary', '1')
    cli('phase', 'start', plan, '1')
    (root / 'src/a').write_text('built\n')
    git('commit', '-qm', 'phase', '--', 'src/a')
    cli('phase', 'report', plan, '1', '--became', 'built', '--commit', git('rev-parse', 'HEAD'),
        '--check', 'scripts/check', 'failed: scripts/check is missing in the throwaway repository')
    cli('phase', 'done', plan, '1')
    cli('gate', 'start', plan)
    brief('verify', 'secondary')
    cli('finding', plan, '--kind', 'defect', '--where', 'src/a:1', '--source', 'plan', '--text', 'fix fixture')
    complete_review(brief('reviewer', 'primary'))
    cli('fix', 'start', plan)
    brief('fix', 'secondary')
    cli('fix', 'report', plan, '--became', 'no change needed')
    cli('fix', 'done', plan)
    complete_review(brief('reviewer', 'secondary'))
    brief('judge', 'primary')
    # build#judge-file-by-code: open engine names, first prediction required, later file immutable.
    cli('verdict', 'pass', plan, '--report', 'ready', '--engine', 'qwen', ok=False, code='no-prediction')
    for engine in ['', '  ', 'qwen\npi', 'qwen\rpi']:
        cli('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', engine, ok=False, code='bad-engine')
    for engine in ['qwen', 'pi', 'hermes']:
        judge = plan.with_suffix('.judge.md')
        if judge.exists():
            judge.unlink()
        # Each first-verdict case starts from the same real, settled gate snapshot.
        state = plan.with_suffix('.json')
        saved = state.read_bytes()
        cli('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', engine)
        assert f' · engine {engine}\n' in judge.read_text()
        first = judge.read_bytes()
        cli('verdict', 'pass', plan, '--report', 'later')
        assert first == judge.read_bytes()
        state.write_bytes(saved)
    cli('verdict', 'round', plan, '--report', 'one round', '--predicted', 'pass', '--engine', 'qwen', '--note', 'fixture note', 'bug')
    cli('round', 'start', plan)
    brief('round', 'secondary')
    cli('round', 'report', plan, '--became', 'no change needed')
    cli('round', 'done', plan)
    complete_review(brief('reviewer', 'secondary'))
    brief('judge', 'primary')
PY
