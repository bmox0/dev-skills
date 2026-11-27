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

with tempfile.TemporaryDirectory() as folder:
    root = Path(folder).resolve()
    prefix = root / "local"
    project = root / "project with spaces"
    project.mkdir()
    home = root / "home"
    home.mkdir()
    global_config = home / "preferences/runweld/config.toml"
    global_config.parent.mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(global_config.parent.parent),
               GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.org",
               GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.org")

    def command(*args, cwd=project, ok=True, with_env=env):
        result = subprocess.run(args, cwd=cwd, env=with_env, text=True, capture_output=True,
                                stdin=subprocess.DEVNULL, timeout=30)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        return (result.stdout + result.stderr).strip()

    def git(*args, **kwargs):
        return command("git", *args, **kwargs)

    def cli(*args, **kwargs):
        return command(prefix / "bin/runweld", *args, **kwargs)

    def read(file):
        return tomllib.loads(file.read_text())

    command(os.environ["INSTALLER"], "--prefix", prefix, cwd=root)
    git("init", "-qb", "main")
    entry = json.loads(cli("next", "--json"))
    action = entry["actions"][0]
    assert action["kind"] == "run" and action["owner"] != "Human" and action["argv"][-2:] == ["onboard", "--json"], (
        "distribution#system-cli: next offers the agent a machine-readable onboarding preview")
    preview = json.loads(command(*action["argv"], cwd=action["cwd"]))
    assert not preview["complete"] and set(preview["pending"]) == {"primary", "secondary", "setup"}, (
        "run#contract-checked: empty project preview identifies both roles and bootstrap uncertainty")
    assert set(preview["executors"]) == {"primary", "secondary"}
    assert "confirm both roles" in cli("next"), "distribution#system-cli: next names the first checkout decision"
    assert sorted(p.name for p in project.iterdir()) == [".git"]
    assert not (project / ".git/runweld-onboard.lock").exists()

    # distribution#local-workflow and run#contract-checked: apply both chat answers and preserve shared edits.
    first_role = {"provider": "GPT", "model": "gpt main", "effort": "high"}
    second_role = {"provider": "Claude", "model": "claude helper"}
    operands = ("--primary-provider", "GPT", "--primary-model", "gpt main", "--primary-effort", "high",
                "--secondary-provider", "Claude", "--secondary-model", "claude helper", "--no-setup")
    agents = project / "AGENTS.md"
    ignore = project / ".gitignore"
    config = project / ".runweld/config.toml"
    lock = project / "runweld.lock"
    agents.write_bytes(b"# Team instructions\r\n\r\nKeep this after preview.")
    ignore.write_bytes(b"notes\r\n")
    saved = json.loads(cli("onboard", "--apply", "--json", *operands))
    assert saved["complete"] and not saved["pending"]
    assert saved["paths"] == {".gitignore": "updated", "AGENTS.md": "updated",
                              "runweld.lock": "created", ".runweld/config.toml": "created"}
    assert read(config)["executors"] == {"primary": first_role, "secondary": second_role}
    assert agents.read_bytes().startswith(b"# Team instructions\r\n\r\nKeep this after preview.")
    assert ignore.read_bytes() == b"notes\r\n/.runweld/\r\n"
    build_id = (prefix / "lib/runweld/default").read_text().strip()
    assert read(lock)["release"] == build_id and "guides" in read(lock)
    assert build_id in cli("--version", "--verbose")
    git("check-ignore", ".runweld/config.toml", ".runweld/workflow/plans/demo.md")
    git("check-ignore", "runweld.lock", "AGENTS.md", ok=False)
    managed = {path: path.read_bytes() for path in (config, lock, agents, ignore)}
    again = json.loads(cli("onboard", "--apply", "--json"))
    assert again["complete"] and set(again["paths"].values()) == {"unchanged"}
    assert all(path.read_bytes() == data for path, data in managed.items())
    assert "initial Git commit" in cli("next")
    assert "primary.model" in cli("onboard", "--apply", "--primary-model", " ", ok=False)
    assert all(path.read_bytes() == data for path, data in managed.items())

    # distribution#local-workflow and run#executor-presets: defaults never confirm roles in a fresh clone.
    git("add", ".")
    git("commit", "-qm", "share Runweld entry and pin")
    assert set(git("ls-files").splitlines()) == {"AGENTS.md", ".gitignore", "runweld.lock"}
    # run#executor-presets: a mixed pair accepts a task-local field override at entry.
    result = subprocess.run([prefix / "bin/runweld", "task", "start", "mixed",
                             "--secondary-model", "opaque / model with spaces", "--json"],
                            cwd=project, env=env, stdin=subprocess.DEVNULL, text=True, capture_output=True)
    assert result.returncode == 0, f"run#executor-presets: installed task entry must accept mixed roles and one field override: {result.stdout}{result.stderr}"
    mixed = json.loads(result.stdout)
    mixed_plan, mixed_tree = Path(mixed["plan"]), Path(mixed["tree"])
    overridden = {**second_role, "model": "opaque / model with spaces"}
    mixed_roles = {"primary": first_role, "secondary": overridden}
    assert read(mixed_plan.with_suffix(".run.toml"))["executors"] == mixed_roles
    assert config.read_bytes() == managed[config]
    global_config.write_text("""[executors.primary]
provider = "GPT"
model = "personal primary"
effort = "xhigh"

[executors.secondary]
provider = "Claude"
model = "personal helper"
effort = "medium"
""")
    clone = root / "new teammate"
    git("clone", "-q", project, clone, cwd=root)
    clone_config = clone / ".runweld/config.toml"
    assert not clone_config.exists() and not (clone / ".runweld/workflow").exists()
    assert (clone / "runweld.lock").read_bytes() == managed[lock]
    action, = json.loads(cli("next", "--json", cwd=clone))["actions"]
    offered = json.loads(command(*action["argv"], cwd=action["cwd"]))
    assert {key for key, val in offered["pending"].items() if val} == {"primary", "secondary", "setup"}
    for role, model in (("primary", "personal primary"), ("secondary", "personal helper")):
        assert offered["executors"][role]["status"] == "offered"
        assert offered["executors"][role]["model"] == model
        assert offered["executors"][role]["source"] == str(global_config)
    assert not clone_config.exists()
    partial = json.loads(cli("onboard", "--apply", "--json", "--confirm-primary", "--no-setup", cwd=clone))
    assert not partial["complete"] and set(partial["pending"]) == {"secondary"}
    assert read(clone_config)["executors"] == {
        "primary": {"provider": "GPT", "model": "personal primary", "effort": "xhigh"}}
    next_partial = json.loads(cli("next", "--json", cwd=clone))
    assert set(next_partial["onboarding"]["pending"]) == {"secondary"}
    assert next_partial["actions"][0]["argv"][-2:] == ["onboard", "--json"]
    guidance = cli("next", cwd=clone)
    assert "Confirm the secondary executor" in guidance and "Confirm the primary executor" not in guidance, (
        "distribution#system-cli: next names only the remaining executor decision")
    assert "secondary" in cli("task", "start", "still-pending", cwd=clone, ok=False)
    global_config.write_text(global_config.read_text().replace("personal primary", "new preference"))
    finished = json.loads(cli("onboard", "--apply", "--json", "--confirm-secondary", cwd=clone))
    assert finished["complete"] and not finished["pending"]
    assert read(clone_config)["executors"] == {
        "primary": {"provider": "GPT", "model": "personal primary", "effort": "xhigh"},
        "secondary": {"provider": "Claude", "model": "personal helper", "effort": "medium"}}
    assert not git("status", "--porcelain", cwd=clone)

    teammate = root / "later teammate"
    git("clone", "-q", project, teammate, cwd=root)
    fresh = json.loads(cli("onboard", "--json", cwd=teammate))
    assert fresh["executors"]["primary"]["model"] == "new preference"
    assert fresh["executors"]["primary"]["status"] == "offered"
    assert read(mixed_plan.with_suffix(".run.toml"))["executors"] == mixed_roles

    # distribution#system-cli: loss of a shared setup entry is repaired without replacing neighboring content.
    clone_agents = clone / "AGENTS.md"
    clone_ignore = clone / ".gitignore"
    for path, edited in ((clone_agents, b"# Retain this\r\n\r\nAn adjacent edit."),
                         (clone_ignore, b"# Retain this\r\nlocal-notes\r\n")):
        path.write_bytes(edited)
        repair = json.loads(cli("next", "--json", cwd=clone))["onboarding"]
        assert repair["paths"] == [path.name] and not repair["pending"]
        assert path.name in cli("next", cwd=clone), "distribution#system-cli: next names the file to repair"
        saved = json.loads(cli("onboard", "--apply", "--json", cwd=clone))
        assert saved["complete"] and saved["paths"][path.name] == "updated"
        assert path.read_bytes().startswith(edited)
        if path == clone_agents:
            assert b"<!-- runweld:begin -->\r\n" in path.read_bytes()
        else:
            assert b"/.runweld/\r\n" in path.read_bytes()
    broken = b"# Keep\r\n<!-- runweld:begin -->\r\n"
    clone_agents.write_bytes(broken)
    assert "project-agents-block" in cli("onboard", "--apply", cwd=clone, ok=False)
    assert clone_agents.read_bytes() == broken

    # run#mandatory-checks and run#contract-checked: designated CI and project disagreement needs a chat decision.
    conflict = root / "conflicting checks"
    conflict.mkdir()
    git("init", "-qb", "main", cwd=conflict)
    (conflict / "AGENTS.md").write_text("""# Project

## Environment

**Lint.** `scripts/local-check`
**Required checks.** `scripts/local-check`
**CI workflow.** `.github/workflows/check.yml`
**Worktree setup.** `touch must-not-run`
""")
    workflow = conflict / ".github/workflows/check.yml"
    workflow.parent.mkdir(parents=True)
    workflow.write_text("jobs:\n  tests:\n    steps:\n      - run: scripts/ci-check\n")
    (conflict / "package.json").write_text('{"scripts":{"test":"touch must-not-run"}}')
    detected = json.loads(cli("onboard", "--json", cwd=conflict))
    assert detected["sources"]["required checks"] == {
        "AGENTS.md ## Environment": ["scripts/local-check"],
        ".github/workflows/check.yml": ["scripts/ci-check"]}
    assert detected["settings"]["checks"]["full"] == ["scripts/local-check", "npm run test"]
    assert detected["sources"]["tests"] == {"package.json scripts": ["npm run test"]}
    assert "required_checks" in detected["pending"]
    conflict_partial = json.loads(cli("onboard", "--apply", "--json", "--confirm-primary", "--confirm-secondary", cwd=conflict))
    assert not conflict_partial["complete"] and set(conflict_partial["pending"]) == {"required_checks"}
    decision = json.loads(cli("onboard", "--apply", "--json", "--required-check", "scripts/local-check",
                              "--required-check", "scripts/ci-check", cwd=conflict))
    assert decision["complete"] and not decision["pending"]
    checked = read(conflict / ".runweld/config.toml")
    assert checked["checks"]["required"] == ["scripts/local-check", "scripts/ci-check"]
    assert checked["onboarding"]["sources"]["confirmed required checks"] == {
        "chat": ["scripts/local-check", "scripts/ci-check"]}
    assert not (conflict / "must-not-run").exists()
    assert json.loads(cli("onboard", "--json", cwd=conflict))["complete"]

    workflow.write_text(workflow.read_text().replace("scripts/ci-check", "scripts/new-ci"))
    refreshed = json.loads(cli("next", "--json", cwd=conflict))
    assert "required_checks" in refreshed.get("onboarding", {}).get("pending", {}), (
        "run#mandatory-checks: changed CI requirements cannot silently reuse a prior decision")
    assert "required_checks" in cli("task", "start", "stale-checks", cwd=conflict, ok=False)
    # run#mandatory-checks: resolving contextual CI cannot erase a separately declared check.
    workflow.write_text("jobs:\n  tests:\n    steps:\n      - run: npm test\n        working-directory: api\n")
    git("add", ".", cwd=conflict)
    git("commit", "-qm", "declare contextual CI and local checks", cwd=conflict)
    local_config = conflict / ".runweld/config.toml"
    before = local_config.read_bytes()
    for override in (("--no-required-checks",), ("--required-check", "cd api && npm test")):
        refusal = cli("onboard", "--apply", *override, cwd=conflict, ok=False)
        assert "project-required-checks" in refusal and "scripts/local-check" in refusal
        assert local_config.read_bytes() == before
    assert "required_checks" in cli("task", "start", "missing-required", cwd=conflict, ok=False)
    cli("onboard", "--apply", "--required-check", "scripts/local-check", "--required-check", "cd api && npm test", cwd=conflict)
    task = json.loads(cli("task", "start", "bound-required", "--json", cwd=conflict))
    required = ["scripts/local-check", "cd api && npm test"]
    assert read(Path(task["plan"]).with_suffix(".run.toml"))["checks"]["required"] == required
    confirmed = local_config.read_text()
    local_config.write_text(confirmed.replace(f"required = {json.dumps(required)}", "required = []"))
    assert read(local_config)["checks"]["required"] == []
    assert "required_checks" in cli("task", "start", "unsafe-previous-answer", cwd=conflict, ok=False), (
        "run#mandatory-checks: a previously saved empty override cannot erase an unchanged declaration")
    local_config.write_text(confirmed)

    workflow.write_text(workflow.read_text() + "      - run: |\\n          scripts/another-check\\n")
    no_split = (conflict / "AGENTS.md").read_text().splitlines(keepends=True)
    (conflict / "AGENTS.md").write_text("".join(line for line in no_split if "**Required checks.**" not in line))
    complicated = json.loads(cli("onboard", "--json", cwd=conflict))
    assert "required_checks" in complicated["pending"], (
        "run#contract-checked: a designated CI workflow with shell blocks needs an explicit decision")

    # distribution#local-workflow: ordinary Git staging shares the setup, never files under .runweld.
    privacy = root / "effective ignore"
    privacy.mkdir()
    git("init", "-qb", "main", cwd=privacy)
    rules = ".*\n*.md\n*.lock\n/.runweld/\n!/.runweld/\n/.runweld/config.toml\n"
    (privacy / ".gitignore").write_text(rules)
    cli("onboard", "--apply", *operands, cwd=privacy)
    plan = privacy / ".runweld/workflow/plans/test.json"
    plan.parent.mkdir(parents=True)
    plan.write_text("{}")
    git("add", ".", cwd=privacy)
    assert set(git("ls-files", cwd=privacy).splitlines()) == {".gitignore", "AGENTS.md", "runweld.lock"}, (
        "distribution#local-workflow: effective ignore rules protect the directory and expose all shared files")
    assert (privacy / ".gitignore").read_text().startswith(rules)
    assert json.loads(cli("onboard", "--apply", "--json", cwd=privacy))["paths"][".gitignore"] == "unchanged"

    # run#mandatory-checks: do not execute a guess at the checkout root for a contextual CI command.
    for context in ("        working-directory: api\n", "        env: {CI: true}\n", "        shell: bash\n"):
        workflow.write_text("jobs:\n  tests:\n    steps:\n      - run: npm test\n" + context)
        preview = json.loads(cli("onboard", "--json", cwd=conflict))
        assert "required_checks" in preview["pending"] and "required" not in preview["settings"]["checks"], (
            f"run#mandatory-checks: {context.strip()} needs an equivalent local check")
    plain = "name: Checks\non: push\njobs:\n  tests:\n    runs-on: ubuntu-latest\n    steps:\n      - name: Verify diff\n        run: git diff --check\n"
    workflow.write_text(plain)
    preview = json.loads(cli("onboard", "--json", cwd=conflict))
    assert preview["settings"]["checks"].get("required") == ["git diff --check"], (
        "run#mandatory-checks: a workflow of plain steps can propose its entire local check suite")
    for step in ("      - {run: npm test, working-directory: api}\n",
                 "      - {name: Integration, run: scripts/integration}\n",
                 "      - run: scripts/integration\n        if: runner.os == 'Linux'\n",
                 "      - uses: owner/actions/.github/actions/integration@v1\n"):
        workflow.write_text(plain + step)
        preview = json.loads(cli("onboard", "--json", cwd=conflict))
        assert "required_checks" in preview["pending"] and "required" not in preview["settings"]["checks"], (
            f"run#mandatory-checks: {step.strip()} must not silently reduce the suite to its plain step")
        assert not preview["sources"]["CI candidates"][".github/workflows/check.yml"]
        assert "workflow SHA-256" in preview["sources"]["CI unresolved"][".github/workflows/check.yml"][0]
    cli("onboard", "--apply", "--required-check", "git diff --check", "--required-check", "scripts/local-integration", cwd=conflict)
    assert json.loads(cli("onboard", "--json", cwd=conflict))["complete"]
    workflow.write_text(workflow.read_text().replace("integration@v1", "integration@v2"))
    assert "required_checks" in json.loads(cli("onboard", "--json", cwd=conflict))["pending"], (
        "run#mandatory-checks: changing a resolved unsupported step invalidates the whole workflow decision")
    workflow.write_text("jobs:\n  tests:\n    steps:\n      - run: |\n          scripts/unit\n")
    cli("onboard", "--apply", "--required-check", "scripts/unit", cwd=conflict)
    assert json.loads(cli("onboard", "--json", cwd=conflict))["complete"]
    workflow.write_text(workflow.read_text() + "          scripts/integration\n")
    assert "required_checks" in json.loads(cli("next", "--json", cwd=conflict))["onboarding"]["pending"], (
        "run#mandatory-checks: a change inside a resolved shell block reopens its decision")
    assert "required_checks" in cli("task", "start", "changed-block", cwd=conflict, ok=False)

    # run#contract-checked: fresh discovery and explicit checkout answers have distinct provenance.
    checks_project = root / "changing checks"
    checks_project.mkdir()
    git("init", "-qb", "main", cwd=checks_project)
    instructions = checks_project / "AGENTS.md"
    instructions.write_text("""## Environment

**Phase checks.** `scripts/old-phase`
**Full checks.** `scripts/old-full`
**Build.** `scripts/old-build`
**Dev server.** `scripts/old-dev` `https://old.example`
**Worktree setup.** `scripts/old-setup`
""")
    cli("onboard", "--apply", "--confirm-primary", "--confirm-secondary", cwd=checks_project)
    instructions.write_text(instructions.read_text().replace("old", "new"))
    refresh = json.loads(cli("onboard", "--json", cwd=checks_project))
    assert refresh["settings"]["checks"] == {"phase": ["scripts/new-phase"], "full": ["scripts/new-full"],
        "build": "scripts/new-build", "dev": "scripts/new-dev", "url": "https://new.example", "required": []}, (
        "run#contract-checked: inferred check values change with their source")
    assert refresh["settings"]["setup"] == {"command": "scripts/new-setup"}
    assert refresh["sources"]["full checks"] == {"AGENTS.md ## Environment": ["scripts/new-full"]}
    cli("onboard", "--apply", "--full-check", "scripts/confirmed", "--no-setup", cwd=checks_project)
    instructions.write_text(instructions.read_text().replace("new", "latest"))
    refresh = json.loads(cli("onboard", "--json", cwd=checks_project))
    assert refresh["settings"]["checks"]["full"] == ["scripts/confirmed"]
    assert refresh["settings"]["checks"]["phase"] == ["scripts/latest-phase"]
    assert "setup" not in refresh["settings"] and "setup" not in refresh["pending"]
    assert set(refresh["sources"]) >= {"confirmed full", "confirmed setup"}
    assert "full checks" not in refresh["sources"] and "setup" not in refresh["sources"], (
        "run#contract-checked: preview names the source of the selected values")
    for flag, value, saved_field, other_label, other_value in (
        ("--dev", "scripts/watch", "dev", "dev url", "https://latest.example"),
        ("--url", "http://localhost:4000", "url", "dev server", "scripts/latest-dev"),
    ):
        refresh = json.loads(cli("onboard", "--json", flag, value, cwd=checks_project))
        assert refresh["settings"]["checks"][saved_field] == value
        assert refresh["sources"][f"confirmed {saved_field}"] == {"chat": [value]}
        assert refresh["sources"].get(other_label) == {"AGENTS.md ## Environment": [other_value]}, (
            f"run#contract-checked: {flag} leaves the other dev setting's discovered source intact")
    cli("onboard", "--apply", "--dev", "scripts/watch", cwd=checks_project)
    refresh = json.loads(cli("onboard", "--json", cwd=checks_project))
    assert refresh["sources"]["confirmed dev"] == {"chat": ["scripts/watch"]}
    assert refresh["sources"]["dev url"] == {"AGENTS.md ## Environment": ["https://latest.example"]}

    # distribution#project-lock: pin validation remains active at the relocated path.
    lock.write_bytes(managed[lock].replace(read(lock)["guides"]["grill"].encode(), b"0" * 64))
    assert "runweld update --project" in cli("onboard", ok=False)
    cli("update", "--project", build_id)
    assert lock.read_bytes() == managed[lock]
PY
