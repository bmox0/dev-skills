#!/usr/bin/env bash
set -euo pipefail
export SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 -B <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(os.environ["SOURCE"])
with tempfile.TemporaryDirectory() as folder:
    home = Path(folder).resolve()
    fixture_bin = home / "bin"
    fixture_bin.mkdir()
    upstream = home / "upstream"
    upstream.mkdir()
    real_git = shutil.which("git")
    assert real_git
    env = dict(os.environ, HOME=str(home), PATH=f"{fixture_bin}:{os.environ['PATH']}",
               XDG_CONFIG_HOME=str(home / "preferences"), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
               GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.org",
               GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.org",
               GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0=f"url.{upstream.as_uri()}.insteadOf",
               GIT_CONFIG_VALUE_0="https://github.com/bmox0/runweld.git",
               FIXTURE_HOME=str(home), FIXTURE_GIT=real_git)
    env.pop("RUNWELD_REF", None)

    def run(*args, cwd=home, settings=None, ok=True, stdin=subprocess.DEVNULL):
        result = subprocess.run(args, cwd=cwd, env=env | (settings or {}), text=True, capture_output=True,
                                stdin=stdin, timeout=30)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        return result.stdout.strip() if ok else result.stderr.strip()

    def git(*args):
        return run(real_git, *args, cwd=upstream)

    def commit(version, marker):
        (upstream / "VERSION").write_text(version + "\n")
        (upstream / "README.md").write_text(marker + "\n")
        git("add", ".")
        git("commit", "-qm", marker)
        return git("rev-parse", "HEAD")

    def fixture_command(name, script):
        path = fixture_bin / name
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + script)
        path.chmod(0o755)

    fixture_command("curl", """
if [[ "${!#}" == https://raw.githubusercontent.com/bmox0/runweld/main/install.sh ]]; then
    touch "$FIXTURE_HOME/mutable-bootstrap"
    exec cat "$SOURCE/install.sh"
fi
if [[ "${!#}" == https://github.com/bmox0/runweld/releases/latest ]]; then
    printf '%s\\n' "${!#}" >> "$FIXTURE_HOME/latest.requests"
    exec python3 -c 'import json, sys; print("https://github.com/bmox0/runweld/releases/tag/" + json.load(sys.stdin)["tag_name"], end="")' < "$FIXTURE_HOME/latest.json"
fi
[[ "${!#}" == https://api.github.com/repos/bmox0/runweld/releases/latest ]]
printf '%s\\n' "${!#}" >> "$FIXTURE_HOME/latest.requests"
if [[ -f "$FIXTURE_HOME/latest.json" ]]; then
    cat "$FIXTURE_HOME/latest.json"
else
    exit 22
fi
""")
    fixture_command("git", """
if [[ "${3:-}" == fetch ]]; then
    if [[ -n "${MOVE_TAG_TO:-}" ]]; then
        "$FIXTURE_GIT" -C "$FIXTURE_HOME/upstream" tag -f v9.3.0 "$MOVE_TAG_TO" >/dev/null
    fi
    if [[ -n "${FETCH_WRONG_COMMIT:-}" ]]; then
        args=("$@")
        args[${#args[@]}-1]="$FETCH_WRONG_COMMIT"
        set -- "${args[@]}"
    fi
fi
exec "$FIXTURE_GIT" "$@"
""")

    def response(tag, target, **flags):
        (home / "latest.json").write_text(json.dumps(
            {"tag_name": tag, "target_commitish": target, "draft": False, "prerelease": False} | flags))

    def bootstrap(prefix, **kwargs):
        with (source / "install.sh").open() as script:
            return run("bash", "-s", "--", "--prefix", prefix, stdin=script, **kwargs)

    def selected(prefix):
        return (prefix / "lib/runweld/default").read_text().strip()

    def check_release(prefix, expected):
        release = selected(prefix)
        installed = prefix / "lib/runweld/releases" / release
        assert (installed / "README.md").read_text().strip() == expected, (
            f"distribution#published-install: expected {expected}, got {(installed / 'README.md').read_text().strip()}")
        assert run(prefix / "bin/runweld", "--version", "--verbose").splitlines()[-1] == f"Build ID: {release}"
        return release

    for name in ("workflow", "agents", "references", "adapters", "scripts", "docs", "bin"):
        shutil.copytree(source / name, upstream / name, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
    for name in ("install.sh", "LICENSE"):
        shutil.copy2(source / name, upstream / name)
    git("init", "-qb", "main")
    old_revision = commit("9.2.0", "previous working build")
    stable_revision = commit("9.3.0", "published stable build")
    git("tag", "-am", "published stable", "v9.3.0")
    prerelease_revision = commit("9.4.0-rc.1", "published prerelease build")
    git("tag", "v9.4.0-rc.1")
    main_revision = commit("9.3.0", "unpublished main build with same VERSION")
    stable_install, existing_install = home / "fresh prefix", home / "existing prefix"
    requests = home / "latest.requests"

    # The API can retain a branch name in target_commitish. The named tag selects the source.
    response("v9.3.0", "main")
    _, _, quickstart = (source / "README.md").read_text().partition("### Install\n")
    snippet = quickstart.split("```sh\n", 1)[1].split("```", 1)[0]
    readme_home = home / "README user"
    readme_home.mkdir()
    run("bash", "-c", snippet, settings={"HOME": str(readme_home)})
    assert not (home / "mutable-bootstrap").exists(), (
        "distribution#published-install: the README must not execute a bootstrap from mutable main")
    readme_release = check_release(readme_home / ".local", "published stable build")
    assert requests.read_text().count("\n") == 1
    bad_download = run("bash", "-c", snippet, settings={"HOME": str(readme_home), "FETCH_WRONG_COMMIT": main_revision}, ok=False)
    assert "Fetched a different commit" in bad_download
    response("v9.4.0-rc.1", prerelease_revision, prerelease=True)
    bad_release = run("bash", "-c", snippet, settings={"HOME": str(readme_home)}, ok=False)
    assert "published stable" in bad_release
    assert check_release(readme_home / ".local", "published stable build") == readme_release
    response("v9.3.0", "main")
    requests.unlink()
    bootstrap(stable_install)
    exact = check_release(stable_install, "published stable build")
    assert readme_release == exact
    assert requests.read_text().count("\n") == 1

    bootstrap(existing_install, settings={"RUNWELD_REF": old_revision})
    check_release(existing_install, "previous working build")
    cli = existing_install / "bin/runweld"
    assert requests.read_text().count("\n") == 1
    project = home / "project"
    project.mkdir()
    run(real_git, "init", "-qb", "main", cwd=project)
    run(real_git, "commit", "--allow-empty", "-qm", "base", cwd=project)
    run(stable_install / "bin/runweld", "onboard", "--apply", "--primary-provider", "Test", "--primary-model", "primary",
        "--secondary-provider", "Test", "--secondary-model", "secondary", "--no-setup", cwd=project)
    run(real_git, "add", ".", cwd=project)
    run(real_git, "commit", "-qm", "share setup", cwd=project)
    clone = home / "clone"
    run(real_git, "clone", "-q", project, clone)
    missing = run(cli, "next", cwd=clone, ok=False)
    assert exact in missing and "install this exact release" in missing, missing

    # The tag is authoritative even if GitHub has a different target_commitish on record.
    response("v9.3.0", main_revision)
    run(cli, "update", "--cli", settings={"MOVE_TAG_TO": main_revision})
    assert git("rev-parse", "refs/tags/v9.3.0") == main_revision
    assert check_release(existing_install, "published stable build") == exact
    assert requests.read_text().count("\n") == 2
    git("tag", "-fam", "published stable", "v9.3.0", stable_revision)

    store = existing_install / "lib/runweld"
    launcher_files = [cli, *(store / name for name in ("default", "route_pipeline.py", "runweld_release.py"))]
    snapshot = {path: path.read_bytes() for path in launcher_files}

    def refused(message, **kwargs):
        error = run(cli, "update", "--cli", ok=False, **kwargs)
        assert message in error, error
        assert snapshot == {path: path.read_bytes() for path in snapshot}
        assert check_release(existing_install, "published stable build") == exact

    (home / "latest.json").unlink()
    refused("latest stable release")
    (home / "latest.json").write_text("not JSON")
    refused("latest stable release")
    response("v9.4.0-rc.1", prerelease_revision, prerelease=True)
    refused("latest stable release")
    response("v9.3.0", stable_revision, draft=True)
    refused("latest stable release")
    response("v9.3.0", stable_revision)
    refused("published commit", settings={"FETCH_WRONG_COMMIT": main_revision})
    response("v9.3.1", "main")
    refused("v9.3.1")
    git("tag", "v9.3.1", main_revision)
    response("v9.3.1", main_revision)
    refused("VERSION")
    (upstream / "workflow/build/cli_help.py").unlink()
    damaged_revision = commit("9.3.2", "incomplete published source")
    git("tag", "v9.3.2")
    response("v9.3.2", damaged_revision)
    refused("missing terminal help")
    assert requests.read_text().count("\n") == 10

    run(cli, "update", "--cli", settings={"RUNWELD_REF": "refs/heads/main"}, ok=False)
    assert check_release(existing_install, "published stable build") == exact
    git("reset", "--hard", main_revision)
    run(cli, "update", "--cli", settings={"RUNWELD_REF": "refs/heads/main"})
    assert check_release(existing_install, "unpublished main build with same VERSION") != exact
    assert requests.read_text().count("\n") == 10
PY
