#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"
tmp=$(mktemp_dir)
# distribution#shared-resources: relocated code uses its resources and the target's profiles.
python3 -B - "$repo_root" "$tmp" <<'PYRELOCATED'
import hashlib, json, os, pathlib, shutil, subprocess, sys
source, tmp = (pathlib.Path(p).resolve() for p in sys.argv[1:])
package = tmp / 'relocated package $'
subprocess.run([source / 'scripts/install-runweld', '--prefix', tmp / 'install'], check=True)
store = tmp / 'install/lib/runweld'
shutil.copytree(store / 'releases' / (store / 'default').read_text().strip(), package)
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
run = subprocess.run([sys.executable, '-B', str(package / 'workflow/build/pipeline.py'),
                      'executor', 'show', '--provider', 'Fixture'], cwd=project, capture_output=True, text=True)
assert run.returncode == 0 and 'project-primary' in run.stdout and str(project / 'AGENTS.md') in run.stdout, run
assert not (project / 'workflow').exists() and not (package / '.runweld/workflow').exists()
for folder in ('agents', 'references', 'workflow', 'scripts', 'adapters'):
    for original in (source / folder).rglob('*'):
        if original.is_file() and '__pycache__' not in original.parts:
            copied = package / original.relative_to(source)
            assert hashlib.sha256(original.read_bytes()).digest() == hashlib.sha256(copied.read_bytes()).digest(), copied
            assert original.stat().st_mode & 0o111 == copied.stat().st_mode & 0o111, copied
assert not list(package.rglob('__pycache__'))
PYRELOCATED

echo ok
