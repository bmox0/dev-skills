#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-runweld"
python3 -B <<'PY'
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib


def check_designated_workflows(root):
    project = root / "project"
    project.mkdir()
    prefix = root / "prefix"
    env = dict(os.environ, HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "config"),
               GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.org",
               GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.org")

    def run(*args, code=0):
        result = subprocess.run(args, cwd=project, env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, stdin=subprocess.DEVNULL, timeout=30)
        assert result.returncode == code, f"{args} exited {result.returncode}: {result.stdout}{result.stderr}"
        return result.stdout + result.stderr

    def cli(*args, **kwargs):
        return run(prefix / "bin/runweld", *args, **kwargs)

    run(os.environ["INSTALLER"], "--prefix", prefix)
    run("git", "init", "-qb", "main")
    (project / "AGENTS.md").write_text("""## Environment

**CI workflow.** `.github/workflows/a.yml`, `.github/workflows/b.yml`
**Worktree setup.** none
""")
    workflows = project / ".github/workflows"
    workflows.mkdir(parents=True)
    steps = "jobs:\n  tests:\n    steps:\n"
    (workflows / "a.yml").write_text(steps + "      - run: exit 19\n")
    (workflows / "b.yml").write_text(steps + "      - run: true\n        working-directory: api\n")
    (project / "api").mkdir()
    (project / "api/.keep").touch()

    partial = json.loads(cli("onboard", "--apply", "--json",
                             "--primary-provider", "GPT", "--primary-model", "primary",
                             "--secondary-provider", "GPT", "--secondary-model", "secondary"))
    assert partial["sources"]["required checks"][".github/workflows/a.yml"] == ["exit 19"]
    assert set(partial["sources"]["CI unresolved"]) == {".github/workflows/b.yml"}
    assert set(partial["pending"]) == {"required_checks"}
    run("git", "add", ".")
    run("git", "commit", "-qm", "designate two CI workflows")

    config = project / ".runweld/config.toml"
    before = config.read_bytes()
    equivalent = "cd api && true"
    required = ["exit 19", equivalent]
    for flags in (("--required-check", equivalent), ("--no-required-checks",)):
        refusal = cli("onboard", "--apply", *flags, code=1)
        assert "project-required-checks" in refusal and "exit 19" in refusal, refusal
        assert config.read_bytes() == before
        print(refusal.strip())

    confirmation = ("--required-check", required[0], "--required-check", required[1])
    completed = json.loads(cli("onboard", "--apply", "--json", *confirmation))
    assert completed["complete"] and completed["settings"]["checks"]["required"] == required

    # The saved requirements and the chat answer omit the same known command.
    config.write_text(config.read_text().replace(json.dumps(required), json.dumps([equivalent])))
    saved = tomllib.loads(config.read_text())
    assert saved["checks"]["required"] == [equivalent]
    assert saved["onboarding"]["sources"]["confirmed required checks"]["chat"] == [equivalent]
    assert "required_checks" in json.loads(cli("onboard", "--json"))["pending"]
    refused_task = cli("task", "start", "unsafe", code=1)
    assert "required_checks" in refused_task, refused_task
    assert run("git", "branch", "--list", "runweld/unsafe") == ""
    print(refused_task.strip())

    cli("onboard", "--apply", *confirmation)
    task = json.loads(cli("task", "start", "bound", "--json"))
    binding = tomllib.loads(Path(task["plan"]).with_suffix(".run.toml").read_text())
    assert binding["checks"]["required"] == required
    print(f"Task bound both required commands: {binding['checks']['required']}")


with tempfile.TemporaryDirectory() as directory:
    # run#mandatory-checks: answering one designated workflow cannot erase another.
    check_designated_workflows(Path(directory).resolve())
PY
