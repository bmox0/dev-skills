#!/usr/bin/env bash
set -euo pipefail
unset CODEX_THREAD_ID CLAUDECODE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SUMMARY_FIXTURE="$repo_root/test/lib/summary.md"
REPO_ROOT="$repo_root" python3 - <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

# distribution#task-outcome: close at the actual stage without changing pinned work or evidence.
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp).resolve()
    project = root / "project with spaces"
    project.mkdir()
    prefix = root / "install"
    cli = prefix / "bin/runweld"
    store = prefix / "lib/runweld"
    source = Path(os.environ["REPO_ROOT"])
    env = dict({k: v for k, v in os.environ.items() if not k.startswith("RUNWELD_")},
               GIT_AUTHOR_NAME="Tester", GIT_AUTHOR_EMAIL="test@example.org",
               GIT_COMMITTER_NAME="Tester", GIT_COMMITTER_EMAIL="test@example.org")

    def run(*args, cwd=project, ok=True):
        process = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
        assert (process.returncode == 0) == ok, process.stdout + process.stderr
        return process.stdout.strip() if ok else process.stdout + process.stderr

    def view(*args, cwd=project):
        return json.loads(run(cli, *args, "--json", cwd=cwd))

    def launch(*args):
        return subprocess.Popen(args, cwd=project, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    legacy = os.environ.get("RUNWELD_TEST_LEGACY_BUNDLE")
    earlier = Path(legacy) if legacy else source
    run(earlier / "scripts/install-runweld", "--prefix", prefix)
    pin = (store / "default").read_text().strip()
    if legacy:
        assert pin == earlier.name
    run("git", "init", "-qb", "main")
    run("git", "commit", "--allow-empty", "-qm", "base")
    base = run("git", "rev-parse", "HEAD")
    signal, resume = root / "setup-started", root / "setup-resume"
    setup = f"touch '{signal}'; while [ ! -e '{resume}' ]; do sleep .05; done"
    run(cli, "init", "--non-interactive", "--provider", "Test",
        "--primary-model", "main", "--secondary-model", "helper", "--setup", setup)

    def start(name):
        return view("task", "start", name, "--goal", "Preserve the evidence",
                    "--finish-how", "ff-only", "--finish-target", "main")

    def snapshot(plan):
        return {path: path.read_bytes() for path in plan.parent.iterdir()
                if path.is_file() and not path.name.endswith((".outcome.json", ".lock"))}

    prototype = start("prototype-only")
    preplan = Path(prototype["plan"])
    run(cli, "grill", "skip", preplan, "--reason", "The questions are settled")
    run(cli, "prototype", "start", preplan)
    artifact = Path(prototype["artifacts"]) / "approved.txt"
    artifact.write_text("Approved prototype\n")
    run(cli, "prototype", "done", preplan, "--result", "Approved by the owner", "--artifact", artifact)
    assert view("next", "prototype-only")["stage"] == "plan"
    assert not preplan.exists()

    compiled = start("compiled")
    plan = Path(compiled["plan"])
    for stage in ("grill", "prototype"):
        run(cli, stage, "skip", plan, "--reason", "Not needed")
    draft_text = f"""# Plan: Compiled cancellation

Status: draft · branch `runweld/compiled` · base `{base}`

## Result

A compiled plan.

## Approach

Implement a change.

## Out of scope

- Other changes.

## Phases

### 1. Change — `waiting`
Territory: `fixture.txt`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture

## Done

1. Write fixture.txt → the result exists.

## Spec

none
"""
    plan.write_text(draft_text)
    draft = view("next", "compiled")
    assert draft["stage"] == "plan" and not draft["task"].get("reason"), draft
    run(cli, "approve", plan)
    plan.with_suffix(".summary.md").write_bytes(Path(os.environ["SUMMARY_FIXTURE"]).read_bytes())
    rev = view("plan", "review", plan)["revision"]
    run(cli, "plan", "approve", plan, "--revision", rev, "--by", "Owner", "--words", "Approve this plan")
    run(cli, "build", "start", plan)
    status = view("next", "compiled", "--provider", "Test")
    stale = next(step for step in status["actions"] if step.get("argv", [])[-4:] == ["phase", "start", str(plan), "1"])
    assert pin in stale["argv"] and status["stage"] == "build"
    evidence = Path(compiled["artifacts"]) / "evidence.txt"
    evidence.write_text("Keep this file\n")
    before = snapshot(preplan)
    lock = (project / ".runweld/runweld.lock").read_bytes()
    candidate = root / "candidate"
    candidate.mkdir()
    for name in ("workflow", "agents", "references", "adapters", "scripts", "docs", "bin"):
        shutil.copytree(source / name, candidate / name)
    for name in ("README.md", "LICENSE", "install.sh", "VERSION"):
        shutil.copy2(source / name, candidate / name)
    catalog = candidate / "references/workflow.toml"
    catalog.write_text(catalog.read_text().replace('grill = "ask"', 'grill = "skip"'))
    run(candidate / "scripts/install-runweld", "--prefix", prefix)
    assert pin != (store / "default").read_text().strip()

    owner = ("--by", "Owner", "--reason", "The goal was reached")

    # build#required-transition-files distribution#task-outcome: a missing compiled state stops the run.
    state_path = plan.with_suffix(".json")
    state = state_path.read_bytes()
    state_path.unlink()
    blocked_snapshot = snapshot(plan)
    state_reason = {"code": "not-compiled", "path": str(state_path)}
    for args, cwd in ((("next", "compiled"), project), (("next", "--plan", plan), root),
                      (("next",), compiled["tree"]), (("status", plan), root),
                      (("status", "--current"), compiled["tree"])):
        data = view(*args, cwd=cwd)
        if isinstance(data, list):
            data, = data
        row = data.get("task", data)
        workflow = data if "task" in data else row["workflow"]
        assert row["status"] == "stopped" and row["reason"] == state_reason, data
        assert workflow["stage"] is None and all(step["kind"] == "work" and "argv" not in step
                                                  for step in workflow["actions"]), workflow
        assert row["release"] == pin and not row.get("outcome"), row
        description = run(cli, *args, cwd=cwd)
        assert all(term in description for term in ("stopped", "not-compiled", str(state_path))), description
    inventory = next(row for row in view("status") if row["plan"] == "compiled")
    assert inventory["status"] == "stopped" and inventory["reason"] == state_reason, inventory
    listed = next(row for row in view("next")["tasks"] if row["id"] == "compiled")
    assert listed["status"] == "stopped" and listed["reason"] == state_reason, listed
    assert str(state_path) in run(cli, "next") and str(state_path) in run(cli, "status")
    assert str(state_path) in run(cli, "--release", pin, "next", "compiled")
    for args in (stale["argv"], (cli, "--release", pin, "approve", plan),
                 (cli, "--release", pin, "grill", "skip", plan, "--reason", "Stale discovery"),
                 (cli, "task", "complete", "compiled", *owner, "--json"),
                 (cli, "task", "cancel", "compiled", *owner, "--json")):
        refusal = run(*args, ok=False)
        assert "not-compiled" in refusal and str(state_path) in refusal, refusal
    assert snapshot(plan) == blocked_snapshot and not plan.with_suffix(".outcome.json").exists()
    assert evidence.read_text() == "Keep this file\n"
    state_path.write_bytes(state)
    resumed = view("next", "compiled", "--provider", "Test")
    assert resumed["stage"] == "build" and resumed["task"]["status"] == "building", resumed
    assert stale in resumed["actions"] and not resumed["task"].get("outcome"), resumed

    assert "--reason" in run(cli, "task", "complete", "--help")
    assert "nonblank reason" in run(cli, "task", "complete", "prototype-only",
                                     "--by", "Owner", "--reason", " ", ok=False)
    assert view("next", "prototype-only")["actions"]
    result = view("task", "complete", "prototype-only", *owner)
    decision = result["outcome"]
    assert decision["outcome"] == "completed" and decision["stage"] == "plan"
    assert decision["by"] == "Owner" and decision["reason"] == "The goal was reached" and decision["at"]
    assert result["release"] == pin and result["discovery"]["prototype"]["artifact"] == str(artifact)
    assert view("task", "complete", "prototype-only", "--by", "Other", "--reason", "Retry")["outcome"] == decision
    assert "completed" in run(cli, "task", "cancel", "prototype-only", *owner, ok=False)
    assert view("status", preplan)["outcome"] == decision
    assert view("status", preplan, cwd=root)["outcome"] == decision
    assert view("task", "resume", "prototype-only")["workflow"]["actions"] == []
    assert view("status", "--current", cwd=prototype["tree"])[0]["outcome"] == decision
    terminal = view("next", cwd=prototype["tree"])
    assert terminal["stage"] == "plan" and terminal["actions"] == [] and terminal["task"]["outcome"] == decision
    description = run(cli, "next", "prototype-only")
    assert "completed" in description and "plan" in description and str(artifact) in description
    assert run(cli, "task", "path", "prototype-only") == prototype["artifacts"]
    assert artifact.read_text() == "Approved prototype\n"
    assert snapshot(preplan) == before and (project / ".runweld/runweld.lock").read_bytes() == lock
    assert [task["id"] for task in view("next")["tasks"]] == ["compiled"]
    assert "task-closed" in run(cli, "task", "start", "prototype-only", ok=False)
    assert "task-closed" in run(cli, "--release", pin, "grill", "skip", preplan, "--reason", "Old command", ok=False)
    run(cli, "help", "agents", "--plan", preplan)

    # An admitted write settles before closure. An issued but unstarted command is refused afterward.
    worker = launch(*stale["argv"])
    try:
        for _ in range(200):
            if signal.exists() or worker.poll() is not None:
                break
            time.sleep(.05)
        assert signal.exists(), "phase start did not reach its setup command"
        closer = launch(cli, "task", "cancel", "compiled", *owner, "--json")
        try:
            closer.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        else:
            raise AssertionError("closure returned while a workflow command was still writing")
    finally:
        resume.touch()
        output, error = worker.communicate(timeout=15)
    assert worker.returncode == 0, output + error
    output, error = closer.communicate(timeout=15)
    assert closer.returncode == 0, output + error
    cancelled = json.loads(output)["outcome"]
    assert cancelled["stage"] == "build" and cancelled["outcome"] == "cancelled"
    before = snapshot(plan)
    assert "cancelled" in run(cli, "task", "complete", "compiled", *owner, ok=False)
    assert "task-closed" in run(*stale["argv"], cwd=stale["cwd"], ok=False)
    assert "task-closed" in run(cli, "finish", plan, ok=False)
    assert view("next")["tasks"] == []
    assert {row["outcome"]["outcome"] for row in view("status")} == {"completed", "cancelled"}
    final = view("status", plan)
    assert final["status"] == "building" and not final["integration"] and not final["acceptance"]
    assert final["phases"][0]["status"] == "in progress"
    assert view("status", "--current", cwd=compiled["tree"])[0]["workflow"]["actions"] == []
    assert view("task", "resume", "compiled")["outcome"] == cancelled
    assert snapshot(plan) == before and evidence.read_text() == "Keep this file\n"
    assert run("git", "branch", "--show-current", cwd=compiled["tree"]) == compiled["branch"]
    assert run("git", "rev-parse", "HEAD") == base

    state = state_path.read_bytes()
    state_path.unlink()
    closed = view("status", plan)
    assert closed["status"] == "stopped" and closed["outcome"] == cancelled, closed
    assert view("next")["tasks"] == []
    state_path.write_bytes(state)

    # distribution#task-outcome distribution#project-lock: competing decisions use the pinned route.
    start("race")
    assert view("next", "race")["stage"] == "grill"
    processes = [launch(cli, "task", action, "race", *owner, "--json") for action in ("complete", "cancel")]
    logs = [process.communicate(timeout=15) for process in processes]
    assert sorted(process.returncode for process in processes) == [0, 1], logs
    winning = next(json.loads(log[0])["outcome"] for process, log in zip(processes, logs) if process.returncode == 0)
    assert winning["stage"] == "grill", winning
    assert view("next", "race")["task"]["outcome"] == winning
    assert view("next")["tasks"] == []

    # distribution#task-outcome distribution#project-lock: pre-plan closure doesn't require resuming the task.
    removed = start("removed-tree")
    run("git", "worktree", "remove", removed["tree"])
    assert view("next", "removed-tree")["stage"] == "grill"
    empty = start("empty-draft")
    empty_plan = Path(empty["plan"])
    for stage in ("grill", "prototype"):
        run(cli, stage, "skip", empty_plan, "--reason", "Not needed")
    empty_plan.touch()
    for task, stage, states in ((removed, "grill", ("current", "upcoming")),
                                (empty, "plan", ("skipped", "skipped"))):
        before = snapshot(Path(task["plan"]))
        outcome = view("task", "cancel", task["id"], *owner)["outcome"]
        assert outcome["stage"] == stage and outcome["outcome"] == "cancelled", outcome
        fresh = view("next", task["id"])
        assert fresh["stage"] == stage and fresh["actions"] == [] and fresh["task"]["outcome"] == outcome
        assert fresh["task"]["release"] == pin
        assert tuple(outcome["optional_stages"][name] for name in ("grill", "prototype")) == states
        assert snapshot(Path(task["plan"])) == before
        assert run("git", "rev-parse", task["branch"]) == base
    assert view("next")["tasks"] == []

    run(cli, "update", "--project")
    draft_task = start("compiled-draft")
    draft = Path(draft_task["plan"])
    run(cli, "prototype", "skip", draft, "--reason", "Not needed")
    draft.write_text(draft_text.replace("runweld/compiled", draft_task["branch"]))
    run(cli, "approve", draft)
    before = snapshot(draft)
    stopped = view("task", "cancel", "compiled-draft", *owner)
    assert stopped["status"] == "draft" and stopped["outcome"]["stage"] == "plan"
    assert stopped["release"] != pin and snapshot(draft) == before
    assert "task-closed" in run(cli, "approve", draft, ok=False)
    assert view("next")["tasks"] == []

    # Before optional stage snapshots, outcome records relied on saved discovery history.
    outcome_path = preplan.with_suffix(".outcome.json")
    legacy_decision = {key: decision[key] for key in ("outcome", "stage", "by", "reason", "at")}
    outcome_path.write_text(json.dumps(legacy_decision))
    legacy_view = view("status", preplan)
    assert legacy_view["outcome"] == legacy_decision
    assert [row["state"] for row in legacy_view["workflow"]["stages"][:2]] == ["skipped", "done"]
PY
