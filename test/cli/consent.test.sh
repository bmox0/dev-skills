#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PIPELINE="$here/../../skills/build/pipeline.py"
python3 -B <<'PY'
import json, os, pathlib, subprocess, tempfile

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
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
    (root / '.ai-workflow/plans').mkdir(parents=True)
    (root / 'src').mkdir()
    (root / 'src/a').write_text('base\n')
    git('add', 'src')
    git('commit', '-qm', 'base')
    plan = root / '.ai-workflow/plans/2026-11-17-consent.md'
    plan.write_text('''# Plan: consent

Status: draft · branch `consent` · base `<sha>`
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

- Gate: normal — CLI

## Done

1. a → b

## Spec

none
''')
    run = plan.with_suffix('.run.toml')
    run.write_text('''[checks]
phase = []
full = ["false"]
[isolation]
worktree = false
port = false
data_dir = false
[finish]
how = "ff-only"
target = "main"
delete_backups = false
[run]
''')
    def state():
        return json.loads(plan.with_suffix('.json').read_text())
    def unchanged(*args, code):
        before = plan.with_suffix('.json').read_bytes()
        cli(*args, ok=False, code=code)
        assert before == plan.with_suffix('.json').read_bytes()
    # planning#summary-before-build, run#required-to-approve
    cli('approve', plan)
    assert state()['status'] == 'draft', 'validation must not grant consent'
    run.write_text(run.read_text().replace('delete_backups = false', 'delete_backups = true'))
    proposal = json.loads(cli('run', 'show', '--json', plan))
    assert not proposal['approved'] and proposal['run']['finish']['delete_backups'] is True, 'unapproved readers show the proposal'
    run.write_text(run.read_text().replace('delete_backups = true', 'delete_backups = false'))
    unchanged('build', 'start', plan, '--base', 'main', code='run-unapproved')
    unchanged('plan', 'status', plan, 'passed', '--note', 'shortcut', code='run-unapproved')
    cli('run', 'approve', plan, '--by', 'user', '--words', 'approve this run')
    unchanged('build', 'start', plan, '--base', 'main', code='summary-unapproved')
    summary = plan.with_suffix('.summary.md')
    summary.write_text(f'Build [this plan]({plan.name}) in one phase. Check the CLI. No other changes.\n')
    def approve_summary(*extra):
        cli('summary', 'approve', plan, '--file', summary, '--by', 'user', '--words', 'approve this summary', *extra)
    approve_summary()
    assert state()['status'] == 'approved'
    cli('build', 'start', plan, '--base', 'main')
    cli('phase', 'start', plan, '1')
    (root / 'src/a').write_text('built\n')
    git('commit', '-qam', 'build')
    cli('phase', 'report', plan, '1', '--became', 'built', '--commit', git('rev-parse', 'HEAD'))
    cli('phase', 'done', plan, '1')
    # build#state-through-commands: a note cannot replace stages.
    unchanged('plan', 'status', plan, 'passed', '--note', 'shortcut', code='no-land')
    unchanged('plan', 'status', plan, 'https://example.org/1', code='no-request')
    unchanged('plan', 'status', plan, 'merged', code='finish-required')
    cli('gate', 'start', plan)
    (root / 'src/a').write_text('built after checks\n')
    git('commit', '-qam', 'after checks')
    unchanged('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', 'codex', code='checks-stale')
    cli('gate', 'start', plan)
    unchanged('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', 'codex', code='result-missing')
    cli('result', plan, '--case', '1', '--outcome', 'passed', '--capture', 'CLI output')
    cli('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', 'codex', '--decide', 'check-1', 'let-through', 'deliberately failing fixture check')
    cli('land', 'draft', plan)
    shape = plan.with_suffix('.shape.toml')
    shape.write_text(shape.read_text().replace('message = ""', 'message = "built"').replace('walkthrough = ""', 'walkthrough = "CLI built"'))
    hook = root / '.git/hooks/pre-commit'
    hook.write_text('#!/bin/sh\necho formatted >> src/a\ngit add src/a\n')
    hook.chmod(0o755)
    cli('land', plan)
    hook.unlink()
    cli('land', 'accept', plan, '--note', 'keep formatter output')
    unchanged('plan', 'status', plan, 'passed', code='no-page')
    cli('page', plan, '--note', 'try CLI')
    assert 'keep formatter output' in plan.read_text()
    unchanged('plan', 'status', plan, 'passed', code='acceptance-required')
    unchanged('accept', plan, '--by', 'router', '--words', 'yes', code='unauthorized-acceptor')
    cli('accept', plan, '--by', 'user', '--words', 'yes, finish')
    assert state()['status'] == 'passed'
    # run#changes-through-approve, finish#merge-needs-land
    summary.write_text(summary.read_text() + 'Changed.\n')
    unchanged('finish', plan, code='summary-stale')
    approve_summary()
    unchanged('finish', plan, code='page-stale')
    cli('plan', 'status', plan, 'building')
    cli('page', plan, '--note', 'try refreshed CLI')
    cli('accept', plan, '--by', 'user', '--words', 'yes again')
    (root / 'src/a').write_text('changed after acceptance\n')
    git('commit', '-qam', 'late change')
    assert any('judge-stale' in item for item in json.loads(cli('status', '--json', plan))['stale'])
    unchanged('finish', plan, code='judge-stale')
    git('reset', '--hard', state()['lands'][-1]['tip'])
    tip = state()['lands'][-1]['tip']
    git('switch', '-c', 'elsewhere')
    unchecked = git('commit-tree', 'HEAD^{tree}', '-p', 'HEAD', '-m', 'unreviewed ref')
    git('update-ref', 'refs/heads/consent', unchecked)
    unchanged('finish', plan, code='land-stale')
    git('update-ref', 'refs/heads/consent', tip)
    git('switch', 'consent')
    before = git('rev-parse', 'main')
    run.write_text(run.read_text().replace('delete_backups = false', 'delete_backups = true'))
    unchanged('finish', plan, code='run-stale')
    assert before == git('rev-parse', 'main')
    run.write_text(run.read_text().replace('delete_backups = true', 'delete_backups = false'))
    approve_summary('--acceptor', 'controller', '--authority', 'The controller may accept this result')
    cli('plan', 'status', plan, 'building')
    cli('page', plan, '--note', 'review delegated result')
    unchanged('accept', plan, '--by', 'user', '--words', 'yes', code='unauthorized-acceptor')
    cli('accept', plan, '--by', 'controller', '--words', 'approved within my grant')
    cli('finish', plan)
    assert git('rev-parse', 'main') == git('rev-parse', 'consent')
    assert git('branch', '--list', 'backup/consent-1')
print('consent.test.sh: ok')
PY
