#!/usr/bin/env python3
"""Translate Claude-compatible native hook payloads into normalized advice."""

import json
import os
import re
import sys

from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
from advise import advice

PATCH_PATH = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+?)\s*$|^\*\*\* Move to: (.+?)\s*$", re.M)


def normalize(data):
    if not isinstance(data, dict):
        return None
    cwd = data.get("cwd") or os.getcwd()
    event = data.get("hook_event_name")
    if event == "SessionStart" and data.get("source") in ("startup", "resume", "compact"):
        return {"event": "session_start", "cwd": cwd}
    if event != "PostToolUse" or data.get("tool_name") not in ("Write", "Edit", "MultiEdit", "apply_patch"):
        return None
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    paths = [tool_input[k] for k in ("file_path", "path", "notebook_path") if isinstance(tool_input.get(k), str)]
    for value in tool_input.values():
        if isinstance(value, str):
            paths += [a or b for a, b in PATCH_PATH.findall(value)]
    return {"event": "edit", "cwd": cwd, "paths": paths}


def main():
    data = json.load(sys.stdin)
    text = advice(normalize(data))
    if text:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": data["hook_event_name"], "additionalContext": text}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
