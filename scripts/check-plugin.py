#!/usr/bin/env python3
"""Validate the shared Claude Code/Codex package without external libraries.

Usage: scripts/check-plugin.py [ROOT] [--library-only]

The structural checks always run. Unless --library-only is given, Claude's
validator also checks both Claude manifests when available. Its only permitted
warning is the repository's own root CLAUDE.md development contract. Codex has
no plugin-validation CLI; its manifest and marketplace are checked here.
"""

import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


PORTABLE_SCHEMA = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
PORTABLE_FIELDS = {
    "$schema", "name", "version", "description", "author", "homepage",
    "repository", "license", "keywords", "extensions",
}
CLAUDE_CONTEXT_WARNING = (
    "CLAUDE.md at the plugin root is not loaded as project context. "
    "To ship context with your plugin, use a skill (skills/<name>/SKILL.md) instead."
)


def frontmatter_scalars(text, key):
    """Read one scalar key's occurrences in the existing flat frontmatter."""
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return []
    try:
        end = lines.index("---", 1)
    except ValueError:
        return []
    values = []
    for line in lines[1:end]:
        match = re.fullmatch(re.escape(key) + r":\s*(.*)", line)
        if not match:
            continue
        value = match[1].strip()
        if value.startswith('"'):
            try:
                value, remainder = json.JSONDecoder().raw_decode(value)
                if remainder < len(match[1].strip()) and not match[1].strip()[remainder:].lstrip().startswith("#"):
                    value = None
            except ValueError:
                value = None
        elif value.startswith("'"):
            quoted = re.fullmatch(r"'((?:[^']|'')*)'\s*(?:#.*)?", value)
            value = quoted[1].replace("''", "'") if quoted else None
        else:
            value = value.split(" #", 1)[0].rstrip()
            if value in ("true", "false"):
                value = value == "true"
        values.append(value)
    return values


class PackageCheck:
    def __init__(self, root):
        self.root = root.resolve()
        self.findings = []

    def fail(self, source, message):
        self.findings.append(f"{source}: PLUGIN {message}")

    def read_json(self, source):
        try:
            value = json.loads((self.root / source).read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            self.fail(source, f"cannot read JSON: {exc}")
            return {}
        if not isinstance(value, dict):
            self.fail(source, "expected a JSON object")
            return {}
        return value

    def text(self, source, value, field):
        if not isinstance(value, str) or not value.strip():
            self.fail(source, f"{field} must be a nonempty string")
            return False
        return True

    def equal(self, source, actual, expected, field):
        if actual != expected:
            self.fail(source, f"{field} is {actual!r}, expected {expected!r}")

    def local_path(self, source, value, field, kind="dir"):
        if not self.text(source, value, field):
            return None
        path = (self.root / value).resolve()
        if Path(value).is_absolute() or not path.is_relative_to(self.root):
            self.fail(source, f"{field} must stay inside the plugin root")
            return None
        exists = path.is_dir() if kind == "dir" else path.is_file()
        if not exists:
            self.fail(source, f"{field} path {value!r} is not a {kind}")
            return None
        return path

    def skills_path(self, source, value):
        paths = value if isinstance(value, list) else [value]
        if not paths:
            self.fail(source, "skills must expose the shared skills/ directory")
        resolved = [self.local_path(source, p, "skills") for p in paths]
        if resolved != [self.root / "skills"]:
            self.fail(source, "skills must expose the shared skills/ directory once")

    def interface(self, source, value):
        if not isinstance(value, dict):
            self.fail(source, "interface must be an object")
            return
        for field in ("displayName", "shortDescription", "longDescription",
                      "developerName", "category", "defaultPrompt", "websiteURL"):
            self.text(source, value.get(field), f"interface.{field}")
        capabilities = value.get("capabilities")
        if not isinstance(capabilities, list) or not capabilities or any(
            item not in ("Read", "Write", "Interactive") for item in capabilities
        ):
            self.fail(source, "interface.capabilities must name Read, Write or Interactive")
        for field in ("icon", "iconSmall", "iconLarge", "logo"):
            if field in value:
                self.local_path(source, value[field], f"interface.{field}", "file")
        if "screenshots" in value:
            screenshots = value["screenshots"]
            if not isinstance(screenshots, list):
                self.fail(source, "interface.screenshots must be an array of file paths")
            else:
                for path in screenshots:
                    self.local_path(source, path, "interface.screenshots", "file")

    def marketplace_entry(self, source, manifest):
        self.equal(source, manifest.get("name"), "dev-skills", "name")
        entries = manifest.get("plugins")
        if not isinstance(entries, list) or len(entries) != 1 or not isinstance(entries[0], dict):
            self.fail(source, "plugins must contain exactly one dev-skills entry")
            return {}
        self.equal(source, entries[0].get("name"), "dev-skills", "plugins[0].name")
        return entries[0]

    def manifests(self):
        portable_source = "plugin.json"
        codex_source = ".codex-plugin/plugin.json"
        claude_source = ".claude-plugin/plugin.json"
        portable = self.read_json(portable_source)
        codex = self.read_json(codex_source)
        claude = self.read_json(claude_source)
        version = portable.get("version")
        if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][\w.-]+)?", version):
            self.fail(portable_source, "version must be a semantic version")
        for source, manifest in ((portable_source, portable), (codex_source, codex), (claude_source, claude)):
            self.equal(source, manifest.get("name"), "dev-skills", "name")
            self.equal(source, manifest.get("version"), version, "version")
            self.text(source, manifest.get("description"), "description")
            author = manifest.get("author")
            if not isinstance(author, dict):
                self.fail(source, "author must be an object with a name")
            else:
                self.text(source, author.get("name"), "author.name")
        self.equal(portable_source, portable.get("$schema"), PORTABLE_SCHEMA, "$schema")
        for field in sorted(set(portable) - PORTABLE_FIELDS):
            self.fail(portable_source, f"unsupported Agent Plugins field {field!r}")
        # The portable schema discovers ./skills automatically. A `skills`
        # field belongs only to the Codex compatibility manifest.
        self.local_path(portable_source, "./skills", "automatically discovered skills")
        self.skills_path(codex_source, codex.get("skills"))
        for source, manifest in ((portable_source, portable), (codex_source, codex), (claude_source, claude)):
            for field in ("hooks", "mcpServers"):
                if field in manifest:
                    self.fail(source, f"{field} is outside the skills-and-roles package")
        if "skills" in claude:
            self.skills_path(claude_source, claude["skills"])
        extensions = portable.get("extensions") or {}
        openai = extensions.get("com.openai") if isinstance(extensions, dict) else None
        portable_interface = openai.get("interface") if isinstance(openai, dict) else None
        self.interface(portable_source, portable_interface)
        self.interface(codex_source, codex.get("interface"))
        self.equal(codex_source, codex.get("interface"), portable_interface, "interface")

        claude_market_source = ".claude-plugin/marketplace.json"
        claude_market = self.read_json(claude_market_source)
        claude_entry = self.marketplace_entry(claude_market_source, claude_market)
        metadata = claude_market.get("metadata") or {}
        self.equal(claude_market_source, metadata.get("version") if isinstance(metadata, dict) else None,
                   version, "metadata.version")
        self.equal(claude_market_source, claude_entry.get("version"), version, "plugins[0].version")
        local = self.local_path(claude_market_source, claude_entry.get("source"), "plugins[0].source")
        self.equal(claude_market_source, local, self.root, "plugins[0].source root")

        codex_market_source = ".agents/plugins/marketplace.json"
        codex_market = self.read_json(codex_market_source)
        codex_entry = self.marketplace_entry(codex_market_source, codex_market)
        if "version" in codex_entry:
            self.equal(codex_market_source, codex_entry["version"], version, "plugins[0].version")
        source = codex_entry.get("source") or {}
        if not isinstance(source, dict):
            self.fail(codex_market_source, "plugins[0].source must be a local-source object")
            source = {}
        self.equal(codex_market_source, source.get("source"), "local", "plugins[0].source.source")
        local = self.local_path(codex_market_source, source.get("path"), "plugins[0].source.path")
        self.equal(codex_market_source, local, self.root, "plugins[0].source root")
        policy = codex_entry.get("policy") or {}
        if not isinstance(policy, dict):
            self.fail(codex_market_source, "plugins[0].policy must be an object")
            policy = {}
        self.equal(codex_market_source, policy.get("installation"), "AVAILABLE", "policy.installation")
        self.equal(codex_market_source, policy.get("authentication"), "ON_USE", "policy.authentication")
        self.equal(codex_market_source, codex_entry.get("category"), "Developer Tools", "plugins[0].category")

    def metadata(self):
        # Reuse the existing frontmatter checker rather than maintain a second
        # YAML dialect. It accepts the skill/agent metadata this package uses.
        spec = importlib.util.spec_from_file_location("check_links", Path(__file__).with_name("check-links.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.REPO_ROOT = self.root
        module.SKILLS_DIR = self.root / "skills"
        module.AGENTS_DIR = self.root / "agents"
        findings = {"FRONT": []}
        module.check_frontmatters(findings)
        self.findings.extend(findings["FRONT"])
        if not list((self.root / "skills").glob("*/SKILL.md")):
            self.fail("skills", "no packaged skills")
        for role, model in (("implementer", "sonnet"), ("reviewer", "opus")):
            source = f"agents/{role}.md"
            try:
                text = (self.root / source).read_text(encoding="utf-8")
            except OSError as exc:
                self.fail(source, f"cannot read role instructions: {exc}")
                continue
            models = frontmatter_scalars(text, "model")
            self.equal(source, models, [model], "Claude compatibility model")
        for source in ("hooks",):
            if (self.root / source).exists():
                self.fail(source, "the package ships skills and role instructions only")
        for path in (self.root / "skills").rglob("scripts"):
            if path.is_dir():
                self.fail(path.relative_to(self.root), "skill script directories are not packaged")

    def invocation_policy(self):
        claude_source = "skills/finish/SKILL.md"
        try:
            text = (self.root / claude_source).read_text(encoding="utf-8")
        except OSError as exc:
            self.fail(claude_source, f"cannot read finish instructions: {exc}")
            text = ""
        flags = frontmatter_scalars(text, "disable-model-invocation")
        self.equal(claude_source, flags, [True], "finish disable-model-invocation")
        source = "skills/finish/agents/openai.yaml"
        try:
            lines = (self.root / source).read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            self.fail(source, f"cannot read invocation policy: {exc}")
            return
        # This is deliberately a small parser for a scalar bool under policy,
        # not a permissive search that could accept a commented/nested policy.
        policies = 0
        values = []
        under_policy = False
        for line in lines:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if line == "policy:":
                policies += 1
                under_policy = True
            elif not line.startswith(" "):
                under_policy = False
            elif under_policy:
                match = re.fullmatch(r"  allow_implicit_invocation:\s*(false|true)\s*(?:#.*)?", line)
                if match:
                    values.append(match[1])
                elif "allow_implicit_invocation" in line:
                    values.append("invalid")
        if policies != 1 or values != ["false"]:
            self.fail(source, "finish requires policy.allow_implicit_invocation: false")

    def runtime_models(self):
        source = "references/RUNTIME.md"
        try:
            text = (self.root / source).read_text(encoding="utf-8")
        except OSError as exc:
            self.fail(source, f"cannot read shared runtime instructions: {exc}")
            return
        mappings = {"sonnet": [], "opus": []}
        for line in text.splitlines():
            if not line.startswith("|"):
                continue
            cells = [cell.strip().strip("`").casefold() for cell in line.strip("|").split("|")]
            for model in mappings:
                if model in cells:
                    index = cells.index(model)
                    mappings[model].append(cells[index + 1:index + 3])
        for model, effort in (("sonnet", "high"), ("opus", "xhigh")):
            self.equal(source, mappings[model], [["sol", effort]], f"{model} runtime mapping")

    def claude_report(self, source, report, returncode):
        if not isinstance(report, dict) or type(report.get("success")) is not bool:
            self.fail(source, "Claude validator returned an invalid success report")
            return
        manifest, contents = report.get("manifest"), report.get("contents")
        if not isinstance(manifest, dict) or not isinstance(contents, list):
            self.fail(source, "Claude validator report lacks manifest/contents")
            return
        allowed = 0
        rejected = 0
        for item in [report, manifest] + contents:
            if not isinstance(item, dict):
                self.fail(source, "Claude validator returned a malformed finding group")
                rejected += 1
                continue
            for kind in ("errors", "warnings"):
                findings = item.get(kind, [])
                if not isinstance(findings, list):
                    self.fail(source, f"Claude validator {kind} must be an array")
                    rejected += 1
                    continue
                for finding in findings:
                    if (kind == "warnings" and isinstance(finding, dict)
                            and item.get("file") == str(self.root / "CLAUDE.md")
                            and finding.get("path") == "root"
                            and finding.get("message") == CLAUDE_CONTEXT_WARNING):
                        allowed += 1
                        continue
                    message = finding.get("message") if isinstance(finding, dict) else finding
                    self.fail(source, f"Claude validator {kind}: {message}")
                    rejected += 1
        if not rejected:
            # Strict mode reports success=false and exit 1 for the permitted
            # warning. No other unexplained failure or process exit is green.
            if not report["success"] and not allowed:
                self.fail(source, "Claude validator failed without an allowed warning")
            elif returncode not in (0, 1) or (returncode != 0 and not allowed):
                self.fail(source, f"Claude validator exited {returncode}")
            elif report["success"] and returncode != 0:
                self.fail(source, "Claude validator success disagrees with its exit code")
        print(f"CLAUDE: {source}: {allowed} permitted root-context warning(s)")

    def claude(self):
        executable = shutil.which("claude")
        if not executable:
            print("CLAUDE: skipped external validation ('claude' is not on PATH); structural checks ran")
            return
        for source in (".claude-plugin/plugin.json", ".claude-plugin/marketplace.json"):
            try:
                result = subprocess.run(
                    [executable, "plugin", "validate", source, "--strict", "--json"],
                    cwd=self.root, capture_output=True, text=True, timeout=30,
                )
                report = json.loads(result.stdout)
            except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
                self.fail(source, f"Claude validator did not return a JSON report: {exc}")
                continue
            self.claude_report(source, report, result.returncode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--library-only", action="store_true", help="run only the standard-library checks")
    args = parser.parse_args()
    check = PackageCheck(args.root)
    check.manifests()
    check.metadata()
    check.invocation_policy()
    check.runtime_models()
    if not args.library_only:
        check.claude()
    for finding in check.findings:
        print(finding)
    print(f"PLUGIN: {len(check.findings)} finding(s)")
    return 1 if check.findings else 0


if __name__ == "__main__":
    sys.exit(main())
