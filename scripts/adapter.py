"""Resolve explicitly selected adapter files inside this package."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def adapter_path(name, filename):
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
        raise ValueError(f"unsafe adapter name {name!r}; use lowercase letters, digits and hyphens")
    root = (ROOT / "adapters").resolve()
    path = root / name / filename
    if not path.resolve().is_relative_to(root):
        raise ValueError(f"adapter {name!r} resolves outside adapters/")
    if not path.is_file():
        raise ValueError(f"adapter {name!r} has no {filename}; install an adapter with that capability")
    return path
