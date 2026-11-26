#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-runweld"
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

    def runweld(*args, **kwargs):
        return command(prefix / 'bin/runweld', *args, **kwargs)

    def terminal(input_, ok=True):
        master, slave = pty.openpty()
        try:
            os.write(master, input_)
            return runweld('init', stdin=slave, ok=ok, timeout=10)
        finally:
            os.close(master)
            os.close(slave)

    def read(file):
        return tomllib.loads(file.read_text())

    command(os.environ['INSTALLER'], '--prefix', prefix, cwd=home)
    release = (prefix / 'lib/runweld/default').read_text().strip()
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
    config = project / '.runweld/config.toml'
    lock = project / '.runweld/runweld.lock'

    # distribution#system-cli, run#executor-presets, run#contract-checked: a terminal collects one pair and project defaults.
    assert 'next' in runweld('help'), 'distribution#system-cli: terminal help advertises the first action'
    assert 'git init' in runweld('next', cwd=home), 'distribution#system-cli: explain the missing Git project'
    entry = json.loads(runweld('next', '--json'))
    assert entry['actions'][0]['argv'][-1] == 'init', 'distribution#system-cli: an uninitialized checkout offers init'
    assert entry['actions'][0]['cwd'] == str(project)
    assert 'runweld init' in runweld('next')
    assert not config.exists(), 'distribution#system-cli: checking what comes next does not initialize'
    stopped = terminal(b'\x04', ok=False)
    assert 'cancelled' in stopped and not config.exists() and not lock.exists()
    assert agents.read_text() == instructions and ignore.read_text() == 'private-notes\n'
    output = terminal(b'GPT\ncodex-main\nhigh\ncodex-helper\n' + b'\n' * 11)
    assert 'Provider' in output and 'scripts/test old' in output and 'touch must-not-run-at-init' in output
    assert not (project / 'must-not-run-at-init').exists()
    profiles = {'GPT': {'primary': {'model': 'codex-main', 'effort': 'high'}, 'secondary': {'model': 'codex-helper'}}}
    assert 'finish' not in read(config)
    assert read(config)['executors'] == profiles
    assert read(config)['checks'] == {'phase': ['scripts/lint'], 'full': ['scripts/lint', 'scripts/test old']}
    assert 'isolation' not in read(config)
    assert read(config)['setup'] == {'command': 'touch must-not-run-at-init'}
    pins = read(lock)
    assert pins['lock_version'] == 2 and pins['release'] == release
    assert set(pins['roles']) == {'implementer', 'reviewer', 'judge'}
    assert {'plan', 'build', 'review'} <= pins['guides'].keys()
    assert {'claude', 'codex', 'antigravity'} <= pins['adapters'].keys()
    assert pins['cli'].keys() == {'engine', 'launcher'}
    generated = lock.read_bytes()
    lock.write_bytes(generated.replace(pins['roles']['judge'].encode(), b'sha256:' + b'0' * 64))
    assert 'does not match the components' in runweld('task', 'start', 'altered', ok=False)
    runweld('update', '--project', release)
    assert lock.read_bytes() == generated
    block = ('<!-- runweld:begin -->\n\n'
             'Start or resume work with `runweld next`.\n\n'
             '<!-- runweld:end -->')
    assert agents.read_text() == f'{instructions}\n\n{block}\n'
    git('check-ignore', '.runweld/workflow/plans/example.md')
    for file in ('.runweld/config.toml', '.runweld/runweld.lock', 'docs/spec/example.md'):
        git('check-ignore', file, ok=False)
    managed = {file: file.read_bytes() for file in (config, lock, agents, ignore)}
    assert 'provider' in runweld('init', '--non-interactive', ok=False).lower()
    runweld('init', '--provider', 'GPT', '--non-interactive')
    assert all(file.read_bytes() == data for file, data in managed.items())
    assert 'runweld task start' in runweld('next'), 'distribution#system-cli: initialized projects offer task entry'
    assert 'executors."Other".primary.model' in runweld('init', '--provider', 'Other', '--primary-model', ' ',
                                                   '--secondary-model', 'helper', '--non-interactive', ok=False)
    assert all(file.read_bytes() == data for file, data in managed.items())
    # A retry after all shared writes except the lock keeps their bytes.
    lock.unlink()
    assert 'runweld init' in runweld('next'), 'distribution#system-cli: next recovers interrupted initialization'
    runweld('init', '--provider', 'GPT', '--non-interactive')
    assert all(file.read_bytes() == data for file, data in managed.items())

    # distribution#local-workflow: refresh the managed block without changing neighboring text.
    before = b'# Local rules\r\n\r\n'
    after = b'\r\n\r\nKeep this text without a trailing newline.'
    begin, end = b'<!-- runweld:begin -->', b'<!-- runweld:end -->'
    agents.write_bytes(before + b'\r\n'.join((begin, b'Old instructions', end)) + after)
    expected = before + block.replace('\n', '\r\n').encode() + after
    for _ in range(2):
        runweld('init', '--provider', 'GPT', '--non-interactive')
        assert agents.read_bytes() == expected
    for markers in ((begin,), (end,), (end, begin), (begin, end, begin, end)):
        broken = before + b'\r\n'.join(markers) + after
        agents.write_bytes(broken)
        problem = runweld('init', '--provider', 'GPT', '--non-interactive', ok=False)
        assert 'project-agents-block' in problem
        assert agents.read_bytes() == broken
        assert all(file.read_bytes() == managed[file] for file in (config, lock, ignore))
    agents.write_bytes(managed[agents])

    # distribution#project-lock, distribution#local-workflow, run#executor-presets: the clone adds only its missing pair.
    with config.open('a') as f:
        f.write('\n# retain this comment\n')
    original = config.read_bytes()
    git('add', '.')
    git('commit', '-qm', 'shared workflow')
    plans = project / '.runweld/workflow/plans'
    plans.mkdir(parents=True)
    first = Path(json.loads(runweld('task', 'start', 'first', '--finish-how', 'ff-only', '--finish-target', 'main', '--json'))['plan'])
    first.write_text(f'''# Plan: First

Status: draft · branch `runweld/first` · base `{git('rev-parse', 'HEAD')}`

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
    agreed = first_values.read_bytes()
    first_values.write_bytes(agreed.replace(b'how = "ff-only"\n', b''))
    assert '[finish] how is missing' in runweld('approve', first, ok=False)
    first_values.write_bytes(agreed)
    runweld('approve', first)
    review = json.loads(runweld('plan', 'review', first, '--json'))
    runweld('plan', 'approve', first, '--revision', review['revision'], '--by', 'Mina', '--words', 'Approve first plan and run')
    clone = home / 'Claude clone'
    git('clone', '-q', project, clone, cwd=home)
    assert not (clone / '.runweld/workflow').exists()
    runweld('init', '--primary-model', 'claude-main', '--secondary-model', 'claude-helper',
       '--non-interactive', cwd=clone, with_env={**env, 'CLAUDECODE': '1'})
    clone_config = clone / '.runweld/config.toml'
    assert clone_config.read_bytes().startswith(original)
    assert read(clone_config)['checks'] == read(config)['checks']
    assert read(clone_config)['executors'] == {
        **profiles, 'Claude': {'primary': {'model': 'claude-main'}, 'secondary': {'model': 'claude-helper'}}}
    assert read(clone / '.runweld/runweld.lock') == read(lock)
    inline = home / 'inline config'
    git('clone', '-q', project, inline, cwd=home)
    inline_config = inline / '.runweld/config.toml'
    inline_config.write_text(
        'executors = { GPT = { primary = { model = "codex-main", effort = "high" }, '
        'secondary = { model = "codex-helper" } } } # keep this annotation\n'
        + original.decode().split('[executors.', 1)[0])
    extra_pair = ('--provider', 'Claude', '--primary-model', 'claude-main',
                  '--secondary-model', 'claude-helper', '--non-interactive')
    runweld('init', *extra_pair, cwd=inline)
    assert read(inline_config) == read(clone_config) and '# keep this annotation' in inline_config.read_text()
    runweld('init', *extra_pair, cwd=inline)

    # run#starts-from-last, run#changes-through-approve: current defaults are not taken from old local runs.
    config.write_text(config.read_text().replace('scripts/test old', 'scripts/test new'))
    second = Path(json.loads(runweld('task', 'start', 'second', '--json'))['plan'])
    snapshot = read(second.with_suffix('.run.toml'))
    assert snapshot['finish'] == {'delete_backups': True}
    assert json.loads(runweld('run', 'show', second, '--json'))['run']['finish'] == snapshot['finish']
    assert '[finish] how is missing' in runweld('run', 'check', second, ok=False)
    assert snapshot['checks']['full'] == ['scripts/lint', 'scripts/test new']
    assert snapshot['executors'] == profiles and snapshot['setup'] == read(config)['setup']
    version, digest = release.split('@')
    assert list(snapshot) == ['workflow', 'finish', 'checks', 'setup', 'executors', 'run']
    assert snapshot['workflow'] == {'version': version, 'digest': digest} and snapshot['run'] == {}
    shown = json.loads(runweld('run', 'show', first, '--json'))
    assert shown['approved'] and shown['run']['workflow'] == snapshot['workflow']
    assert shown['run']['checks']['full'] == ['scripts/lint', 'scripts/test old']
    assert shown['run']['run'] == {'credential': 'keychain:example/private'}
    assert json.loads(runweld('executor', 'show', '--provider', 'Claude', '--json', cwd=clone))['source'] == str(clone_config)

    # run#contract-checked: shared configuration cannot supply graph rules or task values.
    for forbidden in ('graph', 'run', 'workflow'):
        before = config.read_text()
        config.write_text(before + f'\n[{forbidden}]\nvalue = "must not be consumed"\n')
        bad = plans / f'{forbidden}.md'
        problem = runweld('task', 'start', forbidden, ok=False)
        assert f'[{forbidden}]' in problem and str(config) in problem
        assert not bad.with_suffix('.run.toml').exists()
        config.write_text(before)

    # distribution#system-cli: preserve explicit Environment commands rather than inferring different checks.
    detected = home / 'documented'
    detected.mkdir()
    git('init', '-qb', 'main', cwd=detected)
    (detected / 'AGENTS.md').write_text(
        '# Project\n\n## Environment\n\n'
        '**Build.** `make compile`\n\n'
        '**Phase checks.** `make lint`, `make types`\n\n'
        '**Full checks.** `make suite`\n\n'
        '**Bootstrap.** `touch must-not-bootstrap-during-init`\n\n'
        '**Dev server.** `make serve`, serves on `http://localhost:9000`\n\n'
        '**Dev URL.** `http://localhost:9100`\n'
    )
    output = runweld('init', '--provider', 'Test', '--primary-model', 'main',
                     '--secondary-model', 'helper', '--non-interactive', cwd=detected)
    assert 'Detected' in output and 'make types' in output and 'http://localhost:9100' in output, output
    found = read(detected / '.runweld/config.toml')
    assert found['checks'] == {'phase': ['make lint', 'make types'], 'full': ['make suite'],
                               'build': 'make compile', 'dev': 'make serve', 'url': 'http://localhost:9100'}, found
    assert found['setup'] == {'command': 'touch must-not-bootstrap-during-init'}
    assert not (detected / 'must-not-bootstrap-during-init').exists()
    assert 'commit' in runweld('next', cwd=detected), 'distribution#system-cli: task entry needs an initial commit'

    # run#worktree-setup: a clean project can opt in explicitly or leave setup absent.
    explicit = home / 'explicit'
    explicit.mkdir()
    git('init', '-q', '-b', 'trunk', cwd=explicit)
    (explicit / '.gitignore').write_text('/.runweld/\n')
    runweld('init', '--provider', 'Other provider', '--primary-model', 'opaque model', '--secondary-model', 'other model',
       '--phase-check', 'lint -- arg', '--full-check', 'test one', '--full-check', 'test two',
       '--port', '--data-dir', '--build', 'make all', '--dev', 'serve {port} {data_dir}', '--dev-url', 'http://localhost:{port}',
       '--non-interactive', cwd=explicit)
    direct = read(explicit / '.runweld/config.toml')
    assert direct['checks'] == {'phase': ['lint -- arg'], 'full': ['test one', 'test two'],
                                'build': 'make all', 'dev': 'serve {port} {data_dir}', 'url': 'http://localhost:{port}'}
    assert 'finish' not in direct
    git('commit', '--allow-empty', '-qm', 'base', cwd=explicit)
    def explicit_run(*args):
        entry = json.loads(runweld('task', 'start', *args, '--json', cwd=explicit))
        return read(Path(entry['plan']).with_suffix('.run.toml'))
    assert explicit_run('local', '--finish-how', 'no-ff', '--finish-target', 'trunk', '--no-delete-backups')['finish'] == {
        'how': 'no-ff', 'target': 'trunk', 'delete_backups': False}
    assert explicit_run('request', '--finish-how', 'merge-request', '--finish-target', 'trunk')['finish']['how'] == 'merge-request'
    assert 'already has a run file' in runweld('task', 'start', 'local', '--finish-how', 'merge-request', cwd=explicit, ok=False)
    assert 'finish' not in read(explicit / '.runweld/config.toml')
    assert direct['isolation'] == {'port': True, 'data_dir': True}
    assert 'setup' not in direct
    git('check-ignore', '.runweld/config.toml', cwd=explicit, ok=False)
    git('check-ignore', '.runweld/runweld.lock', cwd=explicit, ok=False)
    git('check-ignore', '.runweld/workflow/scratch', cwd=explicit)
    git('check-ignore', '.runweld/other-private', cwd=explicit)
PY
