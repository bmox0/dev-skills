"""The standalone release store and the project/run release selectors."""

import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import tomllib

VERSION = r"[0-9][A-Za-z0-9.+-]*"
RELEASE = re.compile(rf"{VERSION}@[0-9a-f]{{64}}")
TASK_ID = re.compile(r"[a-z0-9][a-z0-9-]*")
MANIFEST = "release.json"
PROGRAM = Path("skills/build/pipeline.py")
INSTRUCTIONS = "scripts/word-budgets.txt"
GUIDE_SKILLS = ("grill", "prototype", "run-file", "plan", "build", "review", "verify", "land", "finish",
                "bug", "epic", "handoff", "retro", "spec", "domain-modeling", "tdd", "browser-test", "commit-work")
ROLES = ("implementer", "reviewer", "judge")
REQUIRED = {str(PROGRAM), INSTRUCTIONS, "bin/runweld", "runweld/SKILL.md", "skills/build/runweld_release.py",
            *(f"skills/build/_marko/{name}.py" for name in ("__init__", "block", "element", "helpers", "inline",
                                                         "inline_parser", "parser", "patterns", "source")),
            "skills/browser-test/tab.mjs", "skills/run-file/references/example.run.toml",
            "skills/build/references/example.guide.md", "skills/build/references/judge.md", "references/SESSIONS.md",
            "references/WORKFLOW-PATHS.md", "skills/build/references/human-guide.md",
            "skills/run-file/references/project-config.md",
            *(f"agents/{role}.md" for role in ROLES), *(f"skills/{skill}/SKILL.md" for skill in GUIDE_SKILLS)}


class ReleaseError(Exception):
    pass


def valid_release(value):
    return isinstance(value, str) and RELEASE.fullmatch(value) is not None


def regular_bytes(path):
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NONBLOCK), "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            raise OSError(f"{path} is not a regular file")
        return f.read()


def read_data(path, reader):
    try:
        return reader(regular_bytes(path).decode("utf-8"))
    except FileNotFoundError:
        if not os.path.lexists(path):
            return None
        raise ReleaseError(f"{path} points to a missing file; restore it") from None
    except (OSError, ValueError, RecursionError) as error:
        raise ReleaseError(f"cannot read {path}: {error}; restore it from a known-good copy") from None


def atomic_write(path, data, mode=0o644):
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            os.fchmod(f.fileno(), mode)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def release_files(root):
    files = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if rel == Path(MANIFEST) or "__pycache__" in rel.parts:
            continue
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise ValueError(f"{rel} is not a regular file")
        files[rel.as_posix()] = [hashlib.sha256(regular_bytes(path)).hexdigest(), bool(mode & stat.S_IXUSR)]
    return files


def manifest_bytes(root, version):
    if not isinstance(version, str) or not re.fullmatch(VERSION, version):
        raise ValueError(f"invalid release version {version!r}")
    files = release_files(root)
    if missing := REQUIRED - files.keys():
        raise ValueError(f"missing release resources: {', '.join(sorted(missing))}")
    instructions = {line.split()[0] for line in regular_bytes(root / INSTRUCTIONS).decode("utf-8").splitlines()
                    if line.strip() and not line.lstrip().startswith("#")}
    if missing := instructions - files.keys():
        raise ValueError(f"missing release instructions: {', '.join(sorted(missing))}")
    return json.dumps({"version": version, "files": files}, sort_keys=True).encode()


def release_id(version, manifest):
    return f"{version}@{hashlib.sha256(manifest).hexdigest()}"


def release_manifest(root, release):
    if not valid_release(release):
        raise ReleaseError(f"invalid release {release!r}; use the exact ID printed by the installer")
    try:
        if root.is_symlink() or not root.is_dir():
            raise OSError("release directory is missing or is not a real directory")
        manifest = regular_bytes(root / MANIFEST)
        expected = json.loads(manifest)
        if release_id(expected["version"], manifest) != release:
            raise ValueError("release manifest does not match its ID")
        if set(expected) != {"version", "files"} or not isinstance(expected["files"], dict):
            raise ValueError("invalid release manifest")
        return expected
    except (OSError, ValueError, KeyError, TypeError, RecursionError) as error:
        raise ReleaseError(f"{release} at {root}: {error}; install this exact release from its source") from None


def verify_release(store, release):
    root = store / "releases" / release
    expected = release_manifest(root, release)
    try:
        actual = json.loads(manifest_bytes(root, expected["version"]))
        if expected != actual:
            changed = next(p for p in sorted(expected["files"].keys() | actual["files"].keys())
                           if expected["files"].get(p) != actual["files"].get(p))
            raise ValueError(f"damaged release resource {changed}")
    except (OSError, ValueError, KeyError, TypeError, RecursionError) as error:
        raise ReleaseError(f"{release} at {root}: {error}; install this exact release from its source") from None
    return root


def installed_root(pipeline):
    root = Path(pipeline).resolve().parents[2]
    return root if root.parent.name == "releases" and valid_release(root.name) else None


def worktrees(path):
    """Git's registered checkouts, in order, with their local branches."""
    directory = Path(path).absolute()
    while not directory.is_dir() and directory != directory.parent:
        directory = directory.parent
    try:
        result = subprocess.run(["git", "worktree", "list", "--porcelain", "-z"], cwd=directory,
                                capture_output=True, check=False)
    except OSError as error:
        raise ReleaseError(f"cannot find the project worktree: {error}") from None
    if result.returncode:
        return []
    trees = []
    for record in result.stdout.split(b"\0\0"):
        path, *facts = record.split(b"\0")
        if path.startswith(b"worktree "):
            branch = next((os.fsdecode(f[18:]) for f in facts if f.startswith(b"branch refs/heads/")), None)
            trees.append((Path(os.fsdecode(path[9:])), branch))
    return trees


def project_root(path):
    trees = worktrees(path)
    return trees[0][0] if trees else None


def history_path(path):
    md = Path(path).absolute()
    parent = md.parent
    if (parent.name, parent.parent.name, parent.parent.parent.name) == ("plans", "workflow", ".runweld"):
        if project := project_root(parent.parent.parent.parent):
            return project / ".runweld/workflow/plans" / md.name
    return md


def command_plan(args, cwd):
    if plan := getattr(args, "plan", None):
        return plan
    by_id = args.group == "task" and args.command in ("start", "resume", "path")
    in_task = ((args.group == "status" and args.current) or
               (args.group == "help" and args.topic == "agents"))
    if not (by_id or in_task) or not (project := project_root(cwd)):
        return None
    workflow = project / ".runweld/workflow"
    if by_id:
        name = args.id
    elif cwd.is_relative_to(workflow / "trees"):
        parts = cwd.relative_to(workflow / "trees").parts
        name = parts[0] if parts else ""
    else:
        return None
    if TASK_ID.fullmatch(name) and os.path.lexists(workflow / "tasks" / (name + ".json")):
        return workflow / "plans" / (name + ".md")


def lock_path(project):
    return project / ".runweld" / "runweld.lock"


def component_key(path):
    parts = path.split("/")
    if parts[0] == "agents" and len(parts) == 2 and path.endswith(".md"):
        return "roles", parts[1][:-3]
    if parts[0] == "skills" and len(parts) >= 3:
        if parts[1] == "build" and (path.endswith(".py") or parts[2] == "_marko"):
            return "cli", "engine"
        return "skills", parts[1]
    if parts[0] == "adapters" and len(parts) >= 3:
        return "adapters", parts[1]
    if parts[0] == "bin":
        return "cli", "launcher"
    return "resources", parts[0]


def project_lock(bundle):
    release = bundle.name
    manifest = release_manifest(bundle, release)
    groups = {}
    for path, entry in manifest["files"].items():
        section, name = component_key(path)
        groups.setdefault(section, {}).setdefault(name, {})[path] = entry
    lines = ["version = 1", f'release = "{release}"']
    for section, components in sorted(groups.items()):
        lines.extend(["", f"[{section}]"])
        for name, entries in sorted(components.items()):
            digest = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
            lines.append(f'{json.dumps(name)} = "sha256:{digest}"')
    return "\n".join(lines) + "\n"


def read_lock(project, store):
    path = lock_path(project)
    value = read_data(path, tomllib.loads)
    if value is None:
        return None
    release = value.get("release")
    if not valid_release(release):
        raise ReleaseError(f"{path} needs one exact release ID as `release = \"…\"`; run `runweld update --project RELEASE` or restore the lock")
    if type(value.get("version")) is not int or value["version"] != 1:
        raise ReleaseError(f"{path} needs lock format 1; run `runweld update --project` or restore the lock")
    expected = tomllib.loads(project_lock(store / "releases" / release))
    if expected != value:
        raise ReleaseError(f"{path} does not match the components of {release}; run `runweld update --project {release}` or restore the lock")
    return release


def write_lock(project, bundle):
    path = lock_path(project)
    if path.is_symlink() or path.parent.is_symlink():
        raise ReleaseError(f"{path} must be a regular project file in a real .runweld directory")
    try:
        path.parent.mkdir(exist_ok=True)
        atomic_write(path, project_lock(bundle).encode())
    except OSError as error:
        raise ReleaseError(f"cannot write {path}: {error}; repair the project lock location") from None


def release_pin(values, path):
    if "workflow" not in values:
        return None
    workflow = values["workflow"]
    if not isinstance(workflow, dict) or set(workflow) != {"release"} or not valid_release(workflow["release"]):
        raise ReleaseError(f"{path} needs one exact release ID at [workflow].release; restore the run file or snapshot")
    return workflow["release"]


def read_task_record(path):
    if path.is_symlink():
        raise ReleaseError(f"{path} is a symbolic link; restore the task record")
    value = read_data(path, json.loads)
    if value is None and not path.exists():
        return None
    fields = {"base", "ready", "branch"}
    # Retained engines expect the three-field record to stay unchanged.
    if (not isinstance(value, dict) or set(value) not in (fields, fields | {"release"}) or
            not isinstance(value["base"], str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", value["base"]) or
            type(value["ready"]) is not bool or value["branch"] != "runweld/" + path.stem or
            ("release" in value and not valid_release(value["release"]))):
        raise ReleaseError(f"{path} has an invalid task record; restore the task record from a known-good copy")
    return value


def registered_task(plan):
    if plan.parent.parts[-3:] == (".runweld", "workflow", "plans") and TASK_ID.fullmatch(plan.stem):
        return read_task_record(plan.parent.parent / "tasks" / (plan.stem + ".json"))


def task_pin(pin, task, path):
    if task is not None:
        recorded = task.get("release")
        if pin is None or (recorded is not None and pin != recorded):
            expected = f" {recorded}" if recorded else ""
            raise ReleaseError(f"{path} must retain the task's original [workflow].release{expected}; restore the run file or snapshot")
    elif pin is not None:
        raise ReleaseError(f"{path} pins a release without a registered task; use `runweld task start ID` and the returned plan path")
    return pin


def run_pin(plan):
    plan = history_path(plan)
    if plan.suffix != ".md":
        return None
    task = registered_task(plan)
    state_path = plan.with_suffix(".json")
    state = read_data(state_path, json.loads)
    if state is not None and not isinstance(state, dict):
        raise ReleaseError(f"{state_path} must contain a compiled plan object; restore the state")
    if state:
        approvals = state.get("approvals", {})
        values = state.get("run", {})
        if not isinstance(approvals, dict) or not isinstance(values, dict):
            raise ReleaseError(f"{state_path} has an invalid run snapshot; restore the state")
        if "run" in approvals or state.get("status") != "draft":
            return task_pin(release_pin(values, state_path), task, state_path)
    run_file = plan.with_suffix(".run.toml")
    proposed = read_data(run_file, tomllib.loads)
    if proposed is None and task is not None and not task["ready"]:
        return task.get("release")  # An interrupted entry uses its reservation when one exists.
    return task_pin(release_pin(proposed, run_file) if proposed is not None else None, task, run_file)


def installed_default(store):
    path = store / "default"
    value = read_data(path, str.strip)
    if not valid_release(value):
        raise ReleaseError(f"{path} has no installed default; reinstall Runweld")
    return value


def update_installation(store, scope, requested):
    if scope is None:
        if not sys.stdin.isatty():
            raise ReleaseError("choose an update scope: --cli or --project")
        try:
            scope = input("Update the CLI or this project? Type cli or project: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            raise ReleaseError("update cancelled") from None
        if scope not in ("cli", "project"):
            raise ReleaseError("no update selected; choose --cli or --project")
    if scope == "cli":
        if requested is not None:
            raise ReleaseError("an installed release ID applies to --project only")
        bootstrap = verify_release(store, installed_default(store)) / "install.sh"
        os.execlp("bash", "bash", str(bootstrap), "--prefix", str(store.parents[1]))

    project = project_root(Path.cwd())
    if project is None:
        raise ReleaseError("outside a Git repository; run `runweld update --project` from an initialized project checkout")
    if not os.path.lexists(lock_path(project)):
        raise ReleaseError(f"{lock_path(project)} is missing; run `runweld init` in this repository or restore its lock")
    release = requested if requested is not None else installed_default(store)
    bundle = verify_release(store, release)
    write_lock(project, bundle)
    print(f"Updated {lock_path(project)} to {release}")
