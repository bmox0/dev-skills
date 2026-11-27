#!/usr/bin/env bash
set -euo pipefail
unset CODEX_THREAD_ID CLAUDECODE
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-runweld"
export SUMMARY_FIXTURE="$repo_root/test/lib/summary.md"
python3 -B <<'PY'
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import tomllib

with tempfile.TemporaryDirectory() as tmp:
    prefix = Path(tmp).resolve()
    repo = prefix / "project with spaces"
    repo.mkdir()
    env = {**os.environ, "GIT_AUTHOR_NAME": "Tester", "GIT_AUTHOR_EMAIL": "test@example.org",
           "GIT_COMMITTER_NAME": "Tester", "GIT_COMMITTER_EMAIL": "test@example.org"}
    cli = prefix / "bin/runweld"

    def run(*argv, cwd=repo, ok=True):
        p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True)
        assert (p.returncode == 0) == ok, f"{argv}: {p.stdout}{p.stderr}"
        return (p.stdout if ok else p.stdout + p.stderr).strip()

    def new(name, goal, *args):
        p = subprocess.run([cli, "task", "start", name, "--goal", goal, "--finish-how", "ff-only",
                            "--finish-target", "main", *args, "--json"], cwd=repo, env=env, capture_output=True, text=True)
        assert p.returncode == 0, f"planning#early-progress: task entry must retain intent and expose starter actions: {p.stdout}{p.stderr}"
        return json.loads(p.stdout)

    def next_from(row):
        return json.loads(run(cli, "next", "--json", cwd=row["tree"]))

    def action(view, suffix):
        step, = (step for step in view["actions"] if step.get("argv", [])[-len(suffix):] == list(suffix))
        return step

    def follow(step, *args):
        return run(*step["argv"], *args, cwd=step["cwd"])

    def record(row, *args, ok=True):
        return run(cli, "task", "stage", row["plan"], *args, ok=ok)

    run(os.environ["INSTALLER"], "--prefix", prefix)
    run("git", "init", "-qb", "main")
    (repo / "example.txt").write_text("wrong\n")
    run("git", "add", "example.txt")
    run("git", "commit", "-qm", "base")
    setup = r'printf "%s\n" "$RUNWELD_PORT" > "$RUNWELD_DATA_DIR/ready"'
    run(cli, "init", "--non-interactive", "--provider", "Test", "--primary-model", "planner",
        "--secondary-model", "helper", "--setup", setup, "--data-dir", "--port")
    run("git", "add", ".")
    run("git", "commit", "-qm", "shared settings")
    earlier = run("git", "rev-parse", "HEAD")
    (repo / "example.txt").write_text("right\n")
    run("git", "commit", "-qam", "different source revision")

    # planning#early-progress: resume an interrupted grill with its intent, decisions and questions.
    feature = new("feature", "Make the result readable")
    first = next_from(feature)
    assert first["task"]["goal"] == "Make the result readable" and first["stage"] == "grill"
    start = action(first, ("grill", "start", feature["plan"]))
    assert shlex.join(start["argv"]) in run(cli, "next", cwd=feature["tree"])
    follow(start)
    run(cli, "grill", "save", "--result", "Keep the existing order", "--question", "Which format?", cwd=feature["tree"])
    resumed = next_from(feature)
    grill = resumed["task"]["discovery"]["grill"]
    assert grill["entered"] and grill["status"] == "active"
    assert grill["result"] == "Keep the existing order" and grill["questions"] == ["Which format?"]
    output = run(cli, "next", cwd=feature["tree"])
    assert "Keep the existing order" in output and "Which format?" in output
    guide = next(step["assignment"] for step in resumed["actions"] if step["kind"] == "work")
    guide_out = run(*guide["instructions"][0], cwd=guide["cwd"])
    assert "Interview me about every aspect" in guide_out
    assert "# ADR Format" not in guide_out
    ref, = (line for line in guide_out.splitlines() if "ADR-FORMAT.md --plan" in line)
    ref_argv = shlex.split(ref.partition(" — ")[2])
    assert feature["release"] in ref_argv and feature["plan"] in ref_argv
    assert "# ADR Format" in run(*ref_argv, cwd=prefix)
    assert "release resource" in run(cli, "reference", "../../.git/config", "--plan", feature["plan"], ok=False)

    record(feature, "grill", "done", "--result", "Use plain text and keep the existing order")
    assert next_from(feature)["stage"] == "prototype"
    record(feature, "prototype", "skip", "--reason", "There is no layout uncertainty")
    plan_view = next_from(feature)
    assert plan_view["stage"] == "plan" and plan_view["task"]["discovery"]["prototype"]["reason"] == "There is no layout uncertainty"
    assert "required" in record(feature, "plan", "skip", "--reason", "Not useful", ok=False)

    # planning#run-route distribution#project-lock: each task has its own route.
    direct = new("direct", "No discovery needed")
    layout = new("layout", "A prototype is needed")
    shared = {repo / ".runweld" / name: (repo / ".runweld" / name).read_bytes()
              for name in ("config.toml", "runweld.lock")}

    def route(row, settings):
        path = Path(row["plan"]).with_suffix(".run.toml")
        text = path.read_text().split("\n[route]\n", 1)[0]
        path.write_text(text + "\n[route]\n" + settings)
        return path

    direct_run = route(direct, 'grill = "skip"\nprototype = "skip"\n')
    layout_run = route(layout, 'grill = "skip"\nprototype = "take"\n')
    assert next_from(direct)["stage"] == "plan", "planning#run-route: skip both optional stages"
    resumed = json.loads(run(cli, "task", "resume", "direct", "--json"))
    assert [row["state"] for row in resumed["workflow"]["stages"][:2]] == ["skipped by route"] * 2
    assert "current stage" in record(direct, "grill", "start", ok=False)
    layout_view = next_from(layout)
    assert layout_view["stage"] == "prototype"
    assert not any("skip" in step.get("argv", []) for step in layout_view["actions"])
    assert "prototype" in record(layout, "prototype", "skip", "--reason", "Skip anyway", ok=False)
    follow(action(layout_view, ("prototype", "start", layout["plan"])))
    record(layout, "prototype", "done", "--result", "The layout works")
    assert next_from(layout)["stage"] == "plan"
    route(layout, 'grill = "skip"\nprototype = "skip"\n')
    assert next_from(layout)["task"]["discovery"]["prototype"]["result"] == "The layout works"
    chosen = direct_run.read_bytes()
    for bad, setting in (('grill = "maybe"', "grill"), ('prototype = true', "prototype"), ('build = "skip"', "build")):
        route(direct, bad + "\n")
        out = run(cli, "next", "direct", ok=False)
        assert "[route]" in out and setting in out and str(direct_run) in out
        assert "[route]" in run(cli, "run", "check", direct["plan"], ok=False)
        assert "[route]" in record(direct, "grill", "start", ok=False)
    direct_run.write_bytes(chosen)
    # build#workflow-progress planning#run-route distribution#task-outcome: closure preserves route history.
    early_exit = new("early-exit", "Goal met without building")
    route(early_exit, 'grill = "skip"\nprototype = "skip"\n')
    resumed = json.loads(run(cli, "task", "resume", "early-exit", "--json"))
    assert [row["state"] for row in resumed["workflow"]["stages"][:2]] == ["skipped by route"] * 2
    closed = json.loads(run(cli, "task", "complete", "early-exit", "--by", "Owner", "--reason", "Goal met", "--json"))
    assert closed["outcome"]["stage"] == "plan"
    assert closed["workflow"]["stages"][:2] == resumed["workflow"]["stages"][:2], closed["workflow"]["stages"][:2]
    route(early_exit, 'grill = "ask"\nprototype = "take"\n')
    reopened = json.loads(run(cli, "task", "resume", "early-exit", "--json"))
    assert reopened["workflow"]["stages"][:2] == resumed["workflow"]["stages"][:2]
    assert reopened["workflow"]["actions"] == []
    assert tomllib.loads(layout_run.read_text())["route"]["prototype"] == "skip"
    assert all(path.read_bytes() == before for path, before in shared.items())

    trial = new("trial", "Compare two layouts")
    record(trial, "grill", "skip", "--reason", "The layout question is already clear")
    follow(action(next_from(trial), ("prototype", "start", trial["plan"])))
    record(trial, "prototype", "save", "--result", "Two versions drawn", "--question", "A or B?")
    assert next_from(trial)["task"]["discovery"]["prototype"]["questions"] == ["A or B?"]
    proto = Path(trial["artifacts"]) / "layout.html"
    proto.write_text("<h1>Layout A</h1>\n")
    transition = record(trial, "prototype", "done", "--result", "Choose A", "--artifact", proto)
    assert shlex.join(next_from(trial)["actions"][0]["assignment"]["instructions"][0]) in transition
    assert next_from(trial)["task"]["discovery"]["prototype"]["questions"] == []
    assert next_from(trial)["task"]["discovery"]["prototype"]["artifact"] == str(proto)

    # planning#early-progress: reproduce in the registered worktree without touching the source checkout.
    bug = new("bug", "Wrong example result", "--bug", "--base", earlier)
    assert run("git", "rev-parse", "HEAD", cwd=bug["tree"]) == earlier
    assert "required" in record(bug, "reproduce", "skip", "--reason", "No time", ok=False)
    follow(action(next_from(bug), ("bug", "start", bug["plan"])))
    active = next_from(bug)
    preview = action(active, ("--reproduction", "--preview"))
    start_setup = action(active, (bug["plan"], "--reproduction"))
    out = follow(preview)
    data = Path(bug["artifacts"]) / "data"
    assert setup in out and bug["tree"] in out and str(data) in out and "port" in out.lower()
    assert not data.exists() and not (Path(bug["artifacts"]) / ".setup.lock").exists()
    follow(start_setup)
    port = (data / "ready").read_text()
    assert int(port) > 0
    assert action(next_from(bug), ("--reproduction", "--preview"))["effects"]["recorded"]
    other_bug = new("other-bug", "Another bug", "--bug")
    record(other_bug, "reproduce", "start")
    follow(action(next_from(other_bug), (other_bug["plan"], "--reproduction")))
    assert (Path(other_bug["artifacts"]) / "data/ready").read_text() != port
    art = Path(bug["artifacts"]) / "bug.red.patch"
    art.write_text("diff --git a/reproduce.sh b/reproduce.sh\nnew file mode 100644\n"
                   "--- /dev/null\n+++ b/reproduce.sh\n@@ -0,0 +1 @@\n+grep -qx right example.txt\n")
    run("git", "apply", art, cwd=bug["tree"])
    reproduction = "sh reproduce.sh"
    assert subprocess.run(reproduction, shell=True, cwd=bug["tree"]).returncode == 1
    (Path(bug["tree"]) / "reproduce.sh").unlink()
    assert (repo / "example.txt").read_text() == "right\n"

    plan = Path(bug["plan"])
    draft = f"""# Plan: Fix example result

Status: draft · branch `{bug['branch']}` · base `{earlier}`

## Result

The example returns the right value.

## Approach

Apply {art} and run {reproduction}.

## Out of scope

- Other examples.

## Phases

### 1. Correct the result — `waiting`
Territory: `example.txt`, `reproduce.sh`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture

## Done

1. Run the reproduction → the result is right.

## Spec

none
"""
    trial_plan = Path(trial["plan"])
    trial_plan.write_text(draft.replace('runweld/bug', trial["branch"]).replace(earlier, trial["base"]))
    run(cli, "approve", trial_plan)
    trial_plan.with_suffix(".summary.md").write_bytes(Path(os.environ["SUMMARY_FIXTURE"]).read_bytes())
    preview = json.loads(run(cli, "plan", "review", trial_plan, "--json"))
    assert preview["evidence"] == {"prototype": {"result": "Choose A", "artifact": str(proto)}}
    assert proto.as_uri() in run(cli, "plan", "review", trial_plan)
    direct_plan = Path(direct["plan"])
    direct_plan.write_text(draft.replace('runweld/bug', direct["branch"]).replace(earlier, direct["base"]))
    run(cli, "approve", direct_plan)
    direct_plan.with_suffix(".summary.md").write_bytes(Path(os.environ["SUMMARY_FIXTURE"]).read_bytes())
    approval = json.loads(run(cli, "plan", "review", direct_plan, "--json"))["revision"]
    assert "plan-unapproved" in run(cli, "build", "start", direct_plan, ok=False)
    route(direct, 'grill = "take"\nprototype = "skip"\n')
    assert "restore the discovery route" in run(cli, "plan", "approve", direct_plan, "--revision", approval,
                                                "--by", "Tester", "--words", "Approve the plan and run", ok=False)
    direct_run.write_bytes(chosen)
    run(cli, "plan", "approve", direct_plan, "--revision", approval, "--by", "Tester", "--words", "Approve the plan and run")
    direct_view = json.loads(run(cli, "status", direct_plan, "--json"))
    assert [row["state"] for row in direct_view["workflow"]["stages"][:2]] == ["skipped by route"] * 2

    plan.write_text(draft)
    assert "reproduction" in run(cli, "approve", plan, ok=False).lower()
    assert "red" in record(bug, "reproduce", "done", "--result", "The source says wrong", "--command", reproduction, ok=False)
    record(bug, "reproduce", "done", "--result", "The source says wrong", "--command", reproduction, "--artifact", art)
    planned = next_from(bug)
    assert planned["stage"] == "plan"
    evidence = planned["task"]["discovery"]["reproduce"]
    assert evidence["command"] == reproduction and evidence["artifact"] == str(art)
    assert reproduction in run(cli, "next", cwd=bug["tree"])
    assert earlier in run(cli, "spec", "check", plan, "--base", "main", ok=False)
    plan.write_text(draft.replace(earlier, run("git", "rev-parse", "HEAD")))
    assert earlier in run(cli, "spec", "check", plan, ok=False)
    plan.write_text(draft)
    run(cli, "spec", "check", plan, cwd=prefix)
    run(cli, "approve", plan, cwd=prefix)
    plan.with_suffix(".summary.md").write_bytes(Path(os.environ["SUMMARY_FIXTURE"]).read_bytes())
    review = json.loads(run(cli, "plan", "review", plan, "--json"))
    assert review["evidence"] == {"reproduce": {"result": "The source says wrong", "command": reproduction, "artifact": str(art)}}
    screen = run(cli, "plan", "review", plan)
    assert "Bug cause: The source says wrong" in screen and reproduction in screen and art.as_uri() in screen
    run(cli, "plan", "approve", plan, "--revision", review["revision"], "--by", "Tester", "--words", "Approve the plan and run")
    stamp = (data / "ready").stat().st_mtime_ns
    run(cli, "build", "start", plan)
    run(cli, "phase", "start", plan, "1")
    assert next_from(bug)["task"]["alloc"]["port"] == int(port)
    assert (data / "ready").stat().st_mtime_ns == stamp
PY
