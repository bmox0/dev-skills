#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SOURCE="$repo_root"
export SUMMARY_FIXTURE="$repo_root/test/lib/summary.md"
python3 -B <<'PY'
import json
import os
import pty
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import tomllib

source = Path(os.environ["SOURCE"])
with tempfile.TemporaryDirectory() as folder:
    home = Path(folder).resolve()
    env = dict(os.environ, HOME=str(home), PATH=f"{home}/.local/bin:{os.environ['PATH']}",
               GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
               GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.org",
               GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.org")
    env.pop("CLAUDE_CONFIG_DIR", None)

    def run(*args, cwd=home, ok=True):
        result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, timeout=30)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        return result.stdout if ok else result.stdout + result.stderr

    run(source / "scripts/install-runweld")
    release = (home / ".local/lib/runweld/default").read_text().strip()
    guide = run("runweld", "help", "agents")
    bundle = home / ".local/lib/runweld/releases" / release

    assert "runweld grill" in guide
    assert (bundle / "workflow/grill/references/INTERVIEW.md").read_text().strip() in run("runweld", "grill")
    assert "browser-test" in run("runweld", "build-verification")

    assert "one persistent tab" in run("runweld", "browser-test", "help")
    assert not any((bundle / p).exists() for p in (".agents", ".claude-plugin", ".codex-plugin", ".qoder-plugin"))
    # A local Git remote exercises the piped installer without contacting GitHub.
    upstream = home / "upstream"
    shutil.copytree(bundle, upstream)
    run("git", "init", "-qb", "main", cwd=upstream)
    run("git", "add", ".", cwd=upstream)
    run("git", "commit", "-qm", "fixture release", cwd=upstream)
    prefix = home / "custom prefix"
    bootstrap_env = dict(env, GIT_CONFIG_COUNT="1",
                         GIT_CONFIG_KEY_0=f"url.{upstream.as_uri()}.insteadOf",
                         GIT_CONFIG_VALUE_0="https://github.com/bmox0/runweld.git")
    with (source / "install.sh").open() as script:
        subprocess.run(["bash", "-s", "--", "--prefix", str(prefix)], stdin=script,
                       cwd=home, env=bootstrap_env, check=True, timeout=30)
    assert run(prefix / "bin/runweld", "--version", "--verbose").splitlines() == [
        f"CLI version: {release.partition('@')[0]}", f"Build ID: {release}"]
    # distribution#project-lock: updating a custom prefix keeps the project's choice until explicit consent.
    cli = prefix / "bin/runweld"
    locked = home / "locked project"
    locked.mkdir()
    run("git", "init", "-qb", "main", cwd=locked)
    assert "outside a Git repository" in run(cli, "update", "--project", cwd=home, ok=False)
    assert not (home / ".runweld").exists()
    assert "runweld init" in run(cli, "update", "--project", cwd=locked, ok=False)
    assert not (locked / ".runweld").exists()
    assert (prefix / "lib/runweld/default").read_text().strip() == release
    run(cli, "init", "--non-interactive", "--provider", "Test", "--primary-model", "p", "--secondary-model", "s", cwd=locked)
    lock = locked / ".runweld/runweld.lock"
    before = lock.read_bytes()
    with (upstream / "workflow/grill/references/INTERVIEW.md").open("a") as f:
        f.write("\nGlobal update fixture\n")
    run("git", "commit", "-qam", "second build", cwd=upstream)
    subprocess.run([cli, "update", "--cli"], cwd=locked, env=bootstrap_env, check=True, timeout=30)
    latest = (prefix / "lib/runweld/default").read_text().strip()
    assert latest != release and lock.read_bytes() == before
    assert (home / ".local/lib/runweld/default").read_text().strip() == release
    bare = subprocess.run([cli, "update"], cwd=locked, env=env, stdin=subprocess.DEVNULL, capture_output=True)
    assert bare.returncode and b"--cli or --project" in bare.stderr
    assert "--project" in run(cli, "update", "--cli", "--project", cwd=locked, ok=False)
    assert "release ID" in run(cli, "update", "--cli", release, cwd=locked, ok=False)
    assert lock.read_bytes() == before
    master, slave = pty.openpty()
    try:
        for answer, ok in ((b"\n", False), (b"project\n", True)):
            os.write(master, answer)
            choice = subprocess.run([cli, "update"], cwd=locked, env=env, stdin=slave,
                                    capture_output=True, timeout=30)
            assert (choice.returncode == 0) == ok and b"cli or project" in choice.stdout
            assert (lock.read_bytes() != before) == ok
    finally:
        os.close(master)
        os.close(slave)
    def manifest_files(release_id):
        return json.loads((prefix / "lib/runweld/releases" / release_id / "release.json").read_text())["files"]

    def changed_files(old, new):
        before, after = map(manifest_files, (old, new))
        return {path for path in before.keys() | after.keys() if before.get(path) != after.get(path)}

    assert tomllib.loads(lock.read_text()) == {"lock_version": 3, "release": latest}
    assert changed_files(release, latest) == {"workflow/grill/references/INTERVIEW.md"}
    shared_path = 'references/SESSIONS.md'
    with (upstream / shared_path).open('a') as f:
        f.write('\nShared protocol fixture\n')
    run("git", "commit", "-qam", "change session protocol", cwd=upstream)
    subprocess.run([cli, "update", "--cli"], cwd=locked, env=bootstrap_env, check=True, timeout=30)
    run(cli, "update", "--project", cwd=locked)
    shared_release = (prefix / "lib/runweld/default").read_text().strip()
    assert tomllib.loads(lock.read_text()) == {"lock_version": 3, "release": shared_release}
    assert changed_files(latest, shared_release) == {shared_path}
    nested = locked / "src"
    nested.mkdir()
    run(cli, "update", "--project", release, cwd=nested)
    assert not (nested / ".runweld").exists()
    assert lock.read_bytes() == before
    run(source / "scripts/install-runweld", "--prefix", prefix)
    codex = home / "Codex checkout"
    codex.mkdir()
    run("git", "init", "-qb", "main", cwd=codex)
    (codex / "hello.txt").write_text("before\n")
    (codex / ".gitignore").write_text(".fixture-*\n")
    run("git", "add", ".", cwd=codex)
    run("git", "commit", "-qm", "initial project", cwd=codex)
    assert "runweld next" in run(cli, "help", "agents", cwd=codex)

    def inspect(cwd, *scope, compare=False):
        view = json.loads(run(cli, "next", *scope, "--json", cwd=cwd))
        if not compare:
            return view
        terminal = run(cli, "next", *scope, cwd=cwd)
        for step in view["actions"]:
            assert f"{step['owner']} — {step['action']} [{step['kind']}]" in terminal
            assignment = step.get("assignment", {})
            commands = ([step] if step["kind"] == "run" else [step["command"]] if step.get("command") else [])
            commands += step.get("alternatives", []) + assignment.get("reports", [])
            for command in commands:
                assert f"In {command['cwd']}: {shlex.join(command['argv'])}" in terminal
                if command.get("options"):
                    assert "Inputs: " + ", ".join(command["options"].values()) in terminal
            if step["kind"] == "work" and assignment.get("role_source"):
                assert assignment["role_source"] in terminal and "Return:" in terminal
        for fact in view.get("evidence", []):
            assert fact in terminal
        return view

    def follow(command, *args, ok=True):
        return run(*command["argv"], *args, cwd=command["cwd"], ok=ok).strip()

    starter, = inspect(codex, compare=True)["actions"]
    options = ("--non-interactive", "--provider", "GPT", "--primary-model", "codex-primary",
               "--secondary-model", "codex-secondary", "--phase-check", "git diff --check",
               "--full-check", "test -s hello.txt", "--bootstrap", "printf ready > .fixture-setup",
               "--data-dir", "--dev-url", "http://localhost:4000")
    follow(starter, *options)
    config = codex / ".runweld/config.toml"
    initial = config.read_text()
    settings = tomllib.loads(initial)
    assert settings["setup"]["command"] == "printf ready > .fixture-setup"
    assert settings["checks"] == {"phase": ["git diff --check"], "full": ["test -s hello.txt"],
                                 "url": "http://localhost:4000"}
    run("git", "add", ".", cwd=codex)
    run("git", "commit", "-qm", "shared settings", cwd=codex)
    follow(starter, *options)
    assert not run("git", "status", "--porcelain", cwd=codex)
    config.write_text(initial + '\n[graph]\nfinish_without_acceptance = true\n')
    run("git", "add", ".", cwd=codex)
    run("git", "commit", "-qm", "initial project", cwd=codex)
    assert "[graph]" in run(cli, "task", "start", "forged", cwd=codex, ok=False)
    assert json.loads(run(cli, "status", "--json", cwd=codex)) == []
    config.write_text(initial)
    run("git", "commit", "-qam", "use release graph", cwd=codex)

    def lifecycle(project, provider, release):
        bundle = prefix / "lib/runweld/releases" / release
        run("git", "config", "core.hooksPath", "/dev/null", cwd=project)
        before = (project / "hello.txt").read_text()
        assert release in run(cli, "help", "agents", cwd=project)
        entry = json.loads(run(cli, "workflow", "--json", cwd=project))
        definition = json.loads(run(cli, "workflow", "--stage", "build-verification", "--json", cwd=project))
        assert definition["when"]["web-or-electron"]["role"] == "verify"
        assert "workflow/browser-test/tab.mjs" in definition["when"]["web-or-electron"]["inputs"]
        assert entry["actions"][0]["assignment"]["kind"] == "task-entry"
        slug = provider.lower() + "-message"
        task = json.loads(run(cli, "task", "start", slug, "--provider", provider, "--goal", f"Print a {provider} greeting.",
                              "--finish-how", "ff-only", "--finish-target", "main", "--json", cwd=project))
        plan, tree = map(Path, (task["plan"], task["tree"]))
        assert task["release"] == release
        artifacts = Path(task["artifacts"])
        assert artifacts.parent == plan.parent and plan.parent.name.endswith("-" + slug)

        def view(*, compare=False):
            return inspect(tree, compare=compare)

        def actions():
            return view()["actions"]

        def advertised(*command, role=None, extra=(), ok=True):
            step, = (x for x in actions() if x["kind"] == "run"
                     and x["argv"][4:4 + len(command)] == list(command) and x.get("role") == role)
            assert step["argv"][1:4] == [str(cli), "--release", release]
            assert str(plan) in step["argv"]
            return follow(step, *extra, ok=ok)

        def requested(input_, steps=None):
            step, = (x for x in (actions() if steps is None else steps) if x.get("input") == input_)
            assert step["kind"] == "ask" and step["owner"] == "Human"
            return step

        initial_view = view()
        assert initial_view == inspect(project, slug)
        assert initial_view["task"]["goal"] == f"Print a {provider} greeting."
        advertised("grill", "start")
        advertised("grill", "save", extra=("--result", "One greeting line", "--question", "Which punctuation?"))
        assert view()["task"]["discovery"]["grill"]["result"] == "One greeting line"
        assert requested("discovery-questions")["questions"] == ["Which punctuation?"]
        advertised("grill", "done", extra=("--result", "No punctuation"))
        advertised("prototype", "start")
        preview = artifacts / "preview.txt"
        preview.write_text(f"hello {provider}\n")
        advertised("prototype", "done", extra=("--result", "Use the plain greeting", "--artifact", preview))
        instruction, = actions()[0]["assignment"]["instructions"]
        assert "# Plan" in run(*instruction, cwd=tree)
        plan.write_text(f"""# Plan: Hello {provider}

Status: draft · branch `{task["branch"]}` · base `{task["base"]}`

## Result

Print a provider-specific greeting.

## Approach

Update the message in hello.txt.

## Out of scope

- Executing a real host.

## Phases

### 1. Write the greeting — `waiting`
Territory: `hello.txt`
Skills: `runweld tdd`
Spec: none
Waits for: nothing

## Checks

- Gate: normal — independent review and CLI evidence.

## Done

1. Read the greeting → a single greeting for {provider}
2. Open hello.txt and read it → the intended wording — you check

## Spec

none
""")

        def assignment_for(role, steps=None):
            assignment, = (x["assignment"] for x in (actions() if steps is None else steps) if x["kind"] == "work" and x.get("role") == role)
            return assignment

        def report(role, command, *extra):
            record, = (entry for entry in assignment_for(role)["reports"]
                       if entry["argv"][4:4 + len(command)] == list(command))
            return follow(record, *extra)

        def brief(role, tier, command=None):
            path = Path(advertised("brief", command or role, role=role))
            body = path.read_text()
            fields = dict(line.split(": ", 1) for line in body.splitlines() if ": " in line)
            model = "codex-" + tier
            assert fields["Executor model"] == model and fields["Executor tier"] == tier
            assert fields["Executor provider"] == provider and fields["Run release"] == release
            for key in ("Protocol", "Role source"):
                source_path = Path(fields[key])
                assert source_path.is_relative_to(bundle) and source_path.read_text().strip()
            assert fields["Tree"] == str(tree)
            # distribution#system-cli: an unseen coordinator can act from the installed next output.
            resumed = view(compare=role == "implementer" and command is None)
            assert resumed["task"]["goal"] == "Print a provider-specific greeting."
            assert resumed["task"]["approvals"]["plan"]["by"] == "Fixture Human"
            assignment = assignment_for(role, resumed["actions"])
            assert assignment["cwd"] == str(tree) and assignment["reports"], assignment
            assert assignment["brief"]["path"] == str(path) and assignment["brief"]["dispatch"] == "unverified"
            assert path.parent == plan.parent
            assert not any(x["kind"] == "run" and x.get("role") == role for x in resumed["actions"])
            for entry in assignment["reports"]:
                assert entry["argv"][1:4] == [str(cli), "--release", release]
            instruction, = assignment["instructions"]
            assert Path(fields["Role source"]).read_text().split("---", 2)[-1].strip().splitlines()[0] in run(*instruction, cwd=assignment["cwd"])
            wait, = (step for step in resumed["actions"] if step["kind"] == "wait"
                     and step.get("waiting_for") == f"{command or role}-report")
            assert wait["condition"] == "after-dispatch" and wait["records"] == str(plan.with_suffix(".json"))
            return body, fields

        advertised("spec", "check")
        advertised("approve")
        summary = plan.with_suffix(".summary.md")
        valid = Path(os.environ["SUMMARY_FIXTURE"]).read_text()
        for invalid in (None, "word " * 351, valid.split("## Checks")[0], valid.split("## Your approval")[0] + "## Your approval"):
            if invalid is not None:
                summary.write_text(invalid)
            repair, = actions()
            assert repair["owner"] == "Planner" and repair["kind"] == "work"
            assert str(summary) in repair["action"] and "resume.example.md" in repair["action"]
            if invalid and "## Phases" in invalid:
                assert ("empty section: Your approval" if "## Your approval" in invalid else "section 4 (Checks)") in repair["action"]
            assert "bad-summary" in run(cli, "build", "start", plan, ok=False)
        summary.write_text(valid)
        assert "plan-unapproved" in run(cli, "build", "start", plan, ok=False)
        requested("plan-approval")
        proposal = json.loads(advertised("plan", "review", extra=("--json",)))
        follow(proposal["approval_command"], "--by", "Fixture Human", "--words", "Fixture plan and run approved")
        start = requested("start-authorization")["command"]
        selection = ("--provider", provider) if "provider" in start["options"] else ()
        follow(start, *selection)  # Fixture human authorizes a separate build start.
        assert "Next:" in advertised("phase", "start")
        # run#changes-through-approve: recompiling an edited active plan does not authorize its new scope.
        original = plan.read_text()
        plan.write_text(original.replace("Territory: `hello.txt`", "Territory: `hello.txt`, `.gitignore`"))
        run(cli, "approve", plan, cwd=tree)
        assert "plan-stale" in run(cli, "brief", "implementer", plan, "1", "--provider", provider, cwd=tree, ok=False)
        assert not list(plan.parent.glob("*.brief-implementer-*.md"))
        assert view()["stage"] == "plan"
        proposal = json.loads(advertised("plan", "review", extra=("--json",)))
        assert ".gitignore" in proposal["plan"]
        assert requested("plan-approval")
        follow(proposal["approval_command"], "--by", "Fixture Human", "--words", "Approve the revised phase territory")
        # distribution#system-cli: Herdr targets must be live and in the assigned checkout.
        fixture = home / ".local/bin/herdr"
        fixture.write_text('#!/bin/sh\n[ "$*" = "api snapshot" ] && cat "$HERDR_FIXTURE"\n')
        fixture.chmod(0o755)
        snapshot = home / "herdr-snapshot.json"
        payload = {"workspaces": [{"workspace_id": "w1"}, {"workspace_id": "w2"}],
                   "panes": [{"pane_id": "w1:p1", "workspace_id": "w1", "cwd": str(tree),
                              "agent": None}], "agents": []}
        snapshot.write_text(json.dumps({"result": {"snapshot": payload}}))
        env["HERDR_ENV"] = "1"
        env["HERDR_FIXTURE"] = str(snapshot)
        target = (cli, "handoff", "herdr", plan, "--pane", "w1:p1")
        assert "handoff: Herdr" in run(*target, "--workspace", "w1")
        assert "herdr-target" in run(*target, "--workspace", "w2", ok=False)
        payload["panes"].clear()
        snapshot.write_text(json.dumps({"result": {"snapshot": payload}}))
        assert "herdr-target" in run(*target, "--workspace", "w1", ok=False)
        env.pop("HERDR_FIXTURE")
        fixture.unlink()
        _, fields = brief("implementer", "secondary")
        assert "runweld tdd" in fields["Skills to read first"]
        red = run("grep", "-x", f"hello {provider}", "hello.txt", cwd=tree, ok=False)
        assert not red
        greeting = f"hello {provider}\n"
        (tree / "hello.txt").write_text(greeting + "extra line\n")
        assert run("grep", "-x", f"hello {provider}", "hello.txt", cwd=tree).strip() == f"hello {provider}"
        run("git", "diff", "--check", cwd=tree)
        run("git", "commit", "-qam", "write the greeting", cwd=tree)
        commit = run("git", "rev-parse", "HEAD", cwd=tree).strip()

        report("implementer", ("phase", "report"), "--became", "The greeting is printed", "--commit", commit,
               "--check", "git diff --check", "passed")
        advertised("phase", "done")
        assert "normal" in advertised("gate", "start")
        brief("reviewer", "primary")
        verify, _ = brief("verify", "secondary")
        assert str(bundle / "workflow/browser-test/tab.mjs") in verify
        finding, = (entry for entry in assignment_for("reviewer")["reports"] if entry["argv"][4] == "finding")
        values = {"kind": "defect", "where": "hello.txt:2", "source": "Done 1",
                  "text": "Greeting contains an extra line"}
        inputs = [arg for key, value in values.items() if key in finding["options"]
                  for arg in (finding["options"][key].split()[0], value)]
        assert "D1 recorded" in follow(finding, *inputs)
        capture = artifacts / "initial.txt"
        capture.write_text((tree / "hello.txt").read_text())
        assert capture.read_text().splitlines() == [greeting.strip(), "extra line"]
        report("verify", ("result",), "--case", "1", "--outcome", "failed",
               "--capture", capture, "--detail", "Captured the whole file")
        assert not any(x.get("role") == "judge" for x in actions())
        report("reviewer", ("review", "complete"))
        # distribution#system-cli: resume a release A repair after the project has selected release B.
        run(cli, "update", "--project", shared_release, cwd=project)
        assert shared_release in run(cli, "help", "agents", cwd=project)
        assert any("Greeting contains an extra line" in fact for fact in view(compare=True)["evidence"])
        another = json.loads(run(cli, "task", "start", "release-b-check", "--provider", provider,
                                 "--goal", "Use the new release", "--json", cwd=project))
        scope = inspect(project)
        assert {task["id"]: task["release"] for task in scope["tasks"]} == {slug: release, "release-b-check": shared_release}
        resume, = (step for step in scope["actions"] if step.get("argv", [])[-2:] == ["next", slug])
        assert json.loads(follow(resume, "--json")) == view()
        second = inspect(another["tree"])
        new_grill = second["actions"][0]["assignment"]["instructions"][0]
        assert new_grill[1:4] == [str(cli), "--release", shared_release]
        assert "Global update fixture" in run(*new_grill, cwd=another["tree"])
        assert "Next:" in advertised("fix", "start")
        brief("implementer", "secondary", "fix")
        (tree / "hello.txt").write_text(greeting)
        run("git", "commit", "-qam", "remove the extra line", cwd=tree)
        fixed = run("git", "rev-parse", "HEAD", cwd=tree).strip()
        report("implementer", ("fix", "report"), "--became", "Only the greeting remains", "--commit", fixed)
        assert "Next:" in advertised("fix", "done")
        brief("reviewer", "secondary")
        brief("verify", "secondary")
        assert assignment_for("reviewer")["range"].endswith(f"{commit}..{fixed}")
        report("reviewer", ("review", "complete"))
        capture = artifacts / "fixed.txt"
        capture.write_text((tree / "hello.txt").read_text())
        assert capture.read_text().splitlines() == [greeting.strip()]
        report("verify", ("result",), "--case", "1", "--outcome", "passed", "--capture", capture)
        # distribution#system-cli, build#judge-reads-the-round: feedback can precede the first verdict.
        feedback_before_verdict = "Capitalize the greeting."
        run(cli, "note", "add", plan, "--text", feedback_before_verdict, "--cause", "feel-ui", cwd=tree)
        run(cli, "round", "start", plan, cwd=tree)  # Fixture human authorizes the round.
        brief("implementer", "secondary", "round")
        greeting = greeting.capitalize()
        (tree / "hello.txt").write_text(greeting)
        run("git", "commit", "-qam", "capitalize the greeting", cwd=tree)
        revision = run("git", "rev-parse", "HEAD", cwd=tree).strip()
        report("implementer", ("round", "report"), "--became", feedback_before_verdict, "--commit", revision)
        source_command, = actions()[0]["alternatives"]
        follow(source_command, "--source", "missed")
        advertised("round", "done")
        brief("reviewer", "secondary")
        report("reviewer", ("review", "complete"))
        round_capture = artifacts / "first-round.txt"
        round_capture.write_text(run("cat", "hello.txt", cwd=tree))
        assert round_capture.read_text() == greeting
        run(cli, "result", plan, "--cycle", "round-1", "--head", revision, "--case", "1", "--outcome",
            "passed", "--capture", round_capture, cwd=tree)
        assert not view(compare=True)["task"]["verdicts"]
        judge_file = plan.with_suffix(".judge.md")
        assert not judge_file.exists()
        body, judge = brief("judge", "primary")
        for evidence in ("First substantive verdict", "## Original gate evidence", "## Round 1 evidence (current)",
                         str(capture), str(round_capture), feedback_before_verdict, f"checks at {fixed[:7]}",
                         f"checks at {revision[:7]}", "You check: 2", "--predicted pass|round", "--engine NAME"):
            assert evidence in body, body
        assert "Judge file:" not in body and not judge_file.exists()
        assert Path(judge["Judge rules"]).is_relative_to(bundle)
        prediction = ("--predicted", "pass", "--engine", judge["Executor model"])
        report("judge", ("verdict", "question"), "--report", "Need the human's decision",
               "--question", "Keep this wording?", *prediction)
        steps = view(compare=True)["actions"]
        assert "Keep this wording?" in requested("judge-answer", steps)["action"]
        wait, = (step for step in steps if step.get("waiting_for") == "judge-answer")
        assert wait["kind"] == "wait" and not wait.get("condition")
        relay = Path(follow(wait["command"], "--note", "Keep it."))
        assert "The human's answer: Keep it." in relay.read_text()
        prediction = ()
        assert "Next:" in report("judge", ("verdict", "pass"), "--report", "Review and CLI evidence agree", *prediction)

        def land_and_show(greeting):
            step, = actions()
            if step.get("assignment", {}).get("shape"):
                shape = Path(step["assignment"]["shape"])
                shape.write_text('since = "Add the requested punctuation"\n' + shape.read_text())
            else:
                shape = Path(advertised("land", "draft").removeprefix("land draft: "))
                shape.write_text(shape.read_text().replace('message = ""', 'message = "feat: greet this provider"')
                                 .replace('walkthrough = ""', 'walkthrough = "Open hello.txt and see its greeting."'))
            advertised("land")
            page, = (step for step in actions() if step.get("assignment", {}).get("kind") == "page")
            human = (f"Open the landed checkout at {tree}. Tell me whether to finish.\n\n"
                     f"#### What to try\n- **Done 2** Read hello.txt → {greeting.strip()}\n\n"
                     "#### Decisions\n- —\n")
            assert follow(page["command"], "--guide", human) == human.strip()
            opening, _ = requested("acceptance")["alternatives"]
            assert follow(opening) == human.strip()

        land_and_show(greeting)
        assert "current authorized" in run(cli, "finish", plan, ok=False)
        assert (project / "hello.txt").read_text() == before
        _, notes = requested("acceptance")["alternatives"]
        feedback = "Add an exclamation point to the greeting."
        follow(notes, "--text", feedback, "--cause", "feel-ui")
        steps = view(compare=True)["actions"]
        authorization = requested("round-authorization", steps)
        assert any(feedback in note for note in authorization["evidence"])
        assert not any(step["kind"] == "run" for step in steps)
        follow(authorization["command"])  # Fixture human authorizes the round.
        body, _ = brief("implementer", "secondary", "round")
        assert feedback in body
        greeting = greeting.strip() + "!\n"
        (tree / "hello.txt").write_text(greeting)
        run("git", "commit", "-qam", "add the requested punctuation", cwd=tree)
        revision = run("git", "rev-parse", "HEAD", cwd=tree).strip()
        report("implementer", ("round", "report"), "--became", feedback, "--commit", revision)
        sources, = actions()
        source_command, = sources["alternatives"]
        follow(source_command, "--source", "missed")
        advertised("round", "done")
        brief("reviewer", "secondary")
        assert assignment_for("reviewer")["range"].endswith(".." + revision)
        report("reviewer", ("review", "complete"))
        body, _ = brief("judge", "primary")
        assert str(judge_file) in body and str(capture) not in body and str(round_capture) not in body
        report("judge", ("verdict", "pass"), "--report", "The feedback round was reviewed")
        land_and_show(greeting)
        # Keep the ff-only target clean without an unrelated release-lock commit on it.
        run(cli, "update", "--project", release, cwd=project)

        follow(requested("acceptance")["command"], "--words", "Fixture result accepted")
        accepted = run("git", "rev-parse", "HEAD", cwd=tree).strip()
        unknown = tree / ".fixture-unknown"
        unknown.write_text("keep this")
        pending = json.loads(advertised("finish", extra=("--json",)))
        assert pending["cleanup_pending"] and unknown.name in pending["cleanup_pending"]
        assert pending["integration"]["commit"] == accepted and pending["integration"]["verified"]
        assert unknown.read_text() == "keep this" and not (tree / ".fixture-setup").exists()
        assert run("git", "rev-parse", "main", cwd=project).strip() == accepted
        retry, = pending["actions"]
        assert retry["cwd"] == str(project)
        assert inspect(project, slug)["actions"] == pending["actions"]
        unknown.unlink()
        assert f"main contains integration commit {accepted}" in follow(retry)
        assert (project / "hello.txt").read_text() == greeting
        assert run("git", "rev-parse", "main", cwd=project).strip() == accepted
        assert not run("git", "status", "--porcelain", cwd=project)
        terminal = inspect(project, slug, compare=True)
        assert terminal["task"]["status"] == "merged" and terminal["actions"] == [] and not tree.exists()
        assert terminal["task"]["integration"]["commit"] == accepted
        assert terminal["task"]["acceptance"]["words"] == "Fixture result accepted"
        assert {p.name for p in plan.parent.iterdir()} >= {
            plan.name, slug + ".json", slug + ".run.toml", slug + ".judge.md", "artifacts"}
        assert (artifacts / "initial.txt").is_file() and not (artifacts / "data").exists()

    lifecycle(codex, "GPT", release)

    cli.write_text("another launcher\n")
    assert "not a managed Runweld launcher" in run(source / "scripts/install-runweld", "--prefix", prefix, ok=False)
    assert cli.read_text() == "another launcher\n"
PY
