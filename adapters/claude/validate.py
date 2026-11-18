#!/usr/bin/env python3
"""Validate Claude Code manifests with the explicitly selected native client."""

import shutil
import subprocess
import sys
from pathlib import Path


def main():
    root = Path(sys.argv[1]).resolve()
    client = shutil.which("claude")
    if not client:
        print("HOST claude: 'claude' is not on PATH — cannot validate manifests", file=sys.stderr)
        return 1
    try:
        version = subprocess.run([client, "--version"], cwd=root, capture_output=True, text=True, timeout=120)
        if version.returncode or not version.stdout.strip():
            print("HOST claude: cannot read required 'claude --version'", file=sys.stderr)
            return 1
        print(f"HOST claude: manifest validation; {version.stdout.strip()}; loader/live execution not checked", flush=True)
        status = 0
        for target in (".", ".claude-plugin/plugin.json"):
            if subprocess.run([client, "plugin", "validate", target, "--strict"], cwd=root, timeout=120).returncode:
                status = 1
        return status
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"HOST claude: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
