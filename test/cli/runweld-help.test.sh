#!/usr/bin/env bash
set -euo pipefail
unset CODEX_THREAD_ID CLAUDECODE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$repo_root" <<'PY'
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    outside = Path(tmp).resolve()
    prefix = outside / "install with spaces"
    cli = prefix / "bin/runweld"
    env = dict({k: v for k, v in os.environ.items() if not k.startswith("RUNWELD_")},
               GIT_AUTHOR_NAME="Tester", GIT_AUTHOR_EMAIL="test@example.org",
               GIT_COMMITTER_NAME="Tester", GIT_COMMITTER_EMAIL="test@example.org")
    subprocess.run([source / "scripts/install-runweld", "--prefix", prefix], cwd=outside, env=env, check=True)
    store = prefix / "lib/runweld"
    release = (store / "default").read_text().strip()

    def invoke(*args, cwd=outside):
        return subprocess.run([cli, *args], cwd=cwd, env=env, capture_output=True, text=True)

    def run(*args, cwd=outside):
        proc = invoke(*args, cwd=cwd)
        assert proc.returncode == 0 and not proc.stderr, (args, proc.stdout, proc.stderr)
        return proc.stdout

    # distribution#command-help: discover a task action without a Git checkout.
    root = run("--help")
    assert "\nStart here\n" in root and "\nProject and tasks\n" in root, "missing guided root help"
    assert root.startswith(f"Runweld {release.partition('@')[0]}\n")
    assert root == run("help") == run("-h") == run()
    assert "\n  task complete " in root and "\n  task cancel " in root
    task = run("help", "task")
    assert "complete" in task and "cancel" in task and "runweld help task" in task
    complete = run("help", "task", "complete")
    assert complete == run("task", "complete", "--help")
    for detail in ("owner", "--by", "--reason", "worktree", "artifacts", "runweld next", "Examples"):
        assert detail in complete, (detail, complete)
    for path, hint in ((("typo",), "runweld help"), (("task", "typo"), "runweld help task"),
                       (("task", "complete", "extra"), "runweld help task complete")):
        bad = invoke("help", *path)
        assert bad.returncode == 2 and not bad.stdout
        assert path[-1] in bad.stderr and hint in bad.stderr, bad.stderr

    # distribution#command-help: every shipped group, nested action and guide uses the same entry points.
    commands = """
        help reference handoff next init update path task spec approve status workflow plan build
        phase owner grant decision brief gate finding review result fix verdict land page accept
        note round finish run executor writing-guides grill prototype run-file verify bug epic retro
        domain-modeling tdd browser-test commit-work implementer reviewer judge build-verification human-review
    """.split()
    nested = {
        "handoff": "herdr",
        "task": "start resume path setup stage complete cancel",
        "spec": "check write list show",
        "plan": "review approve status base",
        "build": "start",
        "phase": "start report done",
        "brief": "implementer judge round reviewer verify fix",
        "gate": "start",
        "review": "complete",
        "fix": "start report done",
        "land": "draft accept revert now",
        "note": "add edit drop",
        "round": "start report done",
        "run": "new check show",
        "executor": "show",
        **dict.fromkeys(("grill", "prototype", "bug"), "start save done skip"),
    }

    def examples(help_text):
        section = help_text.partition("\nExamples\n")[2].split("\n\n", 1)[0]
        for line in section.splitlines():
            if line.strip().startswith("runweld "):
                yield shlex.split(line.strip())[1:]

    sys.dont_write_bytecode = True
    sys.path.insert(0, str(store / "releases" / release / "workflow/build"))
    from pipeline import parse_cli

    parser, _ = parse_cli(["help"], standalone=True, version=release)
    assert set(commands) == parser.commands.keys()
    all_examples = list(examples(root))
    for command in commands:
        assert command in root, command
        assert set(nested.get(command, "").split()) == getattr(parser.commands[command], "commands", {}).keys()
        for path in [(command,), *((command, action) for action in nested.get(command, "").split())]:
            card = run("help", *path)
            assert card == run(*path, "--help"), path
            assert "\nExamples\n" in card, path
            examples_in_card = list(examples(card))
            assert examples_in_card, path
            all_examples.extend(examples_in_card)

    # Parse authored examples using the installed engine's own command grammar, without making writes.
    for args in all_examples:
        parse_cli(args, standalone=True, version=release)

    project = outside / "project"
    project.mkdir()
    subprocess.run(["git", "init", "-qb", "main"], cwd=project, env=env, check=True)
    subprocess.run(["git", "commit", "--allow-empty", "-qm", "base"], cwd=project, env=env, check=True)
    assert "runweld init" in run("next", cwd=project)
    run("init", "--non-interactive", "--provider", "GPT", "--primary-model", "primary",
        "--secondary-model", "secondary", cwd=project)
    for args in examples(root):
        run(*args, cwd=project)
    task_state = json.loads(run("next", "report-search", "--json", cwd=project))
    plan = Path(task_state["task"]["path"])
    guide = run("plan", "--plan", plan)
    assert guide.startswith("runweld plan\n") and guide != run("plan", "--help")
    assert guide == run("plan", cwd=task_state["task"]["tree"])
    assert release in run("help", "agents", "--plan", plan) and "Workflow:" in run("help", "agents", "--plan", plan)
    assert "one persistent tab" in run("browser-test", "help")
    assert "[workflow]" in run("run", "show", plan, cwd=project)
    route = " ".join(run("help", "run").split())
    for term in ('[route]', '"ask"', '"take"', '"skip"', 'runweld next ID'):
        assert term in route, term
    with plan.with_suffix(".run.toml").open("a") as draft:
        draft.write('\n[route]\ngrill = "skip"\nprototype = "take"\n')
    assert json.loads(run("next", "report-search", "--json", cwd=project))["stage"] == "prototype"
    artifact = Path(task_state["task"]["artifacts"]) / "prototype.txt"
    artifact.write_text("Approved prototype\n")
    values = {"PLAN": plan, "ARTIFACT": artifact}
    for args in examples(run("help", "prototype")):
        run(*(values.get(arg, arg) for arg in args), cwd=project)
    # The closure example works as written in the disposable project.
    close = next(args for args in examples(complete) if args[:2] == ["task", "complete"])
    assert complete == run(*close, "--help", cwd=project)
    assert json.loads(run("next", "report-search", "--json", cwd=project))["stage"] == "plan"
    run(*close, cwd=project)
    closed = json.loads(run("next", "report-search", "--json", cwd=project))
    assert closed["task"]["outcome"]["outcome"] == "completed" and not closed["actions"]
    assert closed["stage"] == "plan" and closed["task"]["discovery"]["prototype"]["artifact"] == str(artifact)
PY
