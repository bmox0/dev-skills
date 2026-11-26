#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PIPELINE="$here/../../skills/build/pipeline.py"
python3 -B <<'PY'
import json, os, pathlib, subprocess, tempfile
from urllib.parse import quote

with tempfile.TemporaryDirectory(prefix='consent repo ') as directory:
    root = pathlib.Path(directory)
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
    compiled = plan.with_suffix('.json')
    def facts():
        files = [plan, compiled, run, summary, shape, epic]
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
            assert 'run-stale' not in output and 'summary-stale' not in output, output
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
    run.write_text(run.read_text().replace('delete_backups = false', 'delete_backups = true'))
    proposal = json.loads(cli('run', 'show', '--json', plan))
    assert not proposal['approved'] and proposal['run']['finish']['delete_backups'] is True, 'unapproved readers show the proposal'
    run.write_text(run.read_text().replace('delete_backups = true', 'delete_backups = false'))
    unchanged('build', 'start', plan, '--base', 'main', code='run-unapproved')
    unchanged('plan', 'status', plan, 'passed', '--note', 'shortcut', code='run-unapproved')
    cli('run', 'approve', plan, '--by', 'user', '--words', 'approve this run')
    unchanged('build', 'start', plan, '--base', 'main', code='summary-unapproved')
    summary = plan.with_suffix('.summary.md')
    shape = plan.with_suffix('.shape.toml')
    summary.write_text(f'Build [this plan]({plan.name}) in one phase. Check the CLI. No other changes.\n')
    def approve_summary(*extra):
        cli('summary', 'approve', plan, '--file', summary, '--by', 'user', '--words', 'approve this summary', *extra)
    # build#required-transition-files: summary approval validates its candidate.
    invalid_file(summary, 'summary', 'approve', plan, '--file', summary, '--by', 'user', '--words', 'yes',
                 malformed=b'No link to the plan.')
    # planning#summary-before-build: the destination, relative to the summary, must be this plan.
    original = summary.read_text()
    for target in (f'../missing/{plan.name}', f'missing/../{plan.name}', f'not-{plan.name}', f'https://example.test/{plan.name}'):
        summary.write_text(f'Build [this plan]({target}).\n')
        unchanged('summary', 'approve', plan, '--file', summary, '--by', 'user', '--words', 'yes', code='bad-summary')
    summary.write_text(original)
    elsewhere = root / 'review notes'
    elsewhere.mkdir()
    adjacent = summary
    summary = elsewhere / adjacent.name
    for target in (f'../.runweld/workflow/plans/{plan.name}#result "Details"', f'<{plan}>', quote(str(plan))):
        summary.write_text(f'Build [this plan]({target}).\n')
        approve_summary()
    for alias, destination in (
        ('build (draft) &copy;.md', r'<build \(draft\) \&copy;.md>'),
        ('build (draft) &copy;.md', '<build (draft) &amp;copy;.md>'),
        ('build%20draft.md', 'build%2520draft.md'),
    ):
        alias = elsewhere / alias
        alias.symlink_to(plan)
        summary.write_text(f'Build [this plan]({destination}).\n')
        approve_summary()
        alias.unlink()
    summary.unlink()
    elsewhere.rmdir()
    summary = adjacent
    approve_summary()
    assert state()['status'] == 'approved'
    # build#required-transition-files: consent requires a rendered link with a visible label.
    link = f'[this plan]({plan.name})'
    empty_link = f'[]({plan.name})'
    for false_link in (
        f'Build {empty_link}.\n',
        f'Build [   ]({plan.name}).\n',
        f'Build [  \n  ]({plan.name}).\n',
        f'Build [<!-- hidden -->]({plan.name}).\n',
        f'Build [**<!-- hidden -->**]({plan.name}).\n',
        f'Build [<em></em>]({plan.name}).\n',
        f'Build [` `]({plan.name}).\n',
        f'Build [&nbsp;&#9;&ZeroWidthSpace;]({plan.name}).\n',
        f'Build [&#xFE0F;]({plan.name}).\n',
        f'Build [\u034f]({plan.name}).\n',
        f'Build [&#12644;]({plan.name}).\n',
        f'Build [**\u180f&#xE0100;**]({plan.name}).\n',
        f'Build [`\ufe0f`]({plan.name}).\n',
        f'Build [\u3164][target].\n\n[target]: {plan.name}\n',
        f'The markup is `{link}`.\n',
        f'The markup is ``an example\nwith `backticks`: {link}``.\n',
        f'Intro.\n\n    {link}\n',
        f'Intro.\n\n\t{link}\n',
        f'---\n    {link}\n',
        f'> * * *\n>     {link}\n',
        f'Title\n===\n    {link}\n',
        f'- Title\n  ---\n      {link}\n',
        f'Example: \\{link}.\n',
        f'<!--\n{link}\n-->\n',
        f'<!-- A comment block. --> {link}\n',
        f'Build [this plan]({plan}).\n',
        f'~~~markdown\n{link}\n~~~\n',
        f'````markdown\n```\n{link}\n````\n',
        f'> ~~~markdown\n> {link}\n> ~~~\n',
        f'>     {link}\n',
        f'- ~~~markdown\n  {link}\n  ~~~\n',
        f'-     {link}\n',
        f'<pre><code>\n{link}\n</code></pre>\n',
        f'<code>\n{link}\n</code>\n',
        f'<div>\n{link}\n</div>\n',
        f'<div></div>\n{link}\n',
        f'- <div>\n  {link}\n  </div>\n',
        f'Intro.\n<search\trole="search">\n{link}\n',
        f'> <custom-widget>\n> {link}\n',
        f'<!DOCTYPE html> {link}\n',
        f'<![CDATA[\n>\n{link}\n]]>\n',
        f'<?example\n{link}\n?>\n',
        f'Intro <span title="{link}">example</span>.\n',
        f'!{link}\n',
        f'![Example {link}](image.png)\n',
    ):
        summary.write_text(false_link)
        for args in (
            ('summary', 'approve', plan, '--file', summary, '--by', 'user', '--words', 'yes'),
            ('build', 'start', plan, '--base', 'main'),
        ):
            before = facts()
            output = cli(*args, ok=False, code='bad-summary')
            assert str(summary) in output and 'fix:' in output, output
            assert before == facts(), output
    for real_link in (
        f'Intro with `<!--` and a visible {link}.\n',
        f'<!-- Example: {link} -->\nThen read {link}.\n',
        f'Open <!-- Inline comment. --> {link}.\n',
        f'> ~~~markdown\n> {link}\n\nRead {link}.\n',
        f'- ~~~markdown\n  {link}\n\nRead {link}.\n',
        f'<pre><code>\n{link}\n</code></pre>\n\nRead {link}.\n',
        f'<pre>\nExample\n</textarea>\nRead {link}.\n',
        f'<div>\nExample\n\nRead {link}.\n',
        f'> <div>\n> Example\nRead {link}.\n',
        f'Intro.\n<custom-widget>\nRead {link}.\n',
        f'Intro.\n\n    Ignore this code.\n\n   {link}\n',
        f'Intro.\n    {link}\n',
        f'Intro. \\\\{link}\n',
        f'> Read {link}.\n',
        f'- Open [`{plan.name}`](<{plan}>).\n',
        f'# Read {link}\n',
        f'Read {link}\n---\n',
        f'> 1. Intro.\n>\n>    {link}\n',
        f'- Intro.\n  - Nested.\n\n      {link}\n',
        f'- Intro.\n\n    {link}\n',
        f'Read [**the *plan***]({plan.name}).\n',
        f'Read [`&nbsp;`]({plan.name}).\n',
        f'Read [&nbsp]({plan.name}).\n',
        f'Read [\\*]({plan.name}).\n',
        f'Read [![](plan.png)]({plan.name}).\n',
        f'Ignore {empty_link} and [<!-- hidden -->]({plan.name}). Read {link}.\n',
        f'Открыть [**План**]({plan.name}).\n',
        f'Open [計画]({plan.name}).\n',
        f'Open [🟢]({plan.name}).\n',
        f'Open [🗂&#xFE0F;]({plan.name}).\n',
    ):
        summary.write_text(real_link)
        approve_summary()
    # A linked epic is required when compiling the plan.
    invalid_file(epic, 'approve', plan, malformed=b'# Epic\n\n## Plans\n\n| 1 |')
    # build#required-transition-files: build start checks inputs before creating its branch.
    for path, malformed in [(plan, b'# Only a title\n'), (compiled, b'{"status":"approved"}'),
                            (run, b'[unexpected]\nx = 1'), (summary, f'[Wrong](../missing/{plan.name})'.encode())]:
        invalid_file(path, 'build', 'start', plan, '--base', 'main', malformed=malformed)
    invalid_file(compiled, 'build', 'start', plan, '--base', 'main',
                 malformed=json.dumps({**state(), 'phases': [None]}).encode())
    invalid_file(compiled, 'build', 'start', plan, '--base', 'main',
                 malformed=json.dumps({**state(), 'approvals': {'run': []}}).encode())
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
    cli('accept', plan, '--by', 'user', '--words', 'yes, finish')
    assert state()['status'] == 'passed'
    # run#changes-through-approve, finish#merge-needs-land
    summary.write_text(summary.read_text() + 'Changed.\n')
    unchanged('finish', plan, code='summary-stale')
    approve_summary()
    unchanged('finish', plan, code='page-stale')
    cli('plan', 'status', plan, 'building')
    cli('page', plan, '--guide', 'Try the refreshed CLI.' + guide)
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
    cli('page', plan, '--guide', 'Review the delegated result.' + guide)
    unchanged('accept', plan, '--by', 'user', '--words', 'yes', code='unauthorized-acceptor')
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
