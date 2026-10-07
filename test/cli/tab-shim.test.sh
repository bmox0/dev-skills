#!/usr/bin/env bash
# Pins the `tab` shim that `tab.mjs shim` writes: made from a plugin cache, it
# runs the newest copy in that cache; made from a checkout, that checkout's
# copy; an existing TAB_MJS wins over both. A fake node records the argv, so
# no browser starts and nothing is written to ~/.local/bin.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
. "$repo_root/test/lib/harness.sh"

root=$(mktemp_dir)
root="$(cd "$root" && pwd -P)"
fake_bin="$root/fake bin"
record="$root/args.txt"
mkdir -p "$fake_bin"
cat > "$fake_bin/node" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$TAB_SHIM_TEST_RECORD"
SH
chmod +x "$fake_bin/node"

install_copy() {
  mkdir -p "$1/skills/browser-test"
  cp "$repo_root/skills/browser-test/tab.mjs" "$1/skills/browser-test/tab.mjs"
}

make_shim() {
  TAB_SHIM_DIR="$2" node "$1/skills/browser-test/tab.mjs" shim >/dev/null
}

invoke() {
  local dir="$1"
  shift
  PATH="$fake_bin:$PATH" TAB_SHIM_TEST_RECORD="$record" "$dir/tab" "$@"
}

expect() {
  assert_eq "$(printf '%s\n' "$@")" "$(cat "$record")" "$label"
}

# Both hosts install to <cache>/<marketplace>/<plugin>/<version>.
plugin="$root/host's home/plugins/cache/dev-skills/dev-skills"
install_copy "$plugin/4.2.0"
cache_shim="$root/cache shim"
make_shim "$plugin/4.2.0" "$cache_shim"

label="the cached copy runs, its arguments intact"
TAB_MJS="" invoke "$cache_shim" run "scenario with spaces.mjs" --only 3
expect "$plugin/4.2.0/skills/browser-test/tab.mjs" run "scenario with spaces.mjs" --only 3

install_copy "$plugin/4.10.0"
label="a newer version in the same cache runs without a new shim"
TAB_MJS="" invoke "$cache_shim" status
expect "$plugin/4.10.0/skills/browser-test/tab.mjs" status

override="$root/checkout copy/tab.mjs"
mkdir -p "$(dirname "$override")"
touch "$override"
label="an existing TAB_MJS wins"
TAB_MJS="$override" invoke "$cache_shim" help
expect "$override" help

label="a TAB_MJS that names no file falls back to the cache"
TAB_MJS="$root/missing copy/tab.mjs" invoke "$cache_shim" help
expect "$plugin/4.10.0/skills/browser-test/tab.mjs" help

# A checkout sits among other projects; none of them is a version of it.
checkout="$root/work/dev-skills"
install_copy "$checkout"
install_copy "$root/work/zz-other-project"
checkout_shim="$root/checkout shim"
make_shim "$checkout" "$checkout_shim"

label="a shim made from a checkout runs that checkout's copy"
TAB_MJS="" invoke "$checkout_shim" help
expect "$checkout/skills/browser-test/tab.mjs" help
