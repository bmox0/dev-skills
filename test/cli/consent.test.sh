#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PIPELINE="$here/../../workflow/build/pipeline.py"
python3 -B <<'PY'
import json, os, pathlib, subprocess, tempfile

with tempfile.TemporaryDirectory(prefix='consent repo ') as directory:
    root = pathlib.Path(directory).resolve()
    def command(*args):
        return subprocess.run(args, cwd=root, text=True, capture_output=True)
    def git(*args):
        result = command('git', *args)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()
    def cli(*args, ok=True, code=None):
        result = command('python3', '-B', os.environ['PIPELINE'], *map(str, args))
        assert 'Traceback' not in result.stderr, result.stdout + result.stderr
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        if code:
            assert code in result.stdout, result.stdout + result.stderr
        return result.stdout
    git('init', '-q', '-b', 'main')
    git('config', 'user.name', 'Test')
    git('config', 'user.email', 'test@example.org')
    (root / '.runweld/workflow/plans').mkdir(parents=True)
    (root / 'src').mkdir()
    (root / 'src/a').write_text('base\n')
    git('add', 'src')
    git('commit', '-qm', 'base')
    plan = root / '.runweld/workflow/plans/2026-11-17-consent.md'
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
port = false
data_dir = false
[finish]
how = "ff-only"
target = "main"
delete_backups = false
[run]
[executors.GPT.primary]
model = "planner"
[executors.GPT.secondary]
model = "worker"
effort = "high"
''')
    def state():
        return json.loads(plan.with_suffix('.json').read_text())
    def unchanged(*args, code):
        before = plan.with_suffix('.json').read_bytes()
        cli(*args, ok=False, code=code)
        assert before == plan.with_suffix('.json').read_bytes()
    compiled = plan.with_suffix('.json')
    def facts():
        files = [plan, compiled, run, shape, epic]
        return ([(p.stat().st_mode, p.read_bytes() if p.is_file() and os.access(p, os.R_OK) else None)
                 if p.exists() else None for p in files],
                git('show-ref'), git('branch', '--show-current'))
    def invalid_file(path, *args, malformed):
        original = path.read_bytes()
        for bad, reason in [
            (None, 'does not exist'), (b' \n', 'empty'), (b'\xff', 'UTF-8'),
            ('directory', 'regular file'), ('unreadable', 'cannot read'), (malformed, None),
        ]:
            path.unlink()
            if bad == 'directory':
                path.mkdir()
            elif bad == 'unreadable':
                path.write_bytes(original)
                path.chmod(0)
                if os.access(path, os.R_OK):
                    path.chmod(0o600)
                    continue
            elif bad is not None:
                path.write_bytes(bad)
            before = facts()
            output = cli(*args, ok=False)
            assert str(path) in output and 'fix:' in output and 'Traceback' not in output, output
            assert 'run-stale' not in output and 'plan-stale' not in output, output
            if reason:
                assert reason in output, output
            assert before == facts(), output
            if bad == 'directory':
                path.rmdir()
            elif bad == 'unreadable':
                path.chmod(0o600)
            path.write_bytes(original)
    # planning#summary-before-build, run#required-to-approve
    epic = plan.parent.parent / 'epic.md'
    epic.write_text('# Epic\n\n## Plans\n\n| # | Plan | Waits for | Status |\n|---|---|---|---|\n| 1 | Consent | — | |\n')
    plan.write_text(plan.read_text().replace('Prototype: none', 'Epic: .runweld/workflow/epic.md · row 1\nPrototype: none'))
    cli('approve', plan)
    assert state()['status'] == 'draft', 'validation must not grant consent'
    summary_path = plan.with_suffix('.summary.md')
    cli('plan', 'review', plan, ok=False, code='bad-summary')
    unchanged('plan', 'approve', plan, '--by', 'Mina', '--words', 'yes', '--revision', 'old', code='bad-summary')
    current_state = compiled.read_bytes()
    legacy_state = state()
    del legacy_state['summary_required']
    compiled.write_text(json.dumps(legacy_state))
    legacy = json.loads(cli('plan', 'review', plan, '--json'))
    assert legacy['summary'] is None and '1. a → b' in cli('plan', 'review', plan)
    compiled.write_bytes(current_state)
    for invalid in ['', 'word ' * 351]:
        summary_path.write_text(invalid)
        cli('plan', 'review', plan, ok=False, code='bad-summary')
    example = pathlib.Path(os.environ['PIPELINE']).resolve().parents[1] / 'plan/references/resume.example.md'
    summary = example.read_text().replace('(example.md)', f'({plan.name})').replace(
        '(../../run-file/references/example.run.toml)', f'({run.name})')
    assert [s for s in summary.splitlines() if s.startswith('## ')] == [
        '## Result', '## Phases', '## Spec change', '## Checks', '## Scope and limits', '## Your approval']
    summary_path.write_text(summary + ' word' * (350 - len(summary.split())))
    assert json.loads(cli('plan', 'review', plan, '--json'))['summary'] == summary_path.read_text()
    summary_path.write_text(summary.replace('## Checks', '## 4. Проверки'))
    assert 'Проверки' in cli('plan', 'review', plan)
    for invalid, reason in [(summary.replace('## Checks', '## 5. Проверки'), 'section 4 (Checks)'),
                            (summary.replace('## Scope and limits', '## Checks'), 'repeats'),
                            (summary[:summary.index('## Your approval')], 'section 6 (Your approval)'),
                            (summary.split('## Your approval')[0] + '## Your approval\n<!-- TODO -->', 'empty section')]:
        summary_path.write_text(invalid)
        assert reason in cli('plan', 'review', plan, ok=False, code='bad-summary')
    summary_path.write_text(summary)
    before = compiled.read_bytes(), plan.read_bytes(), git('show-ref')
    review = json.loads(cli('plan', 'review', plan, '--json'))
    assert review['summary'] == summary and review['revision'] != legacy['revision'], review
    assert review['summary_path'] == str(summary_path)
    screen = cli('plan', 'review', plan)
    assert screen.startswith('Approval summary\n\n' + summary) and plan.as_uri() in screen and run.as_uri() in screen
    assert summary_path.as_uri() in screen
    assert '1. a → b' not in screen and '[executors.GPT.primary]' not in screen
    assert '1. a → b' in review['plan'] and 'target = "main"' in review['run_toml'], review
    assert (compiled.read_bytes(), plan.read_bytes(), git('show-ref')) == before, 'review is read-only'
    run.write_text(run.read_text().replace('delete_backups = false', 'delete_backups = true'))
    proposal = json.loads(cli('run', 'show', '--json', plan))
    assert not proposal['approved'] and proposal['run']['finish']['delete_backups'] is True, 'unapproved readers show the proposal'
    run.write_text(run.read_text().replace('delete_backups = true', 'delete_backups = false'))
    unchanged('build', 'start', plan, '--base', 'main', code='plan-unapproved')
    unchanged('plan', 'status', plan, 'passed', '--note', 'shortcut', code='plan-unapproved')

    human = 'Mina Patel'
    shape = plan.with_suffix('.shape.toml')
    def display():
        return json.loads(cli('plan', 'review', plan, '--json'))
    def approve_revision(*extra, words='I approve this plan and its run configuration.'):
        reviewed = display()
        assert reviewed['approval_command']['cwd'] == str(root), reviewed
        argv = reviewed['approval_command']['argv'][2:]
        assert argv[:3] == ['plan', 'approve', str(plan)], argv
        cli(*argv, '--by', human, '--words', words, *extra)

    # build#required-transition-files: approval and build refuse corrupt inputs before mutating state.
    invalid_file(epic, 'approve', plan, malformed=b'# Epic\n\n## Plans\n\n| 1 |')
    for path, malformed in [(plan, b'# Only a title\n'), (compiled, b'{"status":"approved"}'),
                            (run, b'[unexpected]\nx = 1')]:
        invalid_file(path, 'build', 'start', plan, '--base', 'main', malformed=malformed)
    invalid_file(compiled, 'build', 'start', plan, '--base', 'main',
                 malformed=json.dumps({**state(), 'phases': [None]}).encode())
    invalid_file(compiled, 'build', 'start', plan, '--base', 'main',
                 malformed=json.dumps({**state(), 'approvals': {'plan': []}}).encode())
    unchanged('plan', 'approve', plan, '--revision', review['revision'], '--by', human,
              '--words', 'yes', '--acceptor', 'Controller', code='no-authority')
    before = git('show-ref')
    approve_revision()
    approved = state()
    assert approved['status'] == 'approved' and git('show-ref') == before
    assert set(approved['approvals']) == {'plan'} and approved['approvals']['plan']['by'] == human
    assert approved['approvals']['plan']['acceptor'] == human
    assert approved['approvals']['plan']['summary'] == summary
    summary_path.write_text(summary + '\nChanged promise.')
    assert '+Changed promise.' in display()['diff'] and not display()['current']
    unchanged('plan', 'approve', plan, '--revision', review['revision'], '--by', human, '--words', 'yes', code='review-stale')
    unchanged('build', 'start', plan, '--base', 'main', code='plan-stale')
    summary_path.unlink()
    unchanged('build', 'start', plan, '--base', 'main', code='bad-summary')
    summary_path.write_text(summary)
    approve_revision()
    assert state() == approved, 'a duplicate approval must not create a new decision'
    unchanged('phase', 'start', plan, '1', '--note', 'shortcut', code='not-building')

    # run#changes-through-approve: do not apply the revision displayed before a material edit.
    run.write_text(run.read_text().replace('target = "main"', 'target = "release"'))
    fresh = display()
    assert not fresh['current'] and fresh['revision'] != review['revision']
    assert '+    "target": "release"' in fresh['diff'] and '-    "target": "main"' in fresh['diff']
    assert '+    "target": "release"' in cli('plan', 'review', plan)
    assert '[finish] target' in cli('status', plan)
    unchanged('plan', 'approve', plan, '--revision', review['revision'], '--by', human,
              '--words', 'yes', code='review-stale')
    unchanged('build', 'start', plan, '--base', 'main', code='run-stale')
    run.write_text(run.read_text().replace('target = "release"', 'target = "main"'))
    assert display()['current'], 'restoring the approved proposal restores its consent'
    started = json.loads(cli('build', 'start', plan, '--base', 'main', '--json'))
    assert not started['resumed'] and started['build_provider'] == 'GPT' and started['active_phases'] == []
    cli('phase', 'start', plan, '1')
    # build#start-chosen: restarting reports the same phase and executor and does not write.
    before = facts()
    current = json.loads(cli('build', 'start', plan, '--json'))
    assert current['resumed'] and current['tree'] == started['tree'] and current['branch'] == started['branch']
    assert [(p['n'], p['executor']['model'], p['executor']['effort']) for p in current['active_phases']] == [(1, 'worker', 'high')]
    assert 'Active phase 1: One — GPT worker (effort high)' in cli('build', 'start', plan)
    assert facts() == before, 'a repeated start must not change refs or state'
    unchanged('build', 'start', plan, '--provider', 'Another', code='build-assignment')
    assert display()['revision'] == review['revision'], 'execution progress is not a material edit'
    run.write_text(run.read_text() + '\n# An annotation about these settings.\n')
    assert display()['revision'] == review['revision'] and display()['current']

    plan.write_text(plan.read_text().replace('1. a → b', '1. a → changed criterion'))
    assert 'plan-stale' in cli('plan', 'review', plan)
    edit = display()
    assert edit['approval_command'] is None and '+1. a → changed criterion' in edit['diff'], edit
    cli('approve', plan)
    unchanged('build', 'start', plan, code='plan-stale')
    run.write_text(run.read_text().replace('model = "worker"', 'model = "next-worker"'))
    approve_revision()
    assert state()['status'] == 'building' and state()['phases'][0]['status'] == 'in progress'
    assert 'Executor model: worker\n' in pathlib.Path(cli('brief', 'implementer', plan, '1').strip()).read_text()
    assert 'Active phase 1: One — GPT worker (effort high)' in cli('build', 'start', plan)
    (root / 'src/a').write_text('built\n')
    git('commit', '-qam', 'build')
    cli('phase', 'report', plan, '1', '--became', 'built', '--commit', git('rev-parse', 'HEAD'))
    cli('phase', 'done', plan, '1')
    # build#state-through-commands: a note cannot replace stages.
    unchanged('plan', 'status', plan, 'passed', '--note', 'shortcut', code='no-land')
    unchanged('plan', 'status', plan, 'https://example.org/1', code='no-request')
    unchanged('plan', 'status', plan, 'merged', code='finish-required')
    cli('gate', 'start', plan)
    # build#required-transition-files: nested records name their field and repair at the CLI boundary.
    def bad_record(change, field, *args):
        original = compiled.read_bytes()
        corrupt = state()
        change(corrupt)
        compiled.write_text(json.dumps(corrupt))
        before = (compiled.read_bytes(), plan.read_bytes(), git('show-ref'))
        try:
            output = cli(*args, ok=False, code='bad-state')
            assert str(compiled) in output and field in output and 'fix:' in output, output
            assert before == (compiled.read_bytes(), plan.read_bytes(), git('show-ref'))
        finally:
            compiled.write_bytes(original)
    for key, bad, field in (
        ('findings', [{}], 'findings[0].id'), ('results', [{}], 'results[0].case'),
        ('results', [dict(case=1, outcome='bogus', do='a', see='b', width='-', detail=None, capture=None, at='today')], 'results[0].outcome'),
        ('fixes', [{}], 'fixes[0].n'), ('reviews', [{}], 'reviews[0].range'),
        ('current_run', 100, 'current_run'),
    ):
        bad_record(lambda st: st['cycles'][0].update({key: bad}), 'state.cycles[0].' + field, 'status', '--json', plan)
    bad_record(lambda st: st.update(check_transition={'id': 'broken'}), 'state.check_transition.cycle', 'status', '--json', plan)
    (root / 'src/a').write_text('built after checks\n')
    git('commit', '-qam', 'after checks')
    unchanged('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', 'codex', code='checks-stale')
    cli('gate', 'start', plan)
    cli('review', 'complete', plan, '--assignment', 'gate', '--range', f"{git('rev-parse', 'main')}..{git('rev-parse', 'HEAD')}")
    unchanged('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', 'codex', code='result-missing')
    cli('result', plan, '--case', '1', '--outcome', 'passed', '--capture', 'CLI output')
    cli('verdict', 'pass', plan, '--report', 'ready', '--predicted', 'pass', '--engine', 'codex', '--decide', 'check-1', 'let-through', 'deliberately failing fixture check')
    # build#required-transition-files: both status formats validate verdict fields before rendering.
    def stopped_without_proposals(verdict):
        verdict.update(kind='round', stop='fixes spent')
        del verdict['stopped_notes']
    for field, change in (
        ('stopped_notes', stopped_without_proposals),
        ('evidence_note', lambda verdict: verdict.update(evidence_note={'text': 'bad'})),
        ('owed', lambda verdict: verdict.update(kind='evidence-owed', owed='unknown-verifier')),
        ('owed', lambda verdict: verdict.update(kind='evidence-owed', owed=None)),
    ):
        for flags in ((), ('--json',)):
            bad_record(lambda st: change(st['verdicts'][0]), f'state.verdicts[0].{field}', 'status', *flags, plan)
    cli('land', 'draft', plan)
    shape.write_text(shape.read_text().replace('message = ""', 'message = "built"').replace('walkthrough = ""', 'walkthrough = "CLI built"'))
    # build#required-transition-files: a bad shape never creates the backup or starts the rewrite.
    invalid_file(shape, 'land', plan, malformed=b'[[commit]]\npaths = []')
    hook = root / '.git/hooks/pre-commit'
    hook.write_text('#!/bin/sh\necho formatted >> src/a\ngit add src/a\n')
    hook.chmod(0o755)
    cli('land', plan)
    hook.unlink()
    cli('land', 'accept', plan, '--note', 'keep formatter output')
    unchanged('plan', 'status', plan, 'passed', code='no-page')
    guide = '\n\n#### Checks\n\n- —\n\n#### Decisions\n\n- —'
    bound_land = compiled.read_bytes()
    unbound_land = state()
    del unbound_land['lands'][-1]['judge']
    compiled.write_text(json.dumps(unbound_land))
    unchanged('page', plan, '--guide', 'Try CLI.' + guide, code='judge-stale')
    compiled.write_bytes(bound_land)
    cli('page', plan, '--guide', 'Try CLI.' + guide)
    assert 'keep formatter output' in plan.read_text()
    unchanged('plan', 'status', plan, 'passed', code='acceptance-required')
    unchanged('accept', plan, '--by', 'router', '--words', 'yes', code='unauthorized-acceptor')
    cli('accept', plan, '--by', human, '--words', 'yes, finish')
    assert state()['status'] == 'passed'
    # run#changes-through-approve, finish#merge-needs-land
    approve_revision(words='I reaffirm the plan and run configuration.')
    unchanged('finish', plan, code='page-stale')
    cli('plan', 'status', plan, 'building')
    cli('page', plan, '--guide', 'Try the refreshed CLI.' + guide)
    cli('accept', plan, '--by', human, '--words', 'yes again')
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
    approve_revision('--acceptor', 'controller', '--authority', 'The controller may accept this result')
    cli('plan', 'status', plan, 'building')
    cli('page', plan, '--guide', 'Review the delegated result.' + guide)
    action, = json.loads(cli('status', plan, '--json'))['workflow']['actions']
    assert action['owner'] == 'Human' and action['acceptor'] == 'controller'
    assert action['authority'] == 'The controller may accept this result'
    assert action['command']['argv'][-2:] == ['--by', 'controller']
    assert action['command']['options']['words'] == '--words ACCEPTANCE'
    unchanged('accept', plan, '--by', human, '--words', 'yes', code='unauthorized-acceptor')
    cli('accept', plan, '--by', 'controller', '--words', 'approved within my grant')
    cli('finish', plan)
    assert git('rev-parse', 'main') == git('rev-parse', 'consent')
    assert git('branch', '--list', 'backup/consent-1')
    # build#typed-workflow-actions: old lands without a judge binding remain readable without gaining authority.
    historic = state()
    del historic['lands'][0]['judge']
    del historic['verdicts'][0]['evidence_note']
    del historic['verdicts'][0]['stopped_notes']
    del historic['approvals']
    del historic['acceptance']
    compiled.write_text(json.dumps(historic))
    before = compiled.read_bytes()
    assert 'Status: merged' in cli('status', plan)
    view = json.loads(cli('status', '--json', plan))
    assert view['workflow']['actions'] == [] and 'judge' not in view['lands'][0] and view['acceptance'] is None, view
    for scope in ((), ('--current',)):
        assert json.loads(cli('status', '--json', *scope)) == []
        assert cli('status', *scope) == ''
    assert compiled.read_bytes() == before
print('consent.test.sh: ok')
PY
