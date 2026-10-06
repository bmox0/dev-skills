#!/usr/bin/env bash
# Package fixtures exercise host-independent checks and Claude JSON reports.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"

fail() {
  echo "plugin.test.sh: $1" >&2
  exit 1
}

tree=$(mktemp_dir)
stub_dir=$(mktemp_dir)
no_claude=$(mktemp_dir)
ln -s "$(command -v python3)" "$no_claude/python3"

reset_tree() {
  python3 - "$tree" <<'PY'
import json, shutil, sys
from pathlib import Path
root = Path(sys.argv[1])
for child in root.iterdir():
    shutil.rmtree(child) if child.is_dir() else child.unlink()
interface = {
    "displayName": "dev-skills", "shortDescription": "Plan, build, review and finish",
    "longDescription": "A shared development workflow.", "developerName": "bmox0",
    "category": "Developer Tools", "capabilities": ["Read", "Write", "Interactive"],
    "defaultPrompt": "Build this change with dev-skills.",
    "websiteURL": "https://github.com/bmox0/dev-skills",
}
common = {"name": "dev-skills", "version": "4.3.0", "description": "A shared development workflow.",
          "author": {"name": "bmox0"}}
files = {
    "plugin.json": dict(common, **{"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
                                   "extensions": {"com.openai": {"interface": interface}}}),
    ".codex-plugin/plugin.json": dict(common, skills="./skills/", interface=interface),
    ".claude-plugin/plugin.json": common,
    ".claude-plugin/marketplace.json": {
        "name": "dev-skills", "owner": {"name": "bmox0"}, "metadata": {"version": "4.3.0"},
        "plugins": [{"name": "dev-skills", "source": "./", "version": "4.3.0"}],
    },
    ".agents/plugins/marketplace.json": {
        "name": "dev-skills", "plugins": [{"name": "dev-skills", "version": "4.3.0",
        "source": {"source": "local", "path": "./"}, "category": "Developer Tools",
        "policy": {"installation": "AVAILABLE", "authentication": "ON_USE"}}],
    },
}
for name, value in files.items():
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))
for name, model in (("implementer", "sonnet"), ("reviewer", "opus")):
    path = root / "agents" / (name + ".md")
    path.parent.mkdir(exist_ok=True)
    path.write_text(f"---\nname: {name}\ndescription: Shared role instructions\nmodel: {model}\n---\n\nBody.\n")
path = root / "skills/finish/SKILL.md"
path.parent.mkdir(parents=True)
path.write_text("---\nname: finish\ndescription: Finish an approved change\ndisable-model-invocation: true\n---\n\nBody.\n")
path = root / "skills/finish/agents/openai.yaml"
path.parent.mkdir()
path.write_text("policy:\n  allow_implicit_invocation: false\n")
(root / "references").mkdir()
(root / "references/RUNTIME.md").write_text(
    "| Role | Claude Code | Codex | Effort |\n|---|---|---|---|\n"
    "| Worker, implementer, targeted reviewer | Sonnet | Sol | high |\n"
    "| Initial reviewer | Opus | Sol | xhigh |\n"
)
(root / "CLAUDE.md").write_text("Repository development contract.\n")
PY
}

set_json() {
  python3 - "$tree/$1" "$2" "$3" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
value = json.loads(path.read_text())
parts = sys.argv[2].split("/")
cursor = value
for part in parts[:-1]:
    cursor = cursor[int(part)] if isinstance(cursor, list) else cursor[part]
key = int(parts[-1]) if isinstance(cursor, list) else parts[-1]
cursor[key] = json.loads(sys.argv[3])
path.write_text(json.dumps(value))
PY
}

run_check() {
  out=$(python3 "$repo_root/scripts/check-plugin.py" "$tree" --library-only 2>&1)
  rc=$?
}

expect_failure() {
  run_check
  assert_eq 1 "$rc" "$1 should fail" || fail "$1: $out"
  assert_contains "$out" "$2" "$1 should explain its finding" || fail "$1: $out"
}

reset_tree
run_check
assert_eq 0 "$rc" "a valid shared package passes without external validators" || fail "$out"

for source in .codex-plugin/plugin.json .claude-plugin/plugin.json; do
  reset_tree
  set_json "$source" version '"0.0.0"'
  expect_failure "version mismatch in $source" "$source: PLUGIN version"
done

for field in metadata/version plugins/0/version; do
  reset_tree
  set_json .claude-plugin/marketplace.json "$field" '"0.0.0"'
  expect_failure "Claude marketplace $field" ".claude-plugin/marketplace.json: PLUGIN"
done

reset_tree
set_json .agents/plugins/marketplace.json plugins/0/source/path '"./missing"'
expect_failure "missing native marketplace source" "plugins[0].source.path path './missing' is not a dir"

reset_tree
set_json .claude-plugin/marketplace.json plugins/0/source '"../"'
expect_failure "escaping Claude marketplace source" "plugins[0].source must stay inside the plugin root"

reset_tree
set_json .codex-plugin/plugin.json skills '"./missing"'
expect_failure "missing Codex skills resource" "skills path './missing' is not a dir"

for field in skills interface; do
  reset_tree
  set_json plugin.json "$field" '"unsupported"'
  expect_failure "unsupported portable field $field" "unsupported Agent Plugins field '$field'"
done

reset_tree
rm -r "$tree/skills"
expect_failure "missing portable-discovered resources" "automatically discovered skills path './skills' is not a dir"

reset_tree
set_json .codex-plugin/plugin.json skills '["./skills/", "./skills/"]'
expect_failure "duplicate skill exposure" "skills must expose the shared skills/ directory once"

reset_tree
set_json .codex-plugin/plugin.json interface/displayName '"other package"'
expect_failure "mismatched interface metadata" ".codex-plugin/plugin.json: PLUGIN interface is"

reset_tree
set_json plugin.json extensions/com.openai/interface/iconSmall '"./missing.png"'
expect_failure "missing interface asset" "interface.iconSmall path './missing.png' is not a file"

reset_tree
set_json .agents/plugins/marketplace.json plugins/0/policy/installation '"INSTALLED_BY_DEFAULT"'
expect_failure "native install policy" "policy.installation is"

reset_tree
set_json .agents/plugins/marketplace.json plugins/0/source/source '"url"'
expect_failure "native source type" "plugins[0].source.source is"

reset_tree
printf 'policy:\n  allow_implicit_invocation: true\n' > "$tree/skills/finish/agents/openai.yaml"
expect_failure "implicitly callable finish" "finish requires policy.allow_implicit_invocation: false"

reset_tree
printf '# policy:\n#   allow_implicit_invocation: false\n' > "$tree/skills/finish/agents/openai.yaml"
expect_failure "commented finish policy" "finish requires policy.allow_implicit_invocation: false"

reset_tree
printf 'policy:\n  allow_implicit_invocation: false\n  allow_implicit_invocation: "true"\n' > "$tree/skills/finish/agents/openai.yaml"
expect_failure "ambiguous finish policy" "finish requires policy.allow_implicit_invocation: false"

reset_tree
printf -- '---\nname: finish\ndescription: Finish changes\ndisable-model-invocation: false\n---\n\nBody.\n' > "$tree/skills/finish/SKILL.md"
expect_failure "implicitly callable Claude finish" "finish disable-model-invocation is"

reset_tree
printf -- '---\nname: finish\ndescription: Finish changes\ndisable-model-invocation: "true"\n---\n\nBody.\n' > "$tree/skills/finish/SKILL.md"
expect_failure "string-valued Claude policy" "finish disable-model-invocation is"

reset_tree
rm "$tree/skills/finish/agents/openai.yaml"
expect_failure "missing finish policy" "cannot read invocation policy"

reset_tree
printf '| Role | Claude Code | Codex | Effort |\n| Worker | Sonnet | Sol | high |\n| Reviewer | Opus | Sol | high |\n' > "$tree/references/RUNTIME.md"
expect_failure "incorrect full-review reasoning tier" "opus runtime mapping is"

reset_tree
printf -- '---\nname: reviewer\ndescription: Review changes\nmodel: sonnet\n---\n\nBody.\n' > "$tree/agents/reviewer.md"
expect_failure "wrong Claude role tier" "Claude compatibility model is ['sonnet'], expected ['opus']"

reset_tree
printf -- '---\nname: finish\n---\n\nBody.\n' > "$tree/skills/finish/SKILL.md"
expect_failure "missing skill description" "skills/finish/SKILL.md: FRONT no description"

reset_tree
mkdir "$tree/hooks"
expect_failure "unexpected hooks" "hooks: PLUGIN"

reset_tree
mkdir "$tree/skills/finish/scripts"
expect_failure "unexpected skill script directory" "skill script directories are not packaged"

# The stub checks actual argv and returns realistic strict-mode JSON. The
# allowed warning must not hide unrelated reports or an unexplained failure.
cat > "$stub_dir/claude" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
if len(sys.argv) != 6 or sys.argv[1:3] != ["plugin", "validate"] or sys.argv[4:] != ["--strict", "--json"]:
    sys.exit(2)
root = Path.cwd()
source = sys.argv[3]
with open(os.environ["CLAUDE_STUB_LOG"], "a") as log:
    log.write(source + "\n")
mode = os.environ["CLAUDE_STUB_CASE"]
if mode == "invalid-json":
    print("not JSON")
    sys.exit(1)
report = {"success": True, "strict": True, "manifest": {"file": str(root / source), "errors": [], "warnings": []}, "contents": []}
warning = {"path": "root", "message": "CLAUDE.md at the plugin root is not loaded as project context. To ship context with your plugin, use a skill (skills/<name>/SKILL.md) instead."}
item = {"file": str(root / "CLAUDE.md"), "errors": [], "warnings": [warning]}
rc = 0
if mode not in ("clean", "no-findings", "exit-error"):
    report["success"] = False
    report["contents"] = [item]
    rc = 1
if mode == "unknown-warning":
    item["warnings"].append({"path": "root", "message": "Another warning"})
elif mode == "wrong-file":
    item["file"] = str(root / "skills/finish/CLAUDE.md")
elif mode == "changed-warning":
    warning["message"] += " An unrelated problem."
elif mode == "with-error":
    item["errors"].append({"path": "name", "message": "Invalid name"})
elif mode == "no-findings":
    report["success"], rc = False, 1
elif mode == "exit-error":
    rc = 2
elif mode == "malformed":
    report["contents"] = "invalid"
print(json.dumps(report))
sys.exit(rc)
PY
chmod +x "$stub_dir/claude"

run_claude_check() {
  : > "$tree/validator.log"
  out=$(PATH="$stub_dir:$PATH" CLAUDE_STUB_CASE="$1" CLAUDE_STUB_LOG="$tree/validator.log" \
    python3 "$repo_root/scripts/check-plugin.py" "$tree" 2>&1)
  rc=$?
}

reset_tree
run_claude_check clean
assert_eq 0 "$rc" "clean Claude reports pass" || fail "$out"
calls=$(cat "$tree/validator.log")
assert_eq $'.claude-plugin/plugin.json\n.claude-plugin/marketplace.json' "$calls" \
  "both Claude manifests must be validated" || fail "both reports: $calls"

run_claude_check allowed-warning
assert_eq 0 "$rc" "a strict false report containing only the known warning passes" || fail "$out"

for mode in unknown-warning wrong-file changed-warning with-error no-findings exit-error malformed invalid-json; do
  run_claude_check "$mode"
  assert_eq 1 "$rc" "Claude report $mode must fail" || fail "$mode: $out"
done

out=$(PATH="$no_claude" "$no_claude/python3" "$repo_root/scripts/check-plugin.py" "$tree" 2>&1)
rc=$?
assert_eq 0 "$rc" "a Codex-only environment runs structural validation" || fail "$out"
assert_contains "$out" "skipped external validation ('claude' is not on PATH)" \
  "missing external validation must be reported as skipped" || fail "$out"

exit 0
