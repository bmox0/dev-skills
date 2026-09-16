#!/usr/bin/env bash
# Pins skills/setup/scripts/install-codex-agents: TC-12 through TC-15. The
# generator self-locates from its own real path in this repository (the way
# hooks/session-start does), so every run below only overrides HOME — never
# the source agents/*.md it reads, which stay this checkout's own.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

gen="$repo_root/skills/setup/scripts/install-codex-agents"

fail() {
  echo "install-codex-agents.test.sh: $1" >&2
  exit 1
}

sha256_file() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}

# run_gen HOME_DIR [CODEX_HOME_DIR] — sets $out and $rc. CODEX_HOME is
# passed through only when given, and explicitly unset otherwise so every
# existing single-arg call is insulated from whatever CODEX_HOME happens to
# be ambient — mirroring harness-ready.test.sh's own run_ready helper.
run_gen() {
  local home="$1" codex_home="${2:-}"
  if [ -n "$codex_home" ]; then
    out=$(HOME="$home" CODEX_HOME="$codex_home" "$gen" 2>&1)
  else
    out=$(HOME="$home" env -u CODEX_HOME "$gen" 2>&1)
  fi
  rc=$?
}

roles="gate-a gate-b implementer prototyper test-writer"

# --- TC-12: a fresh HOME gets all five roles, each correctly shaped -------

home1=$(mktemp_dir)
run_gen "$home1"

count=$(find "$home1/.codex/agents" -type f -name 'dev-skills-*.toml' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "5" "$count" "TC-12: expected exactly five generated role files, found $count" || fail "TC-12 count"

for role in $roles; do
  f="$home1/.codex/agents/dev-skills-$role.toml"
  [ -f "$f" ] || fail "TC-12: dev-skills-$role.toml was not created"

  expected_hash=$(sha256_file "$repo_root/agents/$role.md")
  first_line=$(head -1 "$f")
  assert_eq "# dev-skills:generated source=agents/$role.md sha256=$expected_hash" "$first_line" \
    "TC-12: $role's ownership marker (first line)" || fail "TC-12 marker $role"

  grep -qE '^name[[:space:]]*=.*dev-skills-'"$role" "$f" \
    || fail "TC-12: $role's generated file has no name field naming dev-skills-$role"

  src_desc=$(awk '
    /^---$/ { c++; next }
    c == 1 && /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }
  ' "$repo_root/agents/$role.md")
  # A YAML frontmatter description may be quoted; the raw source text is
  # compared here, so strip a matching pair of surrounding quotes the way a
  # YAML reader would, before searching for it verbatim in the generated file.
  case "$src_desc" in
    \"*\") src_desc="${src_desc#\"}"; src_desc="${src_desc%\"}" ;;
  esac
  grep -qF -- "$src_desc" "$f" \
    || fail "TC-12: $role's description text is not present verbatim in the generated file"

  grep -q 'developer_instructions' "$f" || fail "TC-12: $role's generated file has no developer_instructions"

  if grep -qE '^model[[:space:]]*=' "$f"; then
    fail "TC-12: $role's generated file writes a model key, and the plan says model is never written"
  fi

  if [ "$role" != "implementer" ] && grep -qF '# dev-skills:embedded' "$f"; then
    fail "TC-12: $role's generated file carries the embedded-TDD marker, which is reserved for the implementer role"
  fi
done

# --- TC-13: a same-named file without the ownership marker is refused -----

home2=$(mktemp_dir)
mkdir -p "$home2/.codex/agents"
conflict="$home2/.codex/agents/dev-skills-gate-a.toml"
printf 'not ours\nname = "someone-elses-gate-a"\n' > "$conflict"
before_sum=$(sha256_file "$conflict")

run_gen "$home2"

after_sum=$(sha256_file "$conflict")
assert_eq "$before_sum" "$after_sum" \
  "TC-13: a dev-skills-gate-a.toml without the ownership marker must be left byte-identical" \
  || fail "TC-13 unchanged"
assert_contains "$out" "dev-skills-gate-a.toml" \
  "TC-13: the refusal should name the conflicting file, got: $out" \
  || fail "TC-13 named"

# --- TC-14: a marked file whose source role no longer exists is removed ---

home3=$(mktemp_dir)
mkdir -p "$home3/.codex/agents"
ghost="$home3/.codex/agents/dev-skills-ghost.toml"
{
  echo "# dev-skills:generated source=agents/ghost.md sha256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  echo 'name = "dev-skills-ghost"'
  echo 'description = "a role that used to exist"'
  echo 'developer_instructions = """stale"""'
} > "$ghost"

run_gen "$home3"

[ -f "$ghost" ] && fail "TC-14: dev-skills-ghost.toml carries the marker for a role that no longer exists under agents/, and should have been removed"
assert_contains "$out" "dev-skills-ghost.toml" \
  "TC-14: the removal should be reported by name, got: $out" \
  || fail "TC-14 reported"

# --- TC-15: the implementer role embeds the whole of skills/tdd/SKILL.md --

home4=$(mktemp_dir)
run_gen "$home4"
impl="$home4/.codex/agents/dev-skills-implementer.toml"
[ -f "$impl" ] || fail "TC-15: dev-skills-implementer.toml was not generated"

tdd_hash=$(sha256_file "$repo_root/skills/tdd/SKILL.md")
grep -qF "# dev-skills:embedded source=skills/tdd/SKILL.md sha256=$tdd_hash" "$impl" \
  || fail "TC-15: the embedded-TDD marker, carrying skills/tdd/SKILL.md's own hash, is missing"

if ! python3 - "$impl" "$repo_root/skills/tdd/SKILL.md" <<'PY'
import sys
gen = open(sys.argv[1], encoding="utf-8").read()
tdd = open(sys.argv[2], encoding="utf-8").read()
sys.exit(0 if tdd in gen else 1)
PY
then
  fail "TC-15: the whole of skills/tdd/SKILL.md is not embedded verbatim in dev-skills-implementer.toml"
fi

# --- CODEX_HOME end-to-end: the generator and harness-ready must agree on
# where "the codex home" is, not each merely claim to honour it in
# isolation. Deliberately NOT built on harness-ready.test.sh's own
# write_valid_roles_at helper, which hand-writes role files directly under
# a CODEX_HOME_DIR/agents it is told about — that proves harness-ready
# reads $CODEX_HOME, but never asks whether this generator put anything
# there in the first place. A generator that still resolves $HOME/.codex
# regardless of $CODEX_HOME, and a reader that correctly resolves
# $CODEX_HOME, are each "correct" by a test that only exercises its own
# side, and still completely disagree — which is exactly the shape of bug
# this case exists to catch. So: run the real generator, then the real
# harness-ready, against the one $CODEX_HOME, and nothing else.

home_e2e=$(mktemp_dir)
codex_home_e2e=$(mktemp_dir)

run_gen "$home_e2e" "$codex_home_e2e"
assert_eq "0" "$rc" \
  "CODEX_HOME end-to-end: install-codex-agents should exit 0 writing under \$CODEX_HOME, got $rc. Output: $out" \
  || fail "CODEX_HOME e2e: generator exit"

count_e2e=$(find "$codex_home_e2e/agents" -type f -name 'dev-skills-*.toml' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "5" "$count_e2e" \
  "CODEX_HOME end-to-end: expected five role files under \$CODEX_HOME/agents (TC-12's own count, under CODEX_HOME resolution), found $count_e2e" \
  || fail "CODEX_HOME e2e: generator count"
[ -e "$home_e2e/.codex/agents" ] \
  && fail "CODEX_HOME end-to-end: the generator wrote under \$HOME/.codex even though \$CODEX_HOME was set — the two paths must never both receive files"

stub_bin_e2e=$(mktemp_dir)
cat > "$stub_bin_e2e/codex" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  --version) echo "codex-cli 9999.0.0" ;;
  *) echo "codex stub: unsupported invocation: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$stub_bin_e2e/codex"
python3_dir_e2e="$(dirname "$(command -v python3)")"
codex_path_e2e="$stub_bin_e2e:$python3_dir_e2e:/usr/bin:/bin:/usr/sbin:/sbin"

ready="$repo_root/skills/implement/scripts/harness-ready"
out_ready=$(HOME="$home_e2e" PATH="$codex_path_e2e" CODEX_HOME="$codex_home_e2e" env -u CLAUDECODE "$ready" 2>&1)
rc_ready=$?
assert_eq "0" "$rc_ready" \
  "CODEX_HOME end-to-end: harness-ready should report ready against the roles this generator just wrote under \$CODEX_HOME, got $rc_ready. Output: $out_ready" \
  || fail "CODEX_HOME e2e: harness-ready exit"
assert_contains "$out_ready" "harness ready" \
  "CODEX_HOME end-to-end: expected 'harness ready', got: $out_ready" \
  || fail "CODEX_HOME e2e: harness-ready message"

exit 0
