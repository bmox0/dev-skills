#!/usr/bin/env bash

install_runweld() (
  set -eu
  if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    echo 'Runweld requires Python 3.11 or later on PATH as python3' >&2
    exit 1
  fi

  runweld_checkout=$(mktemp -d)
  trap 'rm -rf -- "$runweld_checkout"' EXIT
  git -C "$runweld_checkout" init --quiet
  git -C "$runweld_checkout" fetch --quiet --depth 1 https://github.com/bmox0/runweld.git "${RUNWELD_REF:-refs/heads/main}"
  git -C "$runweld_checkout" checkout --quiet --detach FETCH_HEAD
  "$runweld_checkout/scripts/install-runweld" "$@"
)

install_runweld "$@"
