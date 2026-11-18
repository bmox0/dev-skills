#!/usr/bin/env python3
"""Validate and inventory the explicitly selected Qoder package without inference."""

import json
import shutil
import subprocess
import sys
from pathlib import Path


def main():
    root = Path(sys.argv[1]).resolve()
    client = shutil.which("qodercli")
    if not client:
        print("HOST qoder: 'qodercli' is not on PATH — cannot validate/load package", file=sys.stderr)
        return 1
    try:
        version = subprocess.run([client, "--version"], capture_output=True, text=True, timeout=120, check=True).stdout.strip()
        if not version:
            raise ValueError("qodercli --version returned no version")
        print(f"HOST qoder: manifest and loader inventory; {version}; role/model/live execution not checked", flush=True)
        result = subprocess.run([client, "plugin", "validate", "--json", str(root)],
                                capture_output=True, text=True, timeout=120, check=True)
        if json.loads(result.stdout).get("ok") is not True:
            raise ValueError("native manifest validation failed")
        result = subprocess.run([client, "plugin", "list", "--json", "--plugin-dir", str(root)],
                                cwd=root, capture_output=True, text=True, timeout=120, check=True)
        version = json.loads((root / ".qoder-plugin/plugin.json").read_text())["version"]
        plugin = next((p for p in json.loads(result.stdout)
                       if p.get("name") == "dev-skills" and p.get("enabled")
                       and Path(p.get("installPath", "")).resolve() == root), None)
        if not plugin or plugin.get("version") != version:
            raise ValueError("loader did not expose the selected package path/version")
        resources = plugin.get("resources", {})
        expected_skills = {p.parent.name for p in (root / "skills").glob("*/SKILL.md")}
        expected_agents = {f"dev-skills:{p.stem}" for p in (root / "agents").glob("*.md")}
        if {s["name"] for s in resources.get("skills", [])} != expected_skills:
            raise ValueError("loader skill inventory differs from package")
        if {a["name"] for a in resources.get("agents", [])} != expected_agents:
            raise ValueError("loader role inventory differs from package")
        if {h["event"] for h in resources.get("hooks", [])} != {"SessionStart", "PostToolUse"}:
            raise ValueError("loader advisory hook inventory differs from package")
        print(f"HOST qoder: loaded {root}; {len(expected_skills)} skills, {len(expected_agents)} roles, 2 advisory events")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        print(f"HOST qoder: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
