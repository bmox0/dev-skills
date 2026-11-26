#!/usr/bin/env bash
# Instruction-contract checks; these do not certify a live host or role execution.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -B - "$here/../.." <<'PY'
import pathlib, sys

root = pathlib.Path(sys.argv[1]).resolve()
protocol = (root / 'references/SESSIONS.md').read_text()

def requires(text, terms, rule):
    for term in terms:
        assert term in text, f'{rule}: missing {term!r}'

# build#worker-role-bound: source identity and native priority survive dispatch and recovery.
requires(protocol, ('runweld reviewer --plan PLAN', 'higher-priority', 'Initialization evidence',
                    'loaded', 'role', 'brief', 'executor', 'report', 'implementer', 'reviewer', 'judge'),
         'build#worker-role-bound')
assert 'adapters/<host>/workers.md' in protocol
binding = (root / 'adapters/antigravity/workers.md').read_text()
requires(binding, ('define_subagent', 'EnableWriteTools: true', 'SystemPrompt',
                   'EnableSubagentTools: false', 'TypeName', 'approved executor'), 'build#worker-role-bound')
for role in ('implementer', 'reviewer', 'judge'):
    source = (root / f'agents/{role}.md').read_text()
    requires(source, ('SESSIONS.md', 'AGENTS.md', 'brief'), 'build#worker-role-bound')
# build#acceptance-contact: unsupported native messaging has an actionable return channel.
requires(protocol, ('native messages', 'result channel', 'report artifact', 'collect',
                    'question', 'permission', 'approval', 'unchanged', 'duplicate reports'),
         'build#acceptance-contact')
# build#replacement-preserves-progress: old writers stop before same-role recovery from facts.
requires(protocol, ('confirmed stopped', 'write-capable jobs', 'unknown', 'same role',
                    'CLI', 'Git', 'phase start', 'completed', 'continuation'),
         'build#replacement-preserves-progress')
assert 'through native messages' not in (root / 'agents/implementer.md').read_text()
build = (root / 'workflow/build/GUIDE.md').read_text()
assert 'Answer through the host’s message tool' not in build
assert 'Workers use secondary.' not in build, 'build#worker-role-bound: first review and judge use primary'
verify = (root / 'workflow/verify/GUIDE.md').read_text()
assert 'Dispatch a fresh secondary worker' not in verify, 'build#worker-role-bound: the assigned Verify worker drives cases without dispatching'
# run#executor-presets: discovery comes from supplied catalogues; profiles stay literal and local.
plan = (root / 'workflow/plan/GUIDE.md').read_text()
assert '.claude/skills/' not in plan and '.agents/skills/' not in plan
requires(protocol, ('literal', '.runweld/config.toml', 'AGENTS.md', 'frozen', 'unsupported'), 'run#executor-presets')
PY
echo ok
