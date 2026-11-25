#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-ds"
python3 -B <<'PY'
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import tomllib

with tempfile.TemporaryDirectory() as folder:
    home = Path(folder).resolve()
    project = home / "project with spaces"
    project.mkdir()
    env = dict(os.environ, GIT_AUTHOR_NAME="Tester", GIT_AUTHOR_EMAIL="test@example.org",
               GIT_COMMITTER_NAME="Tester", GIT_COMMITTER_EMAIL="test@example.org")
    ds = home / "bin/ds"

    def run(*args, cwd=project, ok=True):
        p = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
        assert (p.returncode == 0) == ok, p.stdout + p.stderr
        return p.stdout.strip() if ok else p.stdout + p.stderr

    def start(name):
        return subprocess.Popen([ds, "task", "start", name, "--json"], cwd=project, env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def task(p):
        out, err = p.communicate()
        assert p.returncode == 0, f"run#task-worktree: task entry did not create a worktree: {out}{err}"
        return json.loads(out)

    run(os.environ["INSTALLER"], "--prefix", home, cwd=home)
    run("git", "init", "-qb", "main")
    (project / ".gitignore").write_text("*.scratch\n")
    (project / "tracked").write_text("base\n")
    run("git", "add", ".")
    run("git", "commit", "-qm", "base")
    setup = ('if [ "${DS_TASK_PATH##*/}" = one ] && [ ! -f "$DS_DATA_DIR/attempt" ]; then '
             'touch "$DS_DATA_DIR/attempt"; exit 31; fi; '
             'printf "%s\\n" "$DS_SOURCE_CHECKOUT" "$DS_TASK_PATH" "$DS_PORT" "$DS_DATA_DIR" > "$DS_DATA_DIR/setup"')
    full = 'test -f "$DS_DATA_DIR/setup"'
    run(ds, "init", "--non-interactive", "--provider", "Test", "--primary-model", "primary",
        "--secondary-model", "secondary", "--port", "--data-dir", "--setup", setup, "--full-check", full)
    run("git", "add", ".")
    run("git", "commit", "-qm", "shared ds defaults")
    # run#task-worktree: concurrent requests start planning in different task trees; retrying retains identity.
    one, same, two = start("one"), start("one"), start("two")
    a, b = task(one), task(two)
    assert task(same)["tree"] == a["tree"]
    assert a["tree"] != b["tree"] and a["branch"] != b["branch"]
    assert run("git", "branch", "--show-current") == "main"
    for row in (a, b):
        tree = Path(row["tree"])
        assert (tree / "tracked").exists() and not (Path(row["artifacts"]) / "data").exists()
        assert run("git", "branch", "--show-current", cwd=tree) == row["branch"]
        view, = json.loads(run(ds, "status", "--current", "--json", cwd=tree))
        assert view["plan"] == row["id"] and view["workflow"]["actions"]
        assert json.loads(run(ds, "task", "resume", row["id"], "--json"))["tree"] == row["tree"]
    assert {r["plan"] for r in json.loads(run(ds, "status", "--json"))} == {"one", "two"}
    assert run(ds, "task", "path", "one", "browser-test") == str(Path(a["artifacts"]) / "browser-test")
    release = run(ds, "--version")
    browser = home / "lib/dev-skills/releases" / release / "skills/browser-test/tab.mjs"
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
        # This source instruction is deliberately absent from the main checkout.
        skill = Path(row["tree"]) / "local-skill.md"
        caller_skill = project / skill.name
        caller_skill.write_text("Not available to the task worker\n")
        refused = run(ds, "approve", path, ok=False)
        assert "local-skill.md" in refused and not path.with_suffix(".json").exists(), refused
        caller_skill.unlink()
        skill.write_text("Task-local skill\n")
        handoff = path.parent / "planning-handoff.md"
        handoff.write_text("# Handoff\n\nInvestigate in the task checkout.\n")
        run(ds, "spec", "check", path, cwd=home)
        run_file = path.with_suffix(".run.toml")
        snapshot = run_file.read_text()
        unpinned = re.sub(r"(?m)^\[workflow\]\nrelease = [^\n]+\n", "", snapshot)
        run_file.write_text(unpinned)
        assert "[workflow].release" in run(ds, "approve", path, ok=False)
        assert not path.with_suffix(".json").exists(), "run#starts-from-last: no state may bind a missing task pin"
        run_file.write_text(snapshot)
        run(ds, "approve", path, cwd=home)
        skill.unlink()
        run_file.write_text(unpinned)
        assert "[workflow].release" in run(ds, "run", "approve", path, "--by", "User", "--words", "Approve this run", ok=False)
        run_file.write_text(snapshot)
        run(ds, "run", "approve", path, "--by", "User", "--words", "Approve this run")
        summary = path.with_suffix(".summary.md")
        summary.write_text(f"Review [this plan]({path.name}) and its checks.\n")
        run(ds, "summary", "approve", path, "--file", summary, "--by", "User", "--words", "Approve summary")
        return path

    a_plan, b_plan = make_plan(a), make_plan(b)
    relative = a_plan.relative_to(project)
    assert json.loads(run(ds, "status", relative, "--json", cwd=Path(a["tree"])))["path"] == str(a_plan)
    for row in (a, b):
        assert not (Path(row["artifacts"]) / "data").exists(), "run#worktree-setup: planning must not prepare runtime"
    run(ds, "build", "start", a_plan, "--branch", "must-not-switch", ok=False)
    for row in (a, b):
        out = run(ds, "build", "start", row["plan"], cwd=home)
        assert row["tree"] in out
    a_data, b_data = (Path(row["artifacts"]) / "data" for row in (a, b))
    assert not (a_data / "setup").exists(), "run#worktree-setup: approval and task checkout are not setup"
    assert "setup exited 31" in run(ds, "phase", "start", a_plan, "1", ok=False)
    still = json.loads(run(ds, "status", a_plan, "--json"))
    assert still["phases"][0]["status"] == "waiting" and still["tree"] == a["tree"]
    run(ds, "phase", "start", a_plan, "1")
    run(ds, "phase", "start", b_plan, "1")
    first_env = (a_data / "setup").read_text().splitlines()
    second_env = (b_data / "setup").read_text().splitlines()
    assert first_env == [str(project), a["tree"], str(still["alloc"]["port"]), str(a_data)]
    assert second_env[:2] == [str(project), b["tree"]] and second_env[-1] == str(b_data)
    assert first_env[2] != second_env[2], "run#worktree-setup: task ports must be distinct"
    setup_mtime = (a_data / "setup").stat().st_mtime_ns
    run(ds, "task", "setup", a_plan)
    assert (a_data / "setup").stat().st_mtime_ns == setup_mtime

    def accepted(row, plan, merge_request=False):
        tree = Path(row["tree"])
        (tree / "tracked").write_text(row["id"] + "\n")
        run("git", "commit", "-qam", "task change", cwd=tree)
        sha = run("git", "rev-parse", "HEAD", cwd=tree)
        run(ds, "phase", "report", plan, "1", "--became", "Done", "--commit", sha)
        run(ds, "phase", "done", plan, "1")
        output = run(ds, "gate", "start", plan)
        assert "spec write refused" not in output, output
        assert " RED" not in output, output
        reviewer = Path(run(ds, "brief", "reviewer", plan, "--provider", "Test"))
        review = next(line.removeprefix("- Complete the review: ") for line in reviewer.read_text().splitlines()
                      if line.startswith("- Complete the review: "))
        run(*shlex.split(review), cwd=home)
        run(ds, "verdict", "pass", plan, "--report", "Ready", "--predicted", "pass", "--engine", "fixture")
        shape = Path(run(ds, "land", "draft", plan).removeprefix("land draft: "))
        shape.write_text(shape.read_text().replace('message = ""', 'message = "feat: record task change"')
                         .replace('walkthrough = ""', 'walkthrough = "Read the task change and its rules."'))
        run(ds, "land", plan)
        guide = "Open tracked.\n\n#### Checks\n- **Done 1** Read tracked → the task's change.\n\n#### Decisions\n- —"
        run(ds, "page", plan, "--guide", guide, *(("--message", "Task merge request") if merge_request else ()))
        run(ds, "accept", plan, "--by", "user", "--words", "Accept result")

    accepted(a, a_plan)
    accepted(b, b_plan)
    assert (Path(a["tree"]) / "docs/spec/example.md").exists()
    assert (Path(b["tree"]) / "docs/spec/example.md").exists()
    assert not (project / "docs/spec/example.md").exists()
    scratch = Path(a["tree"]) / "unsaved.scratch"
    scratch.write_text("retain me")
    out = run(ds, "finish", a_plan, cwd=Path(a["tree"]))
    assert "integration is already recorded" in out and "unsaved.scratch" in out, out
    assert scratch.read_text() == "retain me" and a_data.exists()
    assert (project / "tracked").read_text() == "one\n"
    assert (project / "docs/spec/example.md").exists()
    view = json.loads(run(ds, "status", a_plan, "--json"))
    assert view["status"] == "merged" and "cleanup" in view["workflow"]["actions"][0]["action"]
    scratch.unlink()
    run(ds, "finish", relative, cwd=Path(a["tree"]))
    assert not Path(a["tree"]).exists() and not a_data.exists()
    assert a_plan.exists()
    merged = json.loads(run(ds, "task", "resume", "one", "--json"))
    assert merged["status"] == "merged" and not merged["workflow"]["actions"]
    assert json.loads(run(ds, "task", "resume", "two", "--json"))["status"] == "passed"
    out = run(ds, "finish", b_plan, ok=False)
    assert "merge-refused" in out and "round start" in out
    assert (Path(b["tree"]) / "tracked").read_text() == "two\n"
    assert (project / "tracked").read_text() == "one\n"
    assert run("git", "status", "--short") == ""

    # run#worktree-setup, run#task-worktree: no command is required and a pending merge request retains its tree.
    config = project / ".ds/config.toml"
    before = config.read_text()
    adjusted = re.sub(r"(?ms)^\[setup\]\n.*?(?=^\[|\Z)", "", before)
    config.write_text(adjusted.replace('how = "ff-only"', 'how = "merge-request"').replace(json.dumps(full), '"true"'))
    c = json.loads(run(ds, "task", "start", "request", "--json"))
    config.write_text(before)
    assert "setup" not in tomllib.loads(Path(c["plan"]).with_suffix(".run.toml").read_text())
    c_plan = make_plan(c, spec=False)
    run(ds, "build", "start", c_plan)
    run(ds, "phase", "start", c_plan, "1")
    accepted(c, c_plan, merge_request=True)
    run("git", "remote", "add", "origin", "https://forge.example/fixture/project.git")
    out = run(ds, "finish", c_plan)
    assert "nothing was pushed" in out and Path(c["tree"]).is_dir()
    link = "https://forge.example/fixture/project/requests/1"
    run(ds, "plan", "status", c_plan, link)
    assert "once it is merged" in run(ds, "finish", c_plan) and Path(c["tree"]).is_dir()
    run(ds, "finish", c_plan, "--merged")
    assert not Path(c["tree"]).exists() and c_plan.exists()
    assert (project / "tracked").read_text() == "one\n"
    rows = json.loads(run(ds, "status", "--json"))
    assert {row["plan"]: row["status"] for row in rows} == {"one": "merged", "two": "passed", "request": "merged"}
PY
