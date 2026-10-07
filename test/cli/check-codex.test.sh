#!/usr/bin/env bash
# Pins scripts/check-codex.py against a stub codex, so the suite needs no
# Codex install: what the stub lists is what the check must judge. The real
# codex runs in scripts/check.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"

fail() {
  echo "check-codex.test.sh: $1" >&2
  exit 1
}

tree=$(mktemp_dir)
stub_bin=$(mktemp_dir)
mkdir -p "$tree/.codex-plugin" "$tree/skills/plan" "$tree/skills/finish"
printf '{"name": "dev-skills", "version": "1.2.0"}\n' > "$tree/.codex-plugin/plugin.json"
printf -- '---\nname: plan\ndescription: Plan a change.\n---\n\nBody.\n' > "$tree/skills/plan/SKILL.md"
printf -- '---\nname: finish\ndescription: Land it.\ndisable-model-invocation: true\n---\n\nBody.\n' \
  > "$tree/skills/finish/SKILL.md"

cat > "$stub_bin/codex" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if args[:3] == ["plugin", "marketplace", "add"]:
    sys.exit(int(os.environ.get("STUB_ADD_RC", "0")))
if args[:2] == ["plugin", "add"]:
    version = os.environ.get("STUB_VERSION", "1.2.0")
    Path(os.environ["CODEX_HOME"], "plugins/cache/dev-skills/dev-skills", version).mkdir(parents=True)
    sys.exit(0)
if args[:2] == ["debug", "prompt-input"]:
    lines = "".join(f"- dev-skills:{s}: about it. (file: r2/{s}/SKILL.md)\n" for s in os.environ["STUB_SKILLS"].split())
    text = "<skills_instructions>\n### Available skills\n" + lines + "</skills_instructions>"
    print(json.dumps([{"type": "message", "role": "developer", "content": [{"type": "input_text", "text": text}]}]))
    sys.exit(0)
sys.exit(2)
PY
chmod +x "$stub_bin/codex"

check() {
  out=$(PATH="$stub_bin:$PATH" "$@" python3 "$repo_root/scripts/check-codex.py" "$tree" 2>&1)
  rc=$?
}

check env STUB_SKILLS="plan"
assert_eq 0 "$rc" "a listed skill and a hidden explicit-only one pass" || fail "$out"

check env STUB_SKILLS="plan finish"
assert_eq 1 "$rc" "an explicit-only skill in the list fails" || fail "$out"
assert_contains "$out" "skills/finish: explicit-only, yet Codex offers it to the model" \
  "the finding names the skill Codex should not offer" || fail "$out"

check env STUB_SKILLS=""
assert_eq 1 "$rc" "a skill missing from the list fails" || fail "$out"
assert_contains "$out" "skills/plan: Codex does not list it" "the finding names the missing skill" || fail "$out"

check env STUB_SKILLS="plan" STUB_VERSION="1.1.0"
assert_eq 1 "$rc" "an install at another version fails" || fail "$out"
assert_contains "$out" "plugins/cache/dev-skills/dev-skills/1.2.0" "the finding names where it should be" || fail "$out"

check env STUB_SKILLS="plan" STUB_ADD_RC=1
assert_eq 1 "$rc" "a failed marketplace add fails" || fail "$out"

no_codex=$(mktemp_dir)
ln -s "$(command -v python3)" "$no_codex/python3"
out=$(PATH="$no_codex" "$no_codex/python3" "$repo_root/scripts/check-codex.py" "$tree" 2>&1)
rc=$?
assert_eq 1 "$rc" "a check that cannot reach codex fails, never passes" || fail "$out"
assert_contains "$out" "'codex' is not on PATH" "the finding says codex is missing" || fail "$out"

exit 0
