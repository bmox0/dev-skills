#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SOURCE="$repo_root"
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
    for path in (bundle / "workflow").glob("*/GUIDE.md"):
        body = run("runweld", path.parent.name)
        assert path.read_text().split("---", 2)[-1].strip().splitlines()[0] in body
    for role in ("judge", "reviewer", "implementer"):
        assert (bundle / "agents" / (role + ".md")).read_text().split("---", 2)[-1].strip().splitlines()[0] in run("runweld", role)
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
    updated = tomllib.loads(lock.read_text())
    original = tomllib.loads(before.decode())
    assert updated['release'] == latest
    assert updated['guides']['grill'] != original['guides']['grill']
    grill, previous = updated['stages']['grill'], original['stages']['grill']
    assert grill['digest'] != previous['digest']
    assert [path for path in grill['inputs'] if grill['inputs'][path] != previous['inputs'][path]] == ['workflow/grill/references/INTERVIEW.md']
    assert all(updated['stages'][key] == stage for key, stage in original['stages'].items() if key != 'grill')
    assert updated['roles'] == original['roles']
    assert 'workflow/browser-test/tab.mjs' in updated['stages']['build-verification']['when']['web-or-electron']['inputs']
    shared_path = 'references/SESSIONS.md'
    with (upstream / shared_path).open('a') as f:
        f.write('\nShared protocol fixture\n')
    run("git", "commit", "-qam", "change session protocol", cwd=upstream)
    subprocess.run([cli, "update", "--cli"], cwd=locked, env=bootstrap_env, check=True, timeout=30)
    run(cli, "update", "--project", cwd=locked)
    shared = tomllib.loads(lock.read_text())
    for key, stage in updated['stages'].items():
        changed = shared['stages'][key]
        assert stage['digest'] != changed['digest']
        assert [p for p in stage['inputs'] if stage['inputs'][p] != changed['inputs'][p]] == [shared_path]
    nested = locked / "src"
    nested.mkdir()
    run(cli, "update", "--project", release, cwd=nested)
    assert not (nested / ".runweld").exists()
    assert lock.read_bytes() == before
    foreign = prefix / "bin/runweld"
    foreign.write_text("another launcher\n")
    assert "not a managed Runweld launcher" in run(source / "scripts/install-runweld", "--prefix", prefix, ok=False)
    assert foreign.read_text() == "another launcher\n"

    codex, claude = home / "Codex checkout", home / "Claude clone"
    codex.mkdir()
    run("git", "init", "-qb", "main", cwd=codex)
    (codex / "hello.txt").write_text("before\n")
    run("runweld", "init", "--non-interactive", "--provider", "GPT", "--primary-model", "codex-primary",
        "--secondary-model", "codex-secondary", "--phase-check", "git diff --check",
        "--full-check", "test -s hello.txt", cwd=codex)
    config = codex / ".runweld/config.toml"
    initial = config.read_text()
    config.write_text(initial + '\n[graph]\nfinish_without_acceptance = true\n')
    run("git", "add", ".", cwd=codex)
    run("git", "commit", "-qm", "initial project", cwd=codex)
    assert "[graph]" in run("runweld", "task", "start", "forged", cwd=codex, ok=False)
    assert json.loads(run("runweld", "status", "--json", cwd=codex)) == []
    config.write_text(initial)
    run("git", "commit", "-qam", "use release graph", cwd=codex)

    def lifecycle(project, provider, recorded_grill, prototype):
        run("git", "config", "core.hooksPath", "/dev/null", cwd=project)
        before = (project / "hello.txt").read_text()
        assert release in run("runweld", "help", "agents", cwd=project)
        entry = json.loads(run("runweld", "workflow", "--json", cwd=project))
        definition = json.loads(run("runweld", "workflow", "--stage", "build-verification", "--json", cwd=project))
        assert definition["when"]["web-or-electron"]["role"] == "verify"
        assert definition["when"] == updated["stages"]["build-verification"]["when"]
        assert entry["actions"][0]["assignment"]["kind"] == "task-entry"
        slug = provider.lower() + "-message"
        task = json.loads(run("runweld", "task", "start", slug, "--finish-how", "ff-only", "--finish-target", "main", "--json", cwd=project))
        plan, tree = map(Path, (task["plan"], task["tree"]))
        assert task["tree"] in run("runweld", "task", "resume", slug, cwd=project)
        assert task["release"] == release
        assert "# Plan" in run("runweld", "plan", "--plan", plan)
        if prototype:
            prototype = Path(task["artifacts"]) / "preview.txt"
            prototype.write_text(f"hello {provider}\n")
        plan.write_text(f"""# Plan: Hello {provider}

Status: draft · branch `{task["branch"]}` · base `{task["base"]}`
Grill: {recorded_grill}
Prototype: {prototype or "none"}

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

1. Read the greeting → hello {provider}
2. Open hello.txt and read it → the intended wording — you check

## Spec

none
""")

        def status():
            return json.loads(run("runweld", "status", "--json", "--provider", provider, plan))["workflow"]

        def actions():
            return status()["actions"]

        def advertised(*command, role=None):
            step, = (x for x in actions() if x["kind"] == "run"
                     and x["argv"][4:4 + len(command)] == list(command) and x.get("role") == role)
            assert step["argv"][2:4] == ["--release", release]
            assert str(plan) in step["argv"]
            return run(*step["argv"]).strip()

        def brief(role, tier):
            body = Path(advertised("brief", role, role=role)).read_text()
            fields = dict(line.split(": ", 1) for line in body.splitlines() if ": " in line)
            model = ("codex" if provider == "GPT" else "claude") + "-" + tier
            assert fields["Executor model"] == model and fields["Executor tier"] == tier
            assert fields["Executor provider"] == provider and fields["Run release"] == release
            for key in ("Protocol", "Role source"):
                path = Path(fields[key])
                assert path.is_relative_to(bundle) and path.read_text().strip()
            assert fields["Tree"] == str(tree)
            return body, fields

        run("runweld", "spec", "check", plan)
        run("runweld", "approve", plan)
        seen = {step["id"]: step["state"] for step in status()["stages"]}
        assert seen["grill"] == recorded_grill and seen["prototype"] == ("done" if prototype else "skipped")
        assert "run-unapproved" in run("runweld", "build", "start", plan, ok=False)
        run("runweld", "run", "approve", plan, "--by", "user", "--words", "Fixture run approved")
        summary = plan.with_suffix(".summary.md")
        summary.write_text(f"Review [the plan]({plan.name}) and its checks. No live host runs.\n")
        run("runweld", "summary", "approve", plan, "--file", summary, "--by", "user",
            "--words", "Fixture summary approved")
        assert actions()[0]["waiting_for"] == "start-instruction"
        run("runweld", "build", "start", plan)  # Separate fixture start instruction.
        advertised("phase", "start")
        implementer, fields = brief("implementer", "secondary")
        assert "runweld tdd" in fields["Skills to read first"]
        red = run("grep", "-x", f"hello {provider}", "hello.txt", cwd=tree, ok=False)
        assert not red
        (tree / "hello.txt").write_text(f"hello {provider}\n")
        assert run("grep", "-x", f"hello {provider}", "hello.txt", cwd=tree).strip() == f"hello {provider}"
        run("git", "diff", "--check", cwd=tree)
        run("git", "commit", "-qam", "write the greeting", cwd=tree)
        commit = run("git", "rev-parse", "HEAD", cwd=tree).strip()

        def command_from(body, prefix, stop=None):
            line = next(line.removeprefix(prefix) for line in body.splitlines() if line.startswith(prefix))
            return shlex.split(line.split(stop, 1)[0] if stop else line)

        report = command_from(implementer, "- Your report: ", " --became ")
        run(*report, "--became", "The greeting is printed", "--commit", commit,
            "--check", "git diff --check", "passed")
        advertised("phase", "done")
        assert "normal" in advertised("gate", "start")
        reviewer, _ = brief("reviewer", "primary")
        verify, _ = brief("verify", "secondary")
        assert str(bundle / "workflow/browser-test/tab.mjs") in verify
        run(*command_from(reviewer, "- Complete the review: "))
        assert not any(x.get("role") == "judge" and x["kind"] == "run" for x in actions())
        case = run("cat", "hello.txt", cwd=tree).strip()
        assert case == f"hello {provider}"
        result = command_from(verify, "- Each case: ", " --outcome ")
        result[result.index("<n>")] = "1"
        run(*result, "--outcome", "passed", "--capture", case)
        _, judge = brief("judge", "primary")
        assert Path(judge["Judge rules"]).is_relative_to(bundle)
        run(*shlex.split(judge["CLI"]), "verdict", "pass", plan, "--report", "Review and CLI evidence agree",
            "--predicted", "pass", "--engine", judge["Executor model"])
        shape = Path(advertised("land", "draft").removeprefix("land draft: "))
        shape.write_text(shape.read_text().replace('message = ""', 'message = "feat: greet this provider"')
                         .replace('walkthrough = ""', 'walkthrough = "Open hello.txt and see its greeting."'))
        advertised("land")
        assert actions()[0]["assignment"]["kind"] == "page"
        human = (f"Open the landed checkout at {tree}. Tell me whether to finish.\n\n"
                 f"#### What to try\n- **Done 2** Read hello.txt → hello {provider}\n\n"
                 "#### Decisions\n- —\n")
        assert run("runweld", "page", plan, "--guide", human) == human
        assert run("runweld", "page", plan, "--show") == human
        assert actions()[0]["input"] == "acceptance"
        assert "current authorized" in run("runweld", "finish", plan, ok=False)
        assert (project / "hello.txt").read_text() == before
        run("runweld", "accept", plan, "--by", "user", "--words", "Fixture result accepted")
        advertised("finish")  # Fixture authorization to integrate.
        assert (project / "hello.txt").read_text() == f"hello {provider}\n"
        assert not tree.exists() and status()["actions"] == []

    lifecycle(codex, "GPT", "done", True)
    run("git", "clone", "-q", codex, claude)
    run("runweld", "init", "--non-interactive", "--provider", "Claude", "--primary-model", "claude-primary",
        "--secondary-model", "claude-secondary", cwd=claude)
    assert json.loads(run("runweld", "status", "--json", cwd=claude)) == []
    clone_config = tomllib.loads((claude / ".runweld/config.toml").read_text())
    assert set(clone_config["executors"]) == {"GPT", "Claude"}
    assert clone_config["checks"] == tomllib.loads(initial)["checks"]
    run("git", "commit", "-qam", "add the Claude pair", cwd=claude)
    lifecycle(claude, "Claude", "skipped", False)
PY
