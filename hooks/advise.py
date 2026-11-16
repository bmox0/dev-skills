#!/usr/bin/env python3
"""Advisory hooks for Claude Code and Codex: reads the host's hook input on
stdin and, when it has something to say, prints `additionalContext` for the
model. Every fact comes from skills/build/pipeline.py; this file knows only
which file of a plan is which. It never blocks and always exits 0: any
failure prints nothing.
"""

import json
import os
import re
import subprocess
import sys

CLI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skills", "build", "pipeline.py")
PATCH_PATH = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+?)\s*$|^\*\*\* Move to: (.+?)\s*$", re.M)

NOTES = ("`.notes.md` is rendered from the state: `pipeline.py note add|edit|drop` writes it, "
         "and the next write replaces a hand edit.")
JUDGE = ("`.judge.md` is written by code once, from the first verdict (`pipeline.py verdict`); "
         "a hand edit is not read.")
STATE = "The state changes only through `pipeline.py` commands; a hand edit is drift that later writes refuse."


def cli(*args, cwd):
    done = subprocess.run([sys.executable, "-B", CLI, *args], cwd=cwd, capture_output=True, text=True, timeout=30)
    return done.stdout if done.returncode == 0 else ""


def edited_paths(tool_input, cwd):
    """File paths an edit tool or a Codex patch touched."""
    paths = []
    for key in ("file_path", "path", "notebook_path"):
        if isinstance(tool_input.get(key), str):
            paths.append(tool_input[key])
    for value in tool_input.values():
        if isinstance(value, str):
            paths += [a or b for a, b in PATCH_PATH.findall(value)]
    return [os.path.normpath(os.path.join(cwd, p)) for p in paths]


def plan_advice(path):
    """-> advice for an edit of one file of a compiled plan, or ''."""
    d, name = os.path.split(path)
    if os.path.basename(d) != "plans" or os.path.basename(os.path.dirname(d)) != ".ai-workflow":
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


def session_start(cwd):
    rows = json.loads(cli("status", "--json", cwd=cwd) or "[]")
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd, capture_output=True, text=True).stdout.strip()
    listing = cli("status", cwd=cwd).splitlines()
    out = [next((l for l in listing if l.startswith(r["plan"] + " — ")), "") if not r.get("status")
           else cli("status", os.path.join(root, ".ai-workflow", "plans", r["plan"] + ".md"), cwd=cwd).rstrip()
           for r in rows]
    return "\n\n".join(t for t in out if t)


def main():
    data = json.load(sys.stdin)
    cwd = data.get("cwd") or os.getcwd()
    if data.get("hook_event_name") == "SessionStart":
        text, event = session_start(cwd), "SessionStart"
    else:
        tool_input = data.get("tool_input")
        text = "\n".join(a for p in edited_paths(tool_input, cwd) if (a := plan_advice(p))) if isinstance(tool_input, dict) else ""
        event = "PostToolUse"
    if text:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
