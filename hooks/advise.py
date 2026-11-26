#!/usr/bin/env python3
"""Fail-open workflow advice from normalized {event, cwd, paths} JSON on stdin.
Print plain advice; native adapters own event translation and output envelopes.
"""

import json
import os
import re
import subprocess
import sys

CLI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skills", "build", "pipeline.py")

NOTES = ("`.notes.md` is rendered from the state: `pipeline.py note add|edit|drop` writes it, "
         "and the next write replaces a hand edit.")
JUDGE = ("`.judge.md` is written by code once, from the first verdict (`pipeline.py verdict`); "
         "a hand edit is not read.")
STATE = "The state changes only through `pipeline.py` commands; a hand edit is drift that later writes refuse."


def cli(*args, cwd):
    done = subprocess.run([sys.executable, "-B", CLI, *args], cwd=cwd, capture_output=True, text=True, timeout=30)
    return done.stdout if done.returncode == 0 else ""


def plan_advice(path):
    """-> advice for an edit of one file of a compiled plan, or ''."""
    d, name = os.path.split(os.path.join(os.path.realpath(os.path.dirname(path)), os.path.basename(path)))
    history = os.path.dirname(d)
    if os.path.basename(d) != "plans" or not history.endswith(os.sep + os.path.join(".runweld", "workflow")):
        return ""
    for suffix, text in ((".notes.md", NOTES), (".judge.md", JUDGE), (".json", STATE), (".md", None)):
        if name.endswith(suffix) and not (suffix == ".md" and re.search(r"\.(notes|judge)\.md$", name)):
            slug = name[: -len(suffix)]
            break
    else:
        return ""
    if not os.path.isfile(os.path.join(d, slug + ".json")):
        return ""
    if text:
        return text
    drift = json.loads(cli("status", path, "--json", cwd=d) or "{}").get("drift") or []
    return "\n".join(drift)


def advice(data):
    if not isinstance(data, dict):
        return ""
    cwd = data.get("cwd")
    if not isinstance(cwd, str) or not cwd.strip():
        return ""
    if data.get("event") == "session_start":
        return cli("status", "--current", cwd=cwd).rstrip()
    paths = data.get("paths")
    if data.get("event") != "edit" or not isinstance(paths, list) or not all(isinstance(p, str) and p for p in paths):
        return ""
    return "\n".join(a for p in dict.fromkeys(paths) if (a := plan_advice(os.path.normpath(os.path.join(cwd, p)))))


def main():
    text = advice(json.load(sys.stdin))
    if text:
        print(text)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
