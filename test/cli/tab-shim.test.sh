#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"

root=$(mktemp_dir)
root="$(cd "$root" && pwd -P)"
installed="$root/plugin's installed copy"
shim_dir="$root/shim bin"
fake_bin="$root/fake bin"
record="$root/args.txt"
mkdir -p "$installed" "$fake_bin"
cp "$repo_root/skills/browser-test/tab.mjs" "$installed/tab.mjs"

# Generate only a temporary shim with real Node; never launch a browser or
# install into the user's ~/.local/bin. The fake Node records exact argv.
TAB_SHIM_DIR="$shim_dir" node "$installed/tab.mjs" shim >/dev/null
cat > "$fake_bin/node" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$TAB_SHIM_TEST_RECORD"
SH
chmod +x "$fake_bin/node"

invoke() {
  PATH="$fake_bin:$PATH" TAB_SHIM_TEST_RECORD="$record" "$shim_dir/tab" "$@"
}

TAB_MJS="" invoke run "scenario with spaces.mjs" --only 3
assert_eq "$(printf '%s\n' "$installed/tab.mjs" run "scenario with spaces.mjs" --only 3)" \
  "$(cat "$record")" "default target and arguments survive spaces and apostrophes"

override="$root/checkout copy/tab.mjs"
mkdir -p "$(dirname "$override")"
touch "$override"
TAB_MJS="$override" invoke help
assert_eq "$(printf '%s\n' "$override" help)" "$(cat "$record")" \
  "existing TAB_MJS overrides the installed copy"

TAB_MJS="$root/missing copy/tab.mjs" invoke help
assert_eq "$(printf '%s\n' "$installed/tab.mjs" help)" "$(cat "$record")" \
  "invalid TAB_MJS falls back to the pinned installed copy"

if grep -Eq '\.claude|\.codex|plugins/cache|sort|\$HOME' "$shim_dir/tab"; then
  echo "tab shim must not resolve a target through another host's plugin cache" >&2
  exit 1
fi

# An update becomes the target only when the new installed copy regenerates it.
updated="$root/updated plugin copy"
mkdir -p "$updated"
cp "$installed/tab.mjs" "$updated/tab.mjs"
TAB_SHIM_DIR="$shim_dir" node "$updated/tab.mjs" shim >/dev/null
TAB_MJS="" invoke status
assert_eq "$(printf '%s\n' "$updated/tab.mjs" status)" "$(cat "$record")" \
  "rerunning shim pins the updated plugin copy"
