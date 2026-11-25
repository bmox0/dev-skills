#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export INSTALLER="$repo_root/scripts/install-ds"
export DS_TEST_LEGACY_ROOT="${DS_TEST_LEGACY_ROOT:-$repo_root}"
python3 -B <<'PY'
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as folder:
    home = Path(folder).resolve()
    root = home / "project with spaces"
    root.mkdir()
    env = dict(os.environ, GIT_AUTHOR_NAME="Tester", GIT_AUTHOR_EMAIL="test@example.org",
               GIT_COMMITTER_NAME="Tester", GIT_COMMITTER_EMAIL="test@example.org")
    ds = home / "bin/ds"
    legacy = Path(os.environ["DS_TEST_LEGACY_ROOT"]).resolve()
    legacy_cli = [sys.executable, "-B", legacy / "skills/build/pipeline.py"]

    def run(*args, cwd=root, ok=True):
        p = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
        assert (p.returncode == 0) == ok, p.stdout + p.stderr
        return p.stdout.strip() if ok else p.stdout + p.stderr

    run(os.environ["INSTALLER"], "--prefix", home, cwd=home)
    run("git", "init", "-qb", "main")
    run("git", "commit", "--allow-empty", "-qm", "base")
    checkout = home / "old linked"
    run("git", "worktree", "add", "-qb", "work-with-legacy", checkout)
    here = root / ".ai-workflow/plans"
    there = checkout / ".ai-workflow/plans"
    other_checkout = here.parent / "other linked"
    run("git", "worktree", "add", "-qb", "other-legacy", other_checkout)
    parent_alias = home / "checkout paths"
    parent_alias.symlink_to(home, target_is_directory=True)
    cross_capture = other_checkout / ".ai-workflow/evidence/cross.capture.txt"
    external_file = home / "external/.ai-workflow/external.txt"
    external_child = external_file.parent / "child"
    external_control = home / "external control"
    external_control.symlink_to(external_child, target_is_directory=True)
    external = external_control / "../external.txt"
    for d in (here, there, cross_capture.parent, external_child):
        d.mkdir(parents=True)

    def write_hopped(evidence_dir, content):
        child = evidence_dir.parent / "actual/child"
        child.mkdir(parents=True)
        (evidence_dir / "hop").symlink_to("../actual/child", target_is_directory=True)
        (child.parent / "cross.capture.txt").write_text(content)

    prefix_child = here.parent / "prefix-child"
    prefix_child.mkdir()
    prefix_hop = home / "checkout hop"
    prefix_hop.symlink_to(prefix_child.relative_to(home), target_is_directory=True)
    cross_hopped = cross_capture.parent / "hop/../cross.capture.txt"
    cross_via_prefix = prefix_hop / ".." / cross_hopped.relative_to(here.parent)
    hopped_content = "Evidence through a directory symlink and .."
    cross_capture.write_text("Evidence from the other checkout")
    write_hopped(cross_capture.parent, hopped_content)
    cross_root = cross_capture.parent.parent
    workflow_alias = home / "workflow path"
    workflow_alias.symlink_to(cross_root, target_is_directory=True)
    (cross_capture.parent / "absolute-hop").symlink_to(cross_root / "actual/child", target_is_directory=True)
    external_absolute = cross_capture.parent / "external-absolute"
    external_relative = cross_capture.parent / "external-relative"
    external_absolute.symlink_to(external_child, target_is_directory=True)
    external_relative.symlink_to(os.path.relpath(external_child, cross_capture.parent), target_is_directory=True)
    external_file.write_text("Evidence outside the adopted checkouts")
    missing_external = external_file.parent / "missing directory/../external.txt"
    external_routes = [
        (external_absolute / "../external.txt", external_file),
        (external_relative / "../external.txt", external_file),
        (external_absolute / "../missing directory/../external.txt", missing_external),
    ]
    plain = Path("evidence/cross.capture.txt")
    hopped = Path("actual/cross.capture.txt")
    routes = [
        (cross_root / "../.ai-workflow" / plain, plain),
        (cross_root / "evidence/../../.ai-workflow" / plain, plain),
        (cross_capture.parent / "hop/../../../.ai-workflow" / hopped, hopped),
        (cross_capture.parent / "absolute-hop/../cross.capture.txt", hopped),
        (workflow_alias / plain, plain),
        (workflow_alias / "../.ai-workflow" / plain, plain),
        *external_routes,
    ]
    assert cross_hopped.read_text() == cross_via_prefix.read_text() == hopped_content
    assert cross_capture.read_text() != hopped_content
    expected_bytes = {name: (cross_root / name).read_bytes() for _, name in routes if name != missing_external}
    assert all(path.read_bytes() == expected_bytes[name] for path, name in routes if name in expected_bytes)
    assert external.read_bytes() == expected_bytes[external_file] and not external_routes[-1][0].exists()
    done = here / "historical.md"
    done.write_text("# Plan: Historical\n\nStatus: merged · branch `historical` · base `old`\n")
    archive = here.parent / "retro/notes"
    archive.parent.mkdir()
    archive.write_text("Keep private historical evidence")
    plan = there / "active.md"
    plan.write_text("""# Plan: Adopt an active workflow

Status: draft · branch `old-task` · base `—`

## Result

Keep the evidence.

## Approach

Work in the legacy isolation mode.

## Out of scope

- New task entry.

## Phases

### 1. Change — `waiting`

Territory: `src/`
Skills: none
Spec: none
Waits for: nothing

## Checks

- Gate: small — fixture

## Done

1. Adopt → no lost records.
2. Read command output → inline capture stays inline.
3. Read cross-checkout output → captured evidence stays with its owner.
4. Read external output → unadopted owners keep their original path.
5. Use a checkout alias → retained evidence still resolves to its owner.
6. Follow a symlink and .. → the capture keeps its original meaning.
7. Leave and reenter the history root → the retained file is unchanged.
8. Reenter the history root from an evidence subdirectory → the retained file is unchanged.
9. Follow a directory symlink out and back into the history root → the retained file is unchanged.
10. Follow an absolute directory symlink and .. → the retained file is unchanged.
11. Enter history through a symlink to its source or archive → the retained file is unchanged.
12. Reenter the history root via a symlink or archive alias → the retained file is unchanged.
13. Follow an absolute symlink from retained history → the external file remains reachable.
14. Follow a relative symlink from retained history → the external file remains reachable.
15. Follow a missing component outside retained history → no other capture takes its place.

## Spec

none
""")
    main_plan = here / "main-active.md"
    main_plan.write_text(plan.read_text().replace("`old-task`", "`old-main-task`"))

    def approve(path, external_summary=None):
        example = legacy / "skills/run-file/references/example.run.toml"
        path.with_suffix(".run.toml").write_text(example.read_text().replace('full = ["scripts/check", "scripts/test"]', 'full = ["true"]'))
        run(*legacy_cli, "approve", path)
        run(*legacy_cli, "run", "approve", path, "--by", "User", "--words", "Approved before ds")
        summary = path.with_suffix(".summary.md")
        if external_summary:
            summary.symlink_to(external_summary)
        target = path.name if external_summary else path
        summary.write_text(f"[Read the plan](<{target}>) and preserve its approval.\n")
        run(*legacy_cli, "summary", "approve", path, "--file", summary, "--by", "User", "--words", "Approved start")
        return json.loads(path.with_suffix(".json").read_text())["approvals"]

    external_summary = external_file.parent / "active.summary.md"
    approved = approve(plan, external_summary)
    main_approved = approve(main_plan)
    run_file = plan.with_suffix(".run.toml")
    summary = plan.with_suffix(".summary.md")
    evidence = there / "active.capture.txt"
    evidence.write_text("Evidence, unchanged")
    main_evidence = here / "main.capture.txt"
    main_evidence.write_text("Evidence from the main checkout")

    def land(path, build_tree, captures):
        (build_tree / "fixture.txt").write_text("Fixture change")
        run("git", "add", "fixture.txt", cwd=build_tree)
        run("git", "commit", "-qm", "fixture change", cwd=build_tree)
        run(*legacy_cli, "gate", "start", path, "--note", "Fixture evidence")
        for n, capture in enumerate(captures, 1):
            run(*legacy_cli, "result", path, "--case", str(n), "--outcome", "passed", "--capture", capture)
        brief = Path(run(*legacy_cli, "brief", "reviewer", path))
        complete = next(line.removeprefix("- Complete the review: ") for line in brief.read_text().splitlines()
                        if line.startswith("- Complete the review: "))
        run(*shlex.split(complete))
        run(*legacy_cli, "verdict", "pass", path, "--report", "Fixture reviewed", "--predicted", "pass", "--engine", "fixture")
        run(*legacy_cli, "land", "draft", path)
        shape = path.with_suffix(".shape.toml")
        shape.write_text(shape.read_text().replace('message = ""', 'message = "fix: fixture"').replace('walkthrough = ""', 'walkthrough = "Read fixture.txt"'))
        run(*legacy_cli, "land", path)
        raw = path.with_suffix(".json").read_bytes()
        assert [r["capture"] for r in json.loads(raw)["cycles"][0]["results"]] == list(map(str, captures))
        return raw

    inline = "Fixture output, unchanged"
    cross_via_alias = parent_alias / cross_capture.relative_to(home)
    main_via_alias = parent_alias / main_evidence.relative_to(home)
    main_build = home / "old main build tree"
    run(*legacy_cli, "build", "start", main_plan, "--base", "main", "--worktree", main_build)
    run(*legacy_cli, "phase", "start", main_plan, "1", cwd=home)
    main_captures = [main_evidence, inline, cross_capture, external, cross_via_alias, cross_via_prefix,
                     *(path for path, _ in routes)]
    raw_main = land(main_plan, main_build, main_captures)
    original_main = json.loads(run(*legacy_cli, "status", main_plan, "--json"))
    original_hopped = original_main["cycles"][0]["results"][5]["capture"]
    assert original_hopped == str(cross_via_prefix) and Path(original_hopped).read_text() == hopped_content

    lock = plan.with_suffix(".json.lock")
    inode = lock.stat().st_ino
    issued = [*legacy_cli, "build", "start", plan, "--base", "main", "--worktree", home / "old build tree"]

    # distribution#local-workflow: a collided destination survives and an adoption retry adds only the aliases it needs.
    shared = root / ".ds/workflow"
    private_alias = shared / "legacy/main"
    other_key = hashlib.sha256(json.dumps(str(other_checkout)).encode()).hexdigest()[:16]
    retained_cross_root = private_alias.with_name(other_key)
    archived_main = private_alias / "plans/main-active.md"
    private_alias.parent.mkdir(parents=True)
    private_alias.write_text("existing private path")
    init = [ds, "init", "--non-interactive", "--provider", "Test", "--primary-model", "main", "--secondary-model", "helper"]
    assert "migration-collision" in run(*init, ok=False)
    assert private_alias.read_text() == "existing private path" and evidence.read_text() == "Evidence, unchanged"
    private_alias.rename(private_alias.with_name("saved"))
    key = hashlib.sha256(json.dumps(str(checkout)).encode()).hexdigest()[:16]
    old_alias = private_alias.with_name(key)
    old_alias.mkdir()
    marker = old_alias / "keep-me"
    marker.write_text("private collision")
    assert "migration-collision" in run(*init, ok=False)
    assert marker.read_text() == "private collision" and evidence.read_text() == "Evidence, unchanged"
    old_alias.rename(old_alias.with_name("saved-linked"))
    old_alias.symlink_to(there.parent)
    with lock.open("a") as writer:
        fcntl.flock(writer, fcntl.LOCK_EX)
        adopting = subprocess.Popen(init, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            out, err = adopting.communicate(timeout=1)
            raise AssertionError(f"distribution#local-workflow: migration raced an open writer: {out}{err}")
        except subprocess.TimeoutExpired:
            assert not there.parent.is_symlink()
            fcntl.flock(writer, fcntl.LOCK_UN)
        out, err = adopting.communicate(timeout=10)
        assert adopting.returncode == 0, out + err
        assert os.fstat(writer.fileno()).st_ino == lock.stat().st_ino == inode
    assert private_alias.is_symlink() and (private_alias / "retro/notes").read_bytes() == archive.read_bytes()
    assert old_alias.is_dir() and not old_alias.is_symlink() and there.parent.readlink() == old_alias
    assert lock.stat().st_ino == (old_alias / "plans/active.json.lock").stat().st_ino == inode
    assert (old_alias / "plans/active.capture.txt").read_bytes() == evidence.read_bytes()

    def check_routes(captures, expected_routes):
        assert len(captures[6:]) == len(expected_routes)
        for capture, (original, name) in zip(captures[6:], expected_routes):
            retained = retained_cross_root / name
            path = Path(capture)
            if name == missing_external:
                assert path == retained and not path.exists(), (
                    f"distribution#local-workflow: {original} must stay missing, got {path}"
                )
                continue
            assert path.is_file() and path.samefile(retained) and path.read_bytes() == expected_bytes[name], (
                f"distribution#local-workflow: {original} should still read {retained}, got {path}"
            )

    for source in (main_plan, archived_main):
        migrated = json.loads(run(ds, "status", source, "--json"))
        check_routes([r["capture"] for r in migrated["cycles"][0]["results"]], routes)
    before = {p: p.read_bytes() for p in (plan, run_file, summary, evidence, cross_capture, archive, done)}
    there.parent.unlink()  # Simulate an interruption after the rename but before restoring the old path.
    run(*init)
    assert all(p.read_bytes() == data for p, data in before.items())
    assert "task-collision" in run(ds, "task", "start", "active", ok=False)

    # run#changes-through-approve: invoke exactly the previously issued command, then read the same state through its alias.
    before_build = json.loads(run(ds, "status", old_alias / "plans/active.md", "--json", cwd=home))
    assert before_build["tree"] == str(checkout), "distribution#local-workflow: adoption must not reassign the linked legacy checkout"
    run(*issued, cwd=home)
    state = json.loads(run(ds, "status", old_alias / "plans/active.md", "--json", cwd=home))
    assert state["approvals"] == approved and not state["drift"], state["drift"]
    assert state["release"] is None, "historical work must not be relabeled with the project release"
    assert state["tree"] == str(home / "old build tree")
    run(*legacy_cli, "phase", "start", plan, "1", cwd=home)
    expected_inventory = [("active", "building"), ("historical", "merged"), ("main-active", "building")]
    inventory = json.loads(run(ds, "status", "--json"))
    assert sorted((row["plan"], row["status"]) for row in inventory) == expected_inventory
    current, = json.loads(run(ds, "status", "--current", "--json", cwd=home / "old build tree"))
    assert Path(current["path"]).resolve() == plan.resolve() and current["phases"][0]["status"] == "in progress"
    assert json.loads(run(ds, "run", "show", plan, "--json"))["approved"]
    assert "?? .ds/config.toml" in run("git", "status", "--short", "--untracked-files=all")
    assert "?? .ds/ds.lock" in run("git", "status", "--short", "--untracked-files=all")
    for cwd in (root, checkout):
        for path in (".ai-workflow" if cwd == checkout else ".ai-workflow/plans/new.md", ".ds/workflow/scratch/file"):
            run("git", "check-ignore", path, cwd=cwd)
        run("git", "check-ignore", "docs/spec/area.md", cwd=cwd, ok=False)

    archive_hop = evidence.parent / "archive-hop"
    archive_hop.symlink_to(retained_cross_root / "actual/child", target_is_directory=True)
    linked_routes = [*routes[:4], (archive_hop / "../cross.capture.txt", hopped),
                     (retained_cross_root / ".." / other_key / plain, plain), *external_routes]
    linked_captures = [evidence, inline, cross_capture, external, main_via_alias, cross_hopped,
                       *(path for path, _ in linked_routes)]
    raw = land(plan, home / "old build tree", linked_captures)
    for source in (plan, old_alias / "plans/active.md"):
        migrated = json.loads(run(ds, "status", source, "--json"))
        check_routes([r["capture"] for r in migrated["cycles"][0]["results"]], linked_routes)

    # distribution#local-workflow: the normal removal of a linked checkout keeps its adopted history.
    run("git", "worktree", "remove", checkout)
    run("git", "worktree", "remove", other_checkout)
    assert not checkout.exists() and (old_alias / "plans/active.capture.txt").read_text() == "Evidence, unchanged"
    run(*init)
    inventory = json.loads(run(ds, "status", "--json"))
    assert sorted((row["plan"], row["status"]) for row in inventory) == expected_inventory
    kept = json.loads(run(ds, "status", old_alias / "plans/active.md", "--json"))
    assert kept["approvals"] == approved and not kept["drift"]
    saved_plan = old_alias / "plans/active.md"
    saved_capture = old_alias / "plans/active.capture.txt"
    saved_cross = retained_cross_root / plain
    saved_hopped = retained_cross_root / hopped

    def check_hopped(capture):
        path = Path(capture)
        assert path.resolve() == saved_hopped and path.read_text() == hopped_content, (
            f"distribution#local-workflow: the recorded symlink path must still read {saved_hopped}, got {path}"
        )

    assert not other_checkout.exists() and saved_cross.read_text() == "Evidence from the other checkout"
    assert kept["cycles"][0]["results"][0]["capture"] == str(saved_capture), "distribution#local-workflow: archived status points to the kept capture"
    assert kept["cycles"][0]["results"][1]["capture"] == inline
    assert kept["cycles"][0]["results"][2]["capture"] == str(saved_cross), "distribution#local-workflow: the nested linked checkout owns its retained evidence"
    check_hopped(kept["cycles"][0]["results"][5]["capture"])
    check_routes([r["capture"] for r in kept["cycles"][0]["results"]], linked_routes)
    absent = json.loads(run(ds, "status", archived_main, "--json"))
    check_hopped(absent["cycles"][0]["results"][5]["capture"])
    check_routes([r["capture"] for r in absent["cycles"][0]["results"]], routes)
    assert str(saved_capture) in run(ds, "status", saved_plan)
    assert saved_plan.with_suffix(".json").read_bytes() == raw, "status does not rewrite the judge's evidence"

    # distribution#local-workflow: a new checkout at the old path is not the owner of archived evidence.
    run("git", "worktree", "add", "-qb", "unrelated", checkout)
    run("git", "worktree", "add", "-qb", "other-unrelated", other_checkout)
    cross_capture.parent.mkdir(parents=True)
    cross_capture.write_text("Unrelated cross-checkout output")
    write_hopped(cross_capture.parent, "Unrelated output through a symlink")
    (cross_capture.parent / "absolute-hop").symlink_to(cross_root / "actual/child", target_is_directory=True)
    decoy_child = cross_capture.parent / "decoy/child"
    decoy_child.mkdir(parents=True)
    (decoy_child.parent / "missing directory").mkdir()
    (decoy_child.parent / "external.txt").write_text("Unrelated external output")
    for link in (external_absolute, external_relative):
        link.symlink_to(decoy_child, target_is_directory=True)
    assert all(original.read_text() == "Unrelated external output" for original, _ in external_routes)
    evidence.parent.mkdir(parents=True)
    evidence.write_text("Unrelated checkout's output")
    archive_hop.symlink_to(cross_root / "actual/child", target_is_directory=True)
    summary.write_text("Unrelated checkout's summary")
    plan.write_text("# Unrelated checkout's plan\n")
    kept = json.loads(run(ds, "status", saved_plan, "--json"))
    assert kept["cycles"][0]["results"][0]["capture"] == str(saved_capture), "distribution#local-workflow: archive provenance wins over the reused pathname"
    assert kept["approvals"] == approved and not kept["drift"]
    assert Path(kept["cycles"][0]["results"][0]["capture"]).read_text() == "Evidence, unchanged"
    cross_result = kept["cycles"][0]["results"][2]["capture"]
    assert cross_result == str(saved_cross), "distribution#local-workflow: a capture follows its owner's archive, not the plan's"
    assert Path(cross_result).read_text() == "Evidence from the other checkout"
    guide = "Open fixture.txt\n\n#### Checks\n\n- **Done 1** Read fixture.txt → Fixture change.\n\n#### Decisions\n\n- —"

    def check_displays(path, recorded, approvals, same_owner, via_alias, originals, expected_routes, *, cwd=root):
        state = json.loads(run(ds, "status", path, "--json", cwd=cwd))
        assert state["approvals"] == approvals and not state["drift"]
        actual = [r["capture"] for r in state["cycles"][0]["results"]]
        assert actual[2] == str(saved_cross), f"distribution#local-workflow: {path} picks {actual[2]} instead of the adopted owner's {saved_cross}"
        assert actual[:5] == [str(same_owner), inline, str(saved_cross), str(external), str(via_alias)], actual
        assert Path(actual[2]).read_text() == "Evidence from the other checkout"
        check_hopped(actual[5])
        check_routes(actual, expected_routes)
        assert path.with_suffix(".json").read_bytes() == recorded
        judge = Path(run(ds, "brief", "judge", path, cwd=cwd))
        run(ds, "page", path, "--guide", guide, "--message", "Fixture change", cwd=cwd)
        for view in (run(ds, "status", path, cwd=cwd), judge.read_text(), path.read_text()):
            assert all(expected in view for expected in actual)
            assert all(str(original) not in view for original in originals)
        stored = json.loads(path.with_suffix(".json").read_text())
        assert stored["approvals"] == approvals and stored["cycles"] == json.loads(recorded)["cycles"]

    saved_main = private_alias / "plans/main.capture.txt"
    main_cwd = parent_alias / root.name
    main_originals = [main_evidence, cross_via_alias, cross_capture, cross_via_prefix]
    check_displays(archived_main, raw_main, main_approved, saved_main, saved_cross, main_originals, routes, cwd=main_cwd)
    check_displays(main_plan, main_plan.with_suffix(".json").read_bytes(), main_approved, saved_main, saved_cross,
                   main_originals, routes, cwd=main_cwd)
    check_displays(saved_plan, raw, approved, saved_capture, saved_main,
                   [evidence, cross_capture, main_via_alias, cross_hopped], linked_routes)

    # Even identical plan and state bytes at the reused path do not make a live plan archival.
    for live_plan in (plan, other_checkout / ".ai-workflow/plans/active.md"):
        live_plan.parent.mkdir(parents=True, exist_ok=True)
        live_plan.write_text(saved_plan.read_text())
        live_plan.with_suffix(".json").write_bytes(raw)
        live = json.loads(run(ds, "status", live_plan, "--json"))
        assert live["path"] == str(live_plan)
        actual = [r["capture"] for r in live["cycles"][0]["results"]]
        assert actual == list(map(str, linked_captures)), \
            f"distribution#local-workflow: {live_plan} is unrelated, not archival: {actual}"
    assert evidence.read_text() == "Unrelated checkout's output"
    assert cross_capture.read_text() == "Unrelated cross-checkout output"

    saved_cross.unlink()
    saved_hopped.unlink()
    external_file.unlink()
    external_summary.unlink()
    missing_summary = json.loads(run(ds, "status", saved_plan, "--json"))["drift"]
    assert any(f"{external_summary} does not exist" in line for line in missing_summary), missing_summary
    missing = json.loads(run(ds, "status", archived_main, "--json"))["cycles"][0]["results"]
    assert missing[2]["capture"] == str(saved_cross) and not saved_cross.exists(), "distribution#local-workflow: a missing adopted capture cannot become unrelated live evidence"
    missing_hopped = Path(missing[5]["capture"])
    assert missing_hopped.resolve() == saved_hopped and not missing_hopped.exists()
    for item, (original, name) in zip(missing[6:], routes, strict=True):
        path = Path(item["capture"])
        expected = retained_cross_root / name
        assert (path == expected or path.resolve() == expected) and not path.exists(), (
            f"distribution#local-workflow: missing archived evidence for {original} cannot fall back to {path}"
        )
    assert cross_via_prefix.read_text() == "Unrelated output through a symlink"
PY
