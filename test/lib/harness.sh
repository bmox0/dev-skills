#!/usr/bin/env bash
# Assertion helpers and temp-directory management shared by every
# test/**/*.test.sh file. Sourced, never executed directly — it defines
# functions and a single EXIT trap, and leaves the calling test file's own
# set -e (or explicit checks) to decide what a failed assertion does to that
# file's exit code.
#
# assert_eq EXPECTED ACTUAL MSG        - string equality
# assert_contains HAYSTACK NEEDLE MSG  - substring match
# assert_exit CODE MSG                 - checks $? against CODE; call this
#                                         as the statement right after the
#                                         command under test, nothing between
# mktemp_dir                           - a fresh temp dir, path on stdout;
#                                         every dir it hands out is removed
#                                         by this file's own EXIT trap

# A registry *file*, not a shell array: mktemp_dir is meant to be called as
# `d=$(mktemp_dir)`, and command substitution forks a subshell — an array
# mutated there is gone the moment the subshell exits. A file append is a
# real filesystem side effect and survives it.
_harness_registry="$(mktemp "${TMPDIR:-/tmp}/runweld-test-registry.XXXXXX")"

_harness_cleanup() {
  local d
  if [ -f "$_harness_registry" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && rm -rf "$d"
    done < "$_harness_registry"
    rm -f "$_harness_registry"
  fi
}
trap _harness_cleanup EXIT

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" = "$actual" ]; then
    return 0
  fi
  echo "assert_eq: ${msg:-expected \"$expected\", got \"$actual\"}" >&2
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  case "$haystack" in
    *"$needle"*) return 0 ;;
  esac
  echo "assert_contains: ${msg:-\"$needle\" not found in \"$haystack\"}" >&2
  return 1
}

assert_exit() {
  local actual=$?
  local expected="$1" msg="${2:-}"
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  echo "assert_exit: ${msg:-expected exit $expected, got $actual}" >&2
  return 1
}

mktemp_dir() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/runweld-test.XXXXXX")
  echo "$dir" >> "$_harness_registry"
  echo "$dir"
}
