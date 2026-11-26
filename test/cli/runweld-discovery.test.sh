#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-runweld"
python3 -B <<'PY'
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

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
    run(cli, "run", "approve", plan, "--by", "Tester", "--words", "Approve the run")
    summary = plan.with_suffix(".summary.md")
    summary.write_text(f"Review [this plan]({plan.name}) and its checks.\n")
    run(cli, "summary", "approve", plan, "--file", summary, "--by", "Tester", "--words", "Approve the plan")
    stamp = (data / "ready").stat().st_mtime_ns
    run(cli, "build", "start", plan)
    run(cli, "phase", "start", plan, "1")
    assert next_from(bug)["task"]["alloc"]["port"] == int(port)
    assert (data / "ready").stat().st_mtime_ns == stamp
PY
