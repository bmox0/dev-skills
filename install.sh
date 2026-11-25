#!/usr/bin/env bash

install_ds() (
  set -eu
  if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    echo 'ds requires Python 3.11 or later on PATH as python3' >&2
    exit 1
  fi

  ds_checkout=$(mktemp -d)
  trap 'rm -rf -- "$ds_checkout"' EXIT
  git -C "$ds_checkout" init --quiet
  git -C "$ds_checkout" fetch --quiet --depth 1 https://github.com/bmox0/dev-skills.git "${DS_REF:-refs/heads/main}"
  git -C "$ds_checkout" checkout --quiet --detach FETCH_HEAD
  "$ds_checkout/scripts/install-ds" "$@"
)

install_ds "$@"
