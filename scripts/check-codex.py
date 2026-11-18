#!/usr/bin/env python3
"""Compatibility entrypoint for the explicit Codex loader validator."""

import runpy
from pathlib import Path


if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).resolve().parent.parent / "adapters/codex/validate.py"), run_name="__main__")
