#!/usr/bin/env bash
set -euo pipefail
unset CODEX_THREAD_ID CLAUDECODE
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-runweld"
export SUMMARY_FIXTURE="$repo_root/test/lib/summary.md"
python3 -B <<'PY'
from datetime import date
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import time
import tomllib

with tempfile.TemporaryDirectory() as folder:
    home = Path(folder).resolve()
    project = home / "project with spaces"
    project.mkdir()
    env = dict({k: v for k, v in os.environ.items() if not k.startswith("RUNWELD_")},
               GIT_AUTHOR_NAME="Tester", GIT_AUTHOR_EMAIL="test@example.org",
               GIT_COMMITTER_NAME="Tester", GIT_COMMITTER_EMAIL="test@example.org")
    runweld = home / "bin/runweld"

    def run(*args, cwd=project, ok=True):
        p = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
        assert (p.returncode == 0) == ok, p.stdout + p.stderr
        return p.stdout.strip() if ok else p.stdout + p.stderr

    def start(name):
        return subprocess.Popen([runweld, "task", "start", name, "--finish-how", "ff-only", "--finish-target", "main", "--json"], cwd=project, env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def task(p):
        out, err = p.communicate()
        assert p.returncode == 0, f"run#task-worktree: task entry did not create a worktree: {out}{err}"
        return json.loads(out)

    run(os.environ["INSTALLER"], "--prefix", home, cwd=home)
    run("git", "init", "-qb", "main")
    (project / ".gitignore").write_text("*.scratch\n.setup-cache/\n")
    (project / "tracked").write_text("base\n")
    run("git", "add", ".")
    run("git", "commit", "-qm", "base")
    setup = ('mkdir -p .setup-cache; '
             'if [ "${RUNWELD_TASK_PATH##*/}" = one ] && [ ! -f "$RUNWELD_DATA_DIR/attempt" ]; then '
             'touch "$RUNWELD_DATA_DIR/attempt" .setup-cache/partial; exit 31; fi; '
             'touch .setup-cache/complete .setup-cache/changed; '
             'printf "%s\\n" "$RUNWELD_SOURCE_CHECKOUT" "$RUNWELD_TASK_PATH" "$RUNWELD_PORT" "$RUNWELD_DATA_DIR" > "$RUNWELD_DATA_DIR/setup"')
    full = 'test -f "$RUNWELD_DATA_DIR/setup"'
    run(runweld, "init", "--non-interactive", "--provider", "Test", "--primary-model", "primary",
        "--secondary-model", "secondary", "--port", "--data-dir", "--setup", setup, "--full-check", full)
    run("git", "add", ".")
    run("git", "commit", "-qm", "shared Runweld defaults")
    # run#task-worktree: concurrent requests start planning in different task trees; retrying retains identity.
    one, same, two = start("one"), start("one"), start("two")
    a, b = task(one), task(two)
    assert task(same)["tree"] == a["tree"]
    assert a["tree"] != b["tree"] and a["branch"] != b["branch"]
    assert run("git", "branch", "--show-current") == "main"
    for row in (a, b):
        tree = Path(row["tree"])
        folder = Path(row["plan"]).parent
        assert folder == project / ".runweld/workflow/plans" / f"{date.today()}-{row['id']}", (
            f"distribution#task-artifacts: task {row['id']} must be reserved in one dated folder")
        assert Path(row["artifacts"]).is_relative_to(folder)
        own = json.loads(run(runweld, "next", "--json", cwd=tree))
        assert own["task"]["id"] == row["id"] and own["task"]["artifacts"] == row["artifacts"]
        assert own["actions"] and row["plan"] in run(runweld, "next", cwd=tree)
        assert row["branch"] == f"runweld/{row['id']}"
        assert (tree / "tracked").exists() and not (Path(row["artifacts"]) / "data").exists()
        assert run("git", "branch", "--show-current", cwd=tree) == row["branch"]
        view, = json.loads(run(runweld, "status", "--current", "--json", cwd=tree))
        assert view["plan"] == row["id"] and view["workflow"]["actions"]
        assert json.loads(run(runweld, "task", "resume", row["id"], "--json"))["tree"] == row["tree"]
    assert {r["plan"] for r in json.loads(run(runweld, "status", "--json"))} == {"one", "two"}
    # distribution#task-artifacts: the main checkout lists choices without selecting either task.
    choices = json.loads(run(runweld, "next", "--json"))
    assert choices.get("task") is None and {t["id"] for t in choices["tasks"]} == {"one", "two"}
    assert "runweld next two" in run(runweld, "next")
    assert json.loads(run(runweld, "next", "two", "--json"))["task"]["tree"] == b["tree"]
    assert run(runweld, "task", "path", "one", "browser-test") == str(Path(a["artifacts"]) / "browser-test")
    release = (home / "lib/runweld/default").read_text().strip()
    browser = home / "lib/runweld/releases" / release / "workflow/browser-test/tab.mjs"
    for row in (a, b):
        assert f"Artifacts: {Path(row['artifacts']) / 'browser-test'}" in run("node", browser, "--help", cwd=Path(row["tree"]))

    def make_plan(row, spec=True):
        path = Path(row["plan"])
        rules = """+ example — Example
  About: Shared rules.
+ example#worktree-check — Shared rule
  Why: Each task applies the rules in its own tree.
  Done: 1""" if spec else "none"
        path.write_text(f"""# Plan: {row['id']}

Status: draft · branch `{row['branch']}` · base `{row['base']}`

## Result

Show the task.

## Approach

Make and report the change.

## Out of scope

- Other work.

## Phases

### 1. Edit — `waiting`
Territory: `tracked`
Skills: `local-skill.md`
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture

## Done

1. Read tracked → the task's change — you check

## Spec

{rules}
""")
        # planning#early-progress: omitting a goal does not bypass recording optional stages.
        assert "discovery-incomplete" in run(runweld, "spec", "check", path, ok=False)
        assert "discovery-incomplete" in run(runweld, "approve", path, ok=False)
        for stage in ("grill", "prototype"):
            view = json.loads(run(runweld, "next", "--json", cwd=Path(row["tree"])))
            assert view["stage"] == stage
            run(runweld, stage, "skip", path, "--reason", "The fixture follows a settled plan")
        # This source instruction is deliberately absent from the main checkout.
        skill = Path(row["tree"]) / "local-skill.md"
        caller_skill = project / skill.name
        caller_skill.write_text("Not available to the task worker\n")
        refused = run(runweld, "approve", path, ok=False)
        assert "local-skill.md" in refused and not path.with_suffix(".json").exists(), refused
        caller_skill.unlink()
        skill.write_text("Task-local skill\n")
        handoff = path.parent / "planning-handoff.md"
        handoff.write_text("# Handoff\n\nInvestigate in the task checkout.\n")
        run(runweld, "spec", "check", path, cwd=home)
        run_file = path.with_suffix(".run.toml")
        snapshot = run_file.read_text()
        for key, invalid in (("version", "1.2.3-other"), ("digest", "0" * 64), ("digest", "invalid")):
            run_file.write_text(re.sub(rf'(?m)^{key} = "[^"]+"$', f'{key} = "{invalid}"', snapshot))
            assert "[workflow]" in run(runweld, "approve", path, ok=False)
            assert not path.with_suffix(".json").exists()
        unpinned = re.sub(r"(?m)^\[workflow\]\nversion = [^\n]+\ndigest = [^\n]+\n", "", snapshot)
        run_file.write_text(unpinned)
        assert "[workflow]" in run(runweld, "approve", path, ok=False)
        assert not path.with_suffix(".json").exists(), "run#starts-from-last: no state may bind a missing task pin"
        run_file.write_text(snapshot)
        run(runweld, "approve", path, cwd=home)
        skill.unlink()
        path.with_suffix(".summary.md").write_bytes(Path(os.environ["SUMMARY_FIXTURE"]).read_bytes())
        revision = json.loads(run(runweld, "plan", "review", path, "--json"))["revision"]
        approval = ("plan", "approve", path, "--revision", revision, "--by", "Fixture Human", "--words", "Approve the plan and run")
        run_file.write_text(unpinned)
        assert "[workflow]" in run(runweld, *approval, ok=False)
        run_file.write_text(snapshot)
        run(runweld, *approval)
        discovery = json.loads(run(runweld, "next", "--json", cwd=Path(row["tree"])))["task"]["discovery"]
        assert {stage: (fact["status"], fact["reason"]) for stage, fact in discovery.items()} == dict.fromkeys(
            ("grill", "prototype"), ("skipped", "The fixture follows a settled plan"))
        return path

    a_plan, b_plan = make_plan(a), make_plan(b)
    relative = a_plan.relative_to(project)
    assert json.loads(run(runweld, "status", relative, "--json", cwd=Path(a["tree"])))["path"] == str(a_plan)
    for row in (a, b):
        assert not (Path(row["artifacts"]) / "data").exists(), "run#worktree-setup: planning must not prepare runtime"
    run(runweld, "build", "start", a_plan, "--branch", "must-not-switch", ok=False)
    for row in (a, b):
        out = run(runweld, "build", "start", row["plan"], cwd=home)
        assert row["tree"] in out
    a_data, b_data = (Path(row["artifacts"]) / "data" for row in (a, b))
    assert not (a_data / "setup").exists(), "run#worktree-setup: approval and task checkout are not setup"
    assert "setup exited 31" in run(runweld, "phase", "start", a_plan, "1", ok=False)
    still = json.loads(run(runweld, "status", a_plan, "--json"))
    assert still["phases"][0]["status"] == "waiting" and still["tree"] == a["tree"]
    run(runweld, "phase", "start", a_plan, "1")
    run(runweld, "phase", "start", b_plan, "1")
    first_env = (a_data / "setup").read_text().splitlines()
    second_env = (b_data / "setup").read_text().splitlines()
    assert first_env == [str(project), a["tree"], str(still["alloc"]["port"]), str(a_data)]
    assert second_env[:2] == [str(project), b["tree"]] and second_env[-1] == str(b_data)
    assert first_env[2] != second_env[2], "run#worktree-setup: task ports must be distinct"
    setup_mtime = (a_data / "setup").stat().st_mtime_ns
    run(runweld, "task", "setup", a_plan)
    assert (a_data / "setup").stat().st_mtime_ns == setup_mtime

    def accepted(row, plan, merge_request=False):
        tree = Path(row["tree"])
        (tree / "tracked").write_text(row["id"] + "\n")
        run("git", "commit", "-qam", "task change", cwd=tree)
        sha = run("git", "rev-parse", "HEAD", cwd=tree)
        run(runweld, "phase", "report", plan, "1", "--became", "Done", "--commit", sha)
        run(runweld, "phase", "done", plan, "1")
        output = run(runweld, "gate", "start", plan)
        assert "spec write refused" not in output, output
        assert " RED" not in output, output
        reviewer = Path(run(runweld, "brief", "reviewer", plan, "--provider", "Test"))
        review = next(line.removeprefix("- Complete the review: ") for line in reviewer.read_text().splitlines()
                      if line.startswith("- Complete the review: "))
        run(*shlex.split(review), cwd=home)
        run(runweld, "verdict", "pass", plan, "--report", "Ready", "--predicted", "pass", "--engine", "fixture")
        shape = Path(run(runweld, "land", "draft", plan).removeprefix("land draft: "))
        shape.write_text(shape.read_text().replace('message = ""', 'message = "feat: record task change"')
                         .replace('walkthrough = ""', 'walkthrough = "Read the task change and its rules."'))
        run(runweld, "land", plan)
        guide = "Open tracked.\n\n#### Checks\n- **Done 1** Read tracked → the task's change.\n\n#### Decisions\n- —"
        run(runweld, "page", plan, "--guide", guide, *(("--message", "Task merge request") if merge_request else ()))
        run(runweld, "accept", plan, "--by", "Fixture Human", "--words", "Accept result")

    accepted(a, a_plan)
    accepted(b, b_plan)
    assert (Path(a["tree"]) / "docs/spec/example.md").exists()
    assert (Path(b["tree"]) / "docs/spec/example.md").exists()
    assert not (project / "docs/spec/example.md").exists()
    capture = Path(a["artifacts"]) / "capture.txt"
    capture.write_text("private evidence")
    # finish#by-run-file: remove owned output, never discard unknown or changed ignored files.
    scratch = Path(a["tree"]) / ".setup-cache/unknown"
    changed = scratch.with_name("changed")
    changed.write_text("locally changed")
    scratch.write_text("retain me")
    out = run(runweld, "finish", a_plan, cwd=Path(a["tree"]))
    assert "integration is already recorded" in out and ".setup-cache/unknown" in out, out
    assert scratch.read_text() == "retain me" and a_data.exists()
    assert changed.read_text() == "locally changed"
    assert not scratch.with_name("partial").exists() and not scratch.with_name("complete").exists()
    assert (project / "tracked").read_text() == "one\n"
    assert (project / "docs/spec/example.md").exists()
    view = json.loads(run(runweld, "status", a_plan, "--json"))
    assert view["status"] == "merged" and "cleanup" in view["workflow"]["actions"][0]["action"]
    pending = json.loads(run(runweld, "next", "one", "--json"))
    assert ".setup-cache/unknown" in pending["task"]["cleanup_pending"]
    retry, = pending["actions"]
    assert retry["cwd"] == str(project)
    target = run("git", "rev-parse", "refs/heads/main")
    scratch.unlink()
    changed.unlink()
    done = json.loads(run(*retry["argv"], "--json", cwd=retry["cwd"]))
    assert done["status"] == "merged" and done["cleanup_pending"] is None
    assert done["integration"]["verified"] and done["integration"]["commit"] == target == run("git", "rev-parse", "refs/heads/main")
    assert not Path(a["tree"]).exists() and not a_data.exists()
    assert a_plan.exists()
    assert capture.read_text() == "private evidence"
    assert a_plan.with_suffix(".json").exists()
    assert list(a_plan.parent.glob("*.brief-*.md")), "distribution#task-artifacts: briefs remain beside the plan"
    merged = json.loads(run(runweld, "task", "resume", "one", "--json"))
    assert merged["status"] == "merged" and not merged["workflow"]["actions"]
    assert json.loads(run(runweld, "task", "resume", "two", "--json"))["status"] == "passed"
    out = run(runweld, "finish", b_plan, ok=False)
    assert "merge-refused" in out and "round start" in out
    assert (Path(b["tree"]) / "tracked").read_text() == "two\n"
    assert (project / "tracked").read_text() == "one\n"
    assert run("git", "status", "--short") == ""

    # run#worktree-setup, run#task-worktree: no command is required and a pending merge request retains its tree.
    config = project / ".runweld/config.toml"
    before = config.read_text()
    adjusted = re.sub(r"(?ms)^\[setup\]\n.*?(?=^\[|\Z)", "", before)
    config.write_text(adjusted.replace(json.dumps(full), '"true"'))
    c = json.loads(run(runweld, "task", "start", "request", "--finish-how", "merge-request", "--finish-target", "main", "--json"))
    config.write_text(before)
    assert "setup" not in tomllib.loads(Path(c["plan"]).with_suffix(".run.toml").read_text())
    c_plan = make_plan(c, spec=False)
    run(runweld, "build", "start", c_plan)
    run(runweld, "phase", "start", c_plan, "1")
    accepted(c, c_plan, merge_request=True)
    run("git", "remote", "add", "origin", "https://forge.example/fixture/project.git")
    out = run(runweld, "finish", c_plan)
    assert "nothing was pushed" in out and Path(c["tree"]).is_dir()
    link = "https://forge.example/fixture/project/requests/1"
    run(runweld, "plan", "status", c_plan, link)
    assert "once it is merged" in run(runweld, "finish", c_plan) and Path(c["tree"]).is_dir()
    run(runweld, "finish", c_plan, "--merged")
    assert not Path(c["tree"]).exists() and c_plan.exists()
    assert (project / "tracked").read_text() == "one\n"
    rows = json.loads(run(runweld, "status", "--json"))
    assert {row["plan"]: row["status"] for row in rows} == {"one": "merged", "two": "passed", "request": "merged"}

    # distribution#task-artifacts: retry a reservation after a failed Git checkout on a different local date.
    hook = project / ".git/hooks/post-checkout"
    hook.write_text("#!/bin/sh\nexit 17\n")
    hook.chmod(0o755)
    os.environ["TZ"] = env["TZ"] = "Etc/GMT+12"
    time.tzset()
    first_date = date.today()
    assert "task-worktree" in run(runweld, "task", "start", "cross-midnight", "--finish-how", "ff-only", "--finish-target", "main", ok=False)
    hook.unlink()
    os.environ["TZ"] = env["TZ"] = "Etc/GMT-14"
    time.tzset()
    assert date.today() != first_date
    before_retry = json.loads(run(runweld, "next", "cross-midnight", "--json"))
    retry, = before_retry["actions"]
    assert retry["kind"] == "run" and retry["argv"][-3:] == ["task", "start", "cross-midnight"]
    retried = json.loads(run(*retry["argv"], "--json", cwd=Path(retry["cwd"])))
    dated = project / ".runweld/workflow/plans"
    assert [folder.name for folder in dated.glob("*-cross-midnight")] == [f"{first_date}-cross-midnight"]
    assert Path(retried["plan"]).parent == dated / f"{first_date}-cross-midnight"
PY
