#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SOURCE="$repo_root"
python3 -B <<'PY'
import json
import os
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

    run(source / "scripts/install-ds")
    release = run("ds", "--version").strip()
    guide = run("ds", "help", "agents")
    bundle = home / ".local/lib/dev-skills/releases" / release

    def reference(name, help_text=guide):
        path = Path(next((line.strip().partition(": ")[2] for line in help_text.splitlines()
                          if line.strip().startswith(name + ": ")), ""))
        assert path.is_file() and path.is_relative_to(bundle), (
            f"distribution#system-cli: {name} is missing from installed agent help"
        )
        return path.read_text()

    for stage in ("grill", "prototype", "run-file", "plan", "build", "review", "verify",
                  "judge", "land", "finish", "retro", "bug", "spec", "tdd"):
        assert reference(stage).strip()
    for name in ("Session and dispatch rules", "Workflow paths", "Human review", "implementer", "reviewer"):
        assert reference(name).strip()

    entry = source / "ds-cli-skill"
    assert [p.name for p in entry.iterdir()] == ["SKILL.md"]
    assert (bundle / "ds-cli-skill/SKILL.md").read_bytes() == (entry / "SKILL.md").read_bytes()
    assert "ds help agents" in (entry / "SKILL.md").read_text()
    assert not (home / ".agents/skills").exists() and not (home / ".claude/skills").exists()

    # A local Git remote exercises the piped installer without contacting GitHub.
    upstream = home / "upstream"
    shutil.copytree(bundle, upstream)
    run("git", "init", "-qb", "main", cwd=upstream)
    run("git", "add", ".", cwd=upstream)
    run("git", "commit", "-qm", "fixture release", cwd=upstream)
    prefix = home / "custom prefix"
    bootstrap_env = dict(env, GIT_CONFIG_COUNT="1",
                         GIT_CONFIG_KEY_0=f"url.{upstream.as_uri()}.insteadOf",
                         GIT_CONFIG_VALUE_0="https://github.com/bmox0/dev-skills.git")
    with (source / "install.sh").open() as script:
        subprocess.run(["bash", "-s", "--", "--prefix", str(prefix)], stdin=script,
                       cwd=home, env=bootstrap_env, check=True, timeout=30)
    assert run(prefix / "bin/ds", "--version").strip() == release

    codex, claude = home / "Codex checkout", home / "Claude clone"
    codex.mkdir()
    run("git", "init", "-qb", "main", cwd=codex)
    (codex / "hello.txt").write_text("before\n")
    run("ds", "init", "--non-interactive", "--provider", "GPT", "--primary-model", "codex-primary",
        "--secondary-model", "codex-secondary", "--phase-check", "git diff --check",
        "--full-check", "test -s hello.txt", cwd=codex)
    config = codex / ".ds/config.toml"
    initial = config.read_text()
    config.write_text(initial + '\n[graph]\nfinish_without_acceptance = true\n')
    run("git", "add", ".", cwd=codex)
    run("git", "commit", "-qm", "initial project", cwd=codex)
    assert "[graph]" in run("ds", "task", "start", "forged", cwd=codex, ok=False)
    assert json.loads(run("ds", "status", "--json", cwd=codex)) == []
    config.write_text(initial)
    run("git", "commit", "-qam", "use release graph", cwd=codex)

    def lifecycle(project, provider, recorded_grill, prototype):
        run("git", "config", "core.hooksPath", "/dev/null", cwd=project)
        before = (project / "hello.txt").read_text()
        assert release in run("ds", "help", "agents", cwd=project)
        entry = json.loads(run("ds", "workflow", "--json", cwd=project))
        assert entry["actions"][0]["assignment"]["kind"] == "task-entry"
        slug = provider.lower() + "-message"
        task = json.loads(run("ds", "task", "start", slug, "--json", cwd=project))
        plan, tree = map(Path, (task["plan"], task["tree"]))
        assert task["tree"] in run("ds", "task", "resume", slug, cwd=project)
        assert task["release"] == release
        assert reference("plan", run("ds", "help", "agents", "--plan", plan))
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
Skills: `dev-skills:tdd`
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
            return json.loads(run("ds", "status", "--json", "--provider", provider, plan))["workflow"]

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

        run("ds", "spec", "check", plan)
        run("ds", "approve", plan)
        seen = {step["id"]: step["state"] for step in status()["stages"]}
        assert seen["grill"] == recorded_grill and seen["prototype"] == ("done" if prototype else "skipped")
        assert "run-unapproved" in run("ds", "build", "start", plan, ok=False)
        run("ds", "run", "approve", plan, "--by", "user", "--words", "Fixture run approved")
        summary = plan.with_suffix(".summary.md")
        summary.write_text(f"Review [the plan]({plan.name}) and its checks. No live host runs.\n")
        run("ds", "summary", "approve", plan, "--file", summary, "--by", "user",
            "--words", "Fixture summary approved")
        assert actions()[0]["waiting_for"] == "start-instruction"
        run("ds", "build", "start", plan)  # Separate fixture start instruction.
        advertised("phase", "start")
        implementer, fields = brief("implementer", "secondary")
        assert str(bundle / "skills/tdd/SKILL.md") in fields["Skills to read first"]
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
        assert run("ds", "page", plan, "--guide", human) == human
        assert run("ds", "page", plan, "--show") == human
        assert actions()[0]["input"] == "acceptance"
        assert "current authorized" in run("ds", "finish", plan, ok=False)
        assert (project / "hello.txt").read_text() == before
        run("ds", "accept", plan, "--by", "user", "--words", "Fixture result accepted")
        advertised("finish")  # Fixture authorization to integrate.
        assert (project / "hello.txt").read_text() == f"hello {provider}\n"
        assert not tree.exists() and status()["actions"] == []

    lifecycle(codex, "GPT", "done", True)
    run("git", "clone", "-q", codex, claude)
    run("ds", "init", "--non-interactive", "--provider", "Claude", "--primary-model", "claude-primary",
        "--secondary-model", "claude-secondary", cwd=claude)
    assert json.loads(run("ds", "status", "--json", cwd=claude)) == []
    clone_config = tomllib.loads((claude / ".ds/config.toml").read_text())
    assert set(clone_config["executors"]) == {"GPT", "Claude"}
    assert clone_config["checks"] == tomllib.loads(initial)["checks"]
    run("git", "commit", "-qam", "add the Claude pair", cwd=claude)
    lifecycle(claude, "Claude", "skipped", False)
PY
