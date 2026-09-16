#!/usr/bin/env bash
# Pins skills/implement/scripts/harness-ready: TC-11, TC-20 and TC-21.
#
# Both PATH overrides below strip codex and claude off PATH so "the readiness
# signals are absent" (TC-11) and the staleness check (TC-20) are reached
# regardless of whichever host-detection signal harness-ready ends up
# reading — this file does not choose that signal, only the file state.
#
# TC-20 puts a stub `codex` binary on PATH (answering only --version, since
# the plan names a version floor as one of the Codex-branch's own checks) so
# host detection succeeds and the staleness check is reached. It does not
# also fake a populated ~/.codex/config.toml or a live "plugin installed and
# enabled" signal — neither of which this plan freezes the shape of. If
# phase 3's harness-ready gates staleness behind those unmodelled signals
# too, that mismatch will surface at phase 3's own "TC-20 green" step, not
# silently.
#
# [fix round 2] TC-21's config fixtures use Codex's real format: a
# `[features]` TOML section with bare keys (`multi_agent`, `hooks`,
# `plugins`), verified directly against codex-cli 0.154.0 — never the
# invented flat `<name>_enabled` keys the first pass used, which no real
# Codex ever reads. See the TC-21 block below for how each key was
# established and why its second, invented alternative was dropped rather
# than renamed.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"

ready="$repo_root/skills/implement/scripts/harness-ready"

# A PATH with no codex, no claude, and nothing this repo installed — just
# enough of the system to run the script at all.
bare_path="/usr/bin:/bin:/usr/sbin:/sbin"

fail() {
  echo "harness-ready.test.sh: $1" >&2
  exit 1
}

sha256_file() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}

# run_ready HOME [PATH] [CLAUDECODE] [CODEX_HOME] — CLAUDECODE is explicitly
# unset when omitted (not just empty), matching
# test/cli/session-start.test.sh's own run_hook: a case that wants the codex
# branch must not depend on whatever $CLAUDECODE happens to be in the
# ambient shell running this test file. CODEX_HOME is passed through only
# when given, so every existing call (which relies on harness-ready's
# $HOME/.codex fallback) is unaffected.
run_ready() {
  local home="$1" path="${2:-$bare_path}" claudecode="${3:-}" codex_home="${4:-}"
  if [ -n "$claudecode" ]; then
    if [ -n "$codex_home" ]; then
      out=$(HOME="$home" PATH="$path" CLAUDECODE="$claudecode" CODEX_HOME="$codex_home" "$ready" 2>&1)
    else
      out=$(HOME="$home" PATH="$path" CLAUDECODE="$claudecode" env -u CODEX_HOME "$ready" 2>&1)
    fi
  else
    if [ -n "$codex_home" ]; then
      out=$(HOME="$home" PATH="$path" CODEX_HOME="$codex_home" env -u CLAUDECODE "$ready" 2>&1)
    else
      out=$(HOME="$home" PATH="$path" env -u CLAUDECODE -u CODEX_HOME "$ready" 2>&1)
    fi
  fi
  rc=$?
}

# --- TC-11: an environment where the readiness signals are absent ---------

home1=$(mktemp_dir)
run_ready "$home1"
assert_eq "1" "$rc" \
  "TC-11: harness-ready should exit 1 (not ready) in an environment with no readiness signals at all, got $rc. Output: $out" \
  || fail "TC-11 exit"
[ -n "$out" ] || fail "TC-11: harness-ready printed nothing naming which signal failed"

# --- TC-20: a generated implementer role whose embedded TDD hash is stale -

stub_bin=$(mktemp_dir)
cat > "$stub_bin/codex" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  --version) echo "codex-cli 9999.0.0" ;;
  *) echo "codex stub: unsupported invocation: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$stub_bin/codex"
codex_path="$stub_bin:$bare_path"

home2=$(mktemp_dir)
mkdir -p "$home2/.codex/agents"

for role in gate-a gate-b implementer prototyper test-writer; do
  f="$home2/.codex/agents/dev-skills-$role.toml"
  hash="$(sha256_file "$repo_root/agents/$role.md")"
  {
    echo "# dev-skills:generated source=agents/$role.md sha256=$hash"
    echo "name = \"dev-skills-$role\""
    echo 'description = "fixture"'
    if [ "$role" = "implementer" ]; then
      # Deliberately wrong — skills/tdd/SKILL.md's real hash will not equal
      # this, which is the one thing TC-20 is about.
      echo '# dev-skills:embedded source=skills/tdd/SKILL.md sha256=0000000000000000000000000000000000000000000000000000000000000000'
    fi
    echo 'developer_instructions = """fixture"""'
  } > "$f"
done

run_ready "$home2" "$codex_path"
assert_eq "1" "$rc" \
  "TC-20: harness-ready should exit 1 when a generated role's embedded TDD hash no longer matches skills/tdd/SKILL.md, got $rc. Output: $out" \
  || fail "TC-20 exit"

out_lower=$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')
assert_contains "$out_lower" "stale" "TC-20: the message should say the roles are stale, got: $out" || fail "TC-20 stale"
assert_contains "$out_lower" "setup" "TC-20: the message should say setup must be re-run, got: $out" || fail "TC-20 setup"

# --- TC-21: subagents cannot run -------------------------------------------
#
# [fix round 2] The two keys the first pass invented (`subagents_enabled`,
# `max_concurrent_agents`) matched a format no real Codex ever writes, and
# were never checked against one. Investigated directly against codex-cli
# 0.154.0, isolated `CODEX_HOME` only, real `~/.codex` never touched:
# `codex features list` enumerates every feature flag Codex knows (~150 of
# them); `codex doctor --json`'s `config.load.details."enabled feature
# flags"` confirms which are actually on; neither one, nor `codex --help`'s
# full option list, nor the app-server protocol's generated JSON Schema,
# names any concept of a numeric "concurrent cap" anywhere. What *is* real:
# `multi_agent` — a stable feature flag, on by default, under a `[features]`
# TOML section — and setting `[features] multi_agent = false` in an isolated
# `CODEX_HOME` and re-running `codex features list`/`codex doctor --json`
# there confirms it is genuinely read and genuinely flips the effective
# state. So TC-21 is now this one verified case, not two invented ones — the
# plan's own case text ("subagents disabled, or the concurrent thread cap is
# below two") named two alternatives, and only the first corresponds to
# anything a real Codex exposes today.
#
# The real config shape (confirmed against the live ~/.codex/config.toml on
# the machine this was verified on, read-only, never written to):
#   [features]
#   multi_agent = true
#   js_repl = false
# An absent key means the feature is at its default (on); present and
# `false` means off — never a flat `multi_agent_enabled` or
# `subagents_enabled` top-level key, which is what the first pass wrote and
# no real Codex reads.
#
# harness-ready hashes agents/*.md and skills/tdd/SKILL.md itself, via
# python3, so — unlike TC-11 and TC-20, which never need that hash to be
# right — these fixtures' PATH must resolve a python3 that actually runs,
# not just "no codex, no claude". stub_bin (the codex stub) is kept; the
# directory holding the ambient python3 is added alongside it.
python3_dir="$(dirname "$(command -v python3)")"
codex_path_tc21="$stub_bin:$python3_dir:$bare_path"

# write_valid_roles_at CODEX_HOME_DIR — writes a fully valid, non-stale role
# set directly under CODEX_HOME_DIR/agents. write_valid_roles HOME is the
# usual case (CODEX_HOME_DIR = HOME/.codex, harness-ready's own fallback);
# the CODEX_HOME regression case below calls write_valid_roles_at directly,
# since there CODEX_HOME_DIR *is* the codex home, not a parent of one.
write_valid_roles_at() {
  local codex_home="$1" f hash
  mkdir -p "$codex_home/agents"
  for role in gate-a gate-b implementer prototyper test-writer; do
    f="$codex_home/agents/dev-skills-$role.toml"
    hash="$(sha256_file "$repo_root/agents/$role.md")"
    {
      echo "# dev-skills:generated source=agents/$role.md sha256=$hash"
      echo "name = \"dev-skills-$role\""
      echo 'description = "fixture"'
      if [ "$role" = "implementer" ]; then
        echo "# dev-skills:embedded source=skills/tdd/SKILL.md sha256=$(sha256_file "$repo_root/skills/tdd/SKILL.md")"
      fi
      echo 'developer_instructions = """fixture"""'
    } > "$f"
  done
}

write_valid_roles() {
  write_valid_roles_at "$1/.codex"
}

# TC-21: spawning subagents disabled via the real feature flag.
home3=$(mktemp_dir)
write_valid_roles "$home3"
cat > "$home3/.codex/config.toml" <<'CFG'
[features]
multi_agent = false
CFG

run_ready "$home3" "$codex_path_tc21"
assert_eq "1" "$rc" \
  "TC-21: harness-ready should exit 1 when [features] multi_agent = false, got $rc. Output: $out" \
  || fail "TC-21 exit"
out_lower=$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')
assert_contains "$out_lower" "subagent" "TC-21: the message should name subagents, got: $out" || fail "TC-21 message"

# --- TC-21, section scoping: a same-named key under a *different* TOML ----
# table must not be mistaken for [features]'s own — the exact confusion a
# bare, unscoped grep for "hooks" or "multi_agent" invites, which is why a
# real, table-aware read is required rather than a line-by-line regex.
home4=$(mktemp_dir)
write_valid_roles "$home4"
cat > "$home4/.codex/config.toml" <<'CFG'
[mcp_servers.hooks]
enabled = false

[some_other_table]
hooks = false
plugins = false

[features]
multi_agent = true
CFG

run_ready "$home4" "$codex_path_tc21"
assert_eq "0" "$rc" \
  "TC-21 (section scoping): keys named hooks/plugins/enabled under tables other than [features] must not be read as [features]'s own, got $rc. Output: $out" \
  || fail "TC-21 section scoping"

# --- CODEX_HOME, not just \$HOME/.codex, is where Codex actually keeps its
# state (confirmed directly: codex --version/doctor honour \$CODEX_HOME).
# A home5 with nothing under it at all proves harness-ready is reading
# \$CODEX_HOME and not silently falling back to \$HOME/.codex.
home5=$(mktemp_dir)
codex_home5=$(mktemp_dir)
write_valid_roles_at "$codex_home5"

run_ready "$home5" "$codex_path_tc21" "" "$codex_home5"
assert_eq "0" "$rc" \
  "CODEX_HOME: harness-ready should read \$CODEX_HOME rather than \$HOME/.codex when it is set, got $rc. Output: $out" \
  || fail "CODEX_HOME exit"

# --- both signals present: $CLAUDECODE must outrank a codex CLI on PATH ---
#
# A Claude Code user who also has the codex CLI installed must still get a
# ready verdict without being asked to run Codex's own setup — $CLAUDECODE=1
# is the definitive signal for which host is actually running this session;
# the mere presence of a codex binary on PATH is circumstantial and proves
# nothing about which host this is. This fixture never populates
# ~/.codex/agents at all — if host detection mistakenly preferred codex
# here, the failure would name missing dev-skills-*.toml roles instead.

home6=$(mktemp_dir)
mkdir -p "$home6/.claude/plugins"
cat > "$home6/.claude/plugins/installed_plugins.json" <<'JSON'
{"plugins": {"dev-skills@dev-skills": [{"scope": "user"}]}}
JSON

run_ready "$home6" "$codex_path" "1"
assert_eq "0" "$rc" \
  "both-signals: with \$CLAUDECODE=1 and codex on PATH, harness-ready should still treat this as Claude Code and report ready, got $rc. Output: $out" \
  || fail "both-signals exit"
case "$out" in
  *'.codex/agents'*) fail "both-signals: harness-ready checked Codex's generated roles even though \$CLAUDECODE=1 was set — codex's presence on PATH outranked the definitive signal: $out" ;;
esac

exit 0
