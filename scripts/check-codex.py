#!/usr/bin/env python3
"""Load the plugin the way Codex does, and read back what its model is shown.

Codex has no `plugin validate`. In a throwaway CODEX_HOME this adds the tree
as a local marketplace, installs dev-skills from it, and renders the
model-visible prompt with `codex debug prompt-input`. No model is called and
the user's own ~/.codex is never touched.

Findings, each a CODEX line:

  - `codex` is not on PATH, or the install or the render failed
  - the install did not land at plugins/cache/dev-skills/dev-skills/<version>,
    the version in .codex-plugin/plugin.json
  - a skill under skills/ is missing from Codex's skill list
  - an explicit-only skill (`disable-model-invocation: true`) is in that list:
    its agents/openai.yaml policy is missing or not honoured

Usage: scripts/check-codex.py [ROOT]
Exit:  0 no findings · 1 any finding
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PLUGIN = "dev-skills"
SELECTOR = "dev-skills@dev-skills"
LISTED_RE = re.compile(r"^- dev-skills:([a-z0-9][a-z0-9-]*):", re.MULTILINE)


def skills(root):
    """Every skill under skills/, and the ones Claude may not invoke itself."""
    names, explicit = set(), set()
    for skill_md in sorted((root / "skills").glob("*/SKILL.md")):
        name = skill_md.parent.name
        names.add(name)
        head = skill_md.read_text(encoding="utf-8").split("\n---", 1)[0]
        if re.search(r"^disable-model-invocation:\s*true\s*$", head, re.MULTILINE):
            explicit.add(name)
    return names, explicit


def run(args, env, cwd, findings):
    try:
        done = subprocess.run(args, env=env, cwd=cwd, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as exc:
        findings.append(f"`{' '.join(args)}`: {exc}")
        return None
    if done.returncode != 0:
        tail = (done.stderr or done.stdout).strip().splitlines()[-1:] or [""]
        findings.append(f"`{' '.join(args)}` exited {done.returncode}: {tail[0]}")
        return None
    return done.stdout


def listed(prompt_json):
    """The dev-skills skills named in the rendered skills list."""
    texts = []
    for item in json.loads(prompt_json):
        for part in item.get("content") or []:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                texts.append(part["text"])
    block = next((t for t in texts if "<skills_instructions>" in t), "")
    return set(LISTED_RE.findall(block))


def check(root, findings):
    codex = shutil.which("codex")
    if not codex:
        findings.append("'codex' is not on PATH — cannot load the plugin the way Codex does")
        return
    try:
        version = json.loads((root / ".codex-plugin" / "plugin.json").read_text(encoding="utf-8"))["version"]
    except (OSError, ValueError, KeyError) as exc:
        findings.append(f".codex-plugin/plugin.json: no version: {exc}")
        return
    names, explicit = skills(root)

    with tempfile.TemporaryDirectory(prefix="check-codex-") as tmp:
        home, project = Path(tmp, "home"), Path(tmp, "project")
        home.mkdir()
        project.mkdir()
        env = dict(os.environ, CODEX_HOME=str(home))
        if run([codex, "plugin", "marketplace", "add", str(root)], env, tmp, findings) is None:
            return
        if run([codex, "plugin", "add", SELECTOR], env, tmp, findings) is None:
            return
        installed = home / "plugins" / "cache" / PLUGIN / PLUGIN / version
        if not installed.is_dir():
            findings.append(f"the install is not at {installed.relative_to(home)}")
        prompt = run([codex, "debug", "prompt-input", "hello"], env, project, findings)
        if prompt is None:
            return
        try:
            shown = listed(prompt)
        except (ValueError, AttributeError) as exc:
            findings.append(f"`codex debug prompt-input` returned no prompt list: {exc}")
            return

    for name in sorted(names - explicit - shown):
        findings.append(f"skills/{name}: Codex does not list it")
    for name in sorted(explicit & shown):
        findings.append(f"skills/{name}: explicit-only, yet Codex offers it to the model")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent).resolve()
    findings = []
    check(root, findings)
    for finding in findings:
        print(f"CODEX: {finding}")
    print(f"CODEX: {len(findings)} finding{'' if len(findings) == 1 else 's'}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
