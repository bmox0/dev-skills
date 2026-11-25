#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-ds"
python3 -B <<'PY'
import json
import os
from pathlib import Path
import pty
import subprocess
import tempfile
import tomllib

with tempfile.TemporaryDirectory() as folder:
    home = Path(folder).resolve()
    project = home / 'project with spaces'
    project.mkdir()
    prefix = home / 'local'
    env = dict(os.environ, GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.org',
               GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.org')
    for name in ('CLAUDECODE', 'CODEX_THREAD_ID'):
        env.pop(name, None)

    def command(*args, cwd=project, ok=True, with_env=None, **kwargs):
        result = subprocess.run(args, cwd=cwd, env=with_env or env, text=True, capture_output=True, **kwargs)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        return (result.stdout + result.stderr).strip()

    def git(*args, **kwargs):
        return command('git', *args, **kwargs)

    def ds(*args, **kwargs):
        return command(prefix / 'bin/ds', *args, **kwargs)

    def terminal(input_, ok=True):
        master, slave = pty.openpty()
        try:
            os.write(master, input_)
            return ds('init', stdin=slave, ok=ok, timeout=10)
        finally:
            os.close(master)
            os.close(slave)

    def read(file):
        return tomllib.loads(file.read_text())

    command(os.environ['INSTALLER'], '--prefix', prefix, cwd=home)
    release = ds('--version', cwd=home)
    git('init', '-q', '-b', 'main')
    agents = project / 'AGENTS.md'
    instructions = ('# Local rules\n\nKeep this text.\n\n## Environment\n\n'
                    '**Lint.** `scripts/lint`\n**Tests.** `scripts/test old`\n'
                    '**Worktree setup.** `touch must-not-run-at-init`')
    agents.write_text(instructions)
    ignore = project / '.gitignore'
    ignore.write_text('private-notes\n')
    git('add', '.')
    git('commit', '-qm', 'base')
    config = project / '.ds/config.toml'
    lock = project / '.ds/ds.lock'

    # distribution#system-cli, run#executor-presets, run#contract-checked: a terminal collects one pair and project defaults.
    assert 'init' in ds('--help'), 'distribution#system-cli: the installed CLI must advertise initialization'
    stopped = terminal(b'\x04', ok=False)
    assert 'cancelled' in stopped and not config.exists() and not lock.exists()
    assert agents.read_text() == instructions and ignore.read_text() == 'private-notes\n'
    output = terminal(b'GPT\ncodex-main\nhigh\ncodex-helper\n' + b'\n' * 11)
    assert 'Provider' in output and 'scripts/test old' in output and 'touch must-not-run-at-init' in output
    assert not (project / 'must-not-run-at-init').exists()
    profiles = {'GPT': {'primary': {'model': 'codex-main', 'effort': 'high'}, 'secondary': {'model': 'codex-helper'}}}
    assert read(config)['executors'] == profiles
    assert read(config)['checks'] == {'phase': ['scripts/lint'], 'full': ['scripts/lint', 'scripts/test old']}
    assert read(config)['isolation']['worktree'] is True
    assert read(config)['setup'] == {'command': 'touch must-not-run-at-init'}
    assert read(lock) == {'release': release}
    assert instructions in agents.read_text() and agents.read_text().count('ds help agents') == 1
    git('check-ignore', '.ds/workflow/plans/example.md')
    for file in ('.ds/config.toml', '.ds/ds.lock', 'docs/spec/example.md'):
        git('check-ignore', file, ok=False)
    managed = {file: file.read_bytes() for file in (config, lock, agents, ignore)}
    assert 'provider' in ds('init', '--non-interactive', ok=False).lower()
    ds('init', '--provider', 'GPT', '--non-interactive')
    assert all(file.read_bytes() == data for file, data in managed.items())
    assert 'executors."Other".primary.model' in ds('init', '--provider', 'Other', '--primary-model', ' ',
                                                   '--secondary-model', 'helper', '--non-interactive', ok=False)
    assert all(file.read_bytes() == data for file, data in managed.items())
    # A retry after all shared writes except the lock keeps their bytes.
    lock.unlink()
    ds('init', '--provider', 'GPT', '--non-interactive')
    assert all(file.read_bytes() == data for file, data in managed.items())

    # distribution#project-lock, distribution#local-workflow, run#executor-presets: the clone adds only its missing pair.
    with config.open('a') as f:
        f.write('\n# retain this comment\n')
    original = config.read_bytes()
    git('add', '.')
    git('commit', '-qm', 'shared workflow')
    plans = project / '.ds/workflow/plans'
    plans.mkdir(parents=True)
    first = plans / 'first.md'
    ds('task', 'start', 'first')
    first.write_text(f'''# Plan: First

Status: draft · branch `ds/first` · base `{git('rev-parse', 'HEAD')}`

## Result

One run.

## Approach

Check it.

## Out of scope

- Nothing.

## Phases

### 1. Example — `waiting`

Territory: `src/`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture

## Done

1. Run → record.

## Spec

none
''')
    first_values = first.with_suffix('.run.toml')
    with first_values.open('a') as f:
        f.write('credential = "keychain:example/private"\n')
    ds('approve', first)
    ds('run', 'approve', first, '--by', 'User', '--words', 'Approve first run')
    clone = home / 'Claude clone'
    git('clone', '-q', project, clone, cwd=home)
    assert not (clone / '.ds/workflow').exists()
    ds('init', '--primary-model', 'claude-main', '--secondary-model', 'claude-helper',
       '--non-interactive', cwd=clone, with_env={**env, 'CLAUDECODE': '1'})
    clone_config = clone / '.ds/config.toml'
    assert clone_config.read_bytes().startswith(original)
    assert read(clone_config)['checks'] == read(config)['checks']
    assert read(clone_config)['executors'] == {
        **profiles, 'Claude': {'primary': {'model': 'claude-main'}, 'secondary': {'model': 'claude-helper'}}}
    assert read(clone / '.ds/ds.lock') == read(lock)
    inline = home / 'inline config'
    git('clone', '-q', project, inline, cwd=home)
    inline_config = inline / '.ds/config.toml'
    inline_config.write_text(
        'executors = { GPT = { primary = { model = "codex-main", effort = "high" }, '
        'secondary = { model = "codex-helper" } } } # keep this annotation\n'
        + original.decode().split('[executors.', 1)[0])
    extra_pair = ('--provider', 'Claude', '--primary-model', 'claude-main',
                  '--secondary-model', 'claude-helper', '--non-interactive')
    ds('init', *extra_pair, cwd=inline)
    assert read(inline_config) == read(clone_config) and '# keep this annotation' in inline_config.read_text()
    ds('init', *extra_pair, cwd=inline)

    # run#starts-from-last, run#changes-through-approve: current defaults are not taken from old local runs.
    config.write_text(config.read_text().replace('scripts/test old', 'scripts/test new'))
    second = plans / 'second.md'
    ds('task', 'start', 'second')
    snapshot = read(second.with_suffix('.run.toml'))
    assert snapshot['checks']['full'] == ['scripts/lint', 'scripts/test new']
    assert snapshot['executors'] == profiles and snapshot['setup'] == read(config)['setup']
    assert snapshot['workflow'] == {'release': release} and snapshot['run'] == {}
    shown = json.loads(ds('run', 'show', first, '--json'))
    assert shown['approved'] and shown['run']['workflow'] == {'release': release}
    assert shown['run']['checks']['full'] == ['scripts/lint', 'scripts/test old']
    assert shown['run']['run'] == {'credential': 'keychain:example/private'}
    assert json.loads(ds('executor', 'show', '--provider', 'Claude', '--json', cwd=clone))['source'] == str(clone_config)

    # run#contract-checked: shared configuration cannot supply graph rules or task values.
    for forbidden in ('graph', 'run', 'workflow'):
        before = config.read_text()
        config.write_text(before + f'\n[{forbidden}]\nvalue = "must not be consumed"\n')
        bad = plans / f'{forbidden}.md'
        problem = ds('task', 'start', forbidden, ok=False)
        assert f'[{forbidden}]' in problem and str(config) in problem
        assert not bad.with_suffix('.run.toml').exists()
        config.write_text(before)

    # run#worktree-setup: a clean project can opt in explicitly or leave setup absent.
    explicit = home / 'explicit'
    explicit.mkdir()
    git('init', '-q', '-b', 'trunk', cwd=explicit)
    (explicit / '.gitignore').write_text('/.ds/\n')
    ds('init', '--provider', 'Other provider', '--primary-model', 'opaque model', '--secondary-model', 'other model',
       '--phase-check', 'lint -- arg', '--full-check', 'test one', '--full-check', 'test two',
       '--finish-how', 'no-ff', '--finish-target', 'stable', '--no-delete-backups',
       '--port', '--data-dir', '--dev', 'serve {port} {data_dir}', '--url', 'http://localhost:{port}',
       '--non-interactive', cwd=explicit)
    direct = read(explicit / '.ds/config.toml')
    assert direct['checks'] == {'phase': ['lint -- arg'], 'full': ['test one', 'test two'],
                                'dev': 'serve {port} {data_dir}', 'url': 'http://localhost:{port}'}
    assert direct['finish'] == {'how': 'no-ff', 'target': 'stable', 'delete_backups': False}
    assert direct['isolation'] == {'worktree': True, 'port': True, 'data_dir': True}
    assert 'setup' not in direct
    git('check-ignore', '.ds/config.toml', cwd=explicit, ok=False)
    git('check-ignore', '.ds/ds.lock', cwd=explicit, ok=False)
    git('check-ignore', '.ds/workflow/scratch', cwd=explicit)
    git('check-ignore', '.ds/other-private', cwd=explicit)
PY
