#!/usr/bin/env bash

install_runweld() (
  set -euo pipefail
  if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    echo 'Runweld requires Python 3.11 or later on PATH as python3' >&2
    exit 1
  fi

  upstream=https://github.com/bmox0/runweld.git
  tag=
  revision=${RUNWELD_REF:-}
  if [[ -z "$revision" ]]; then
    if ! tag=$(curl -fsSL -H 'Accept: application/vnd.github+json' https://api.github.com/repos/bmox0/runweld/releases/latest |
      python3 -c '
import json, re, sys
try:
    release = json.load(sys.stdin)
    tag = release["tag_name"]
    if release["draft"] is not False or release["prerelease"] is not False or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        sys.exit(1)
except (KeyError, TypeError, ValueError):
    sys.exit(1)
print(tag)
'); then
      echo 'Runweld could not resolve the latest stable release. Retry or set RUNWELD_REF to an explicit source.' >&2
      exit 1
    fi
    ref="refs/tags/$tag"
    # GitHub's target_commitish can describe a branch or be unused for an existing tag.
    if ! refs=$(git ls-remote --exit-code -- "$upstream" "$ref" "$ref^{}"); then
      echo "Runweld could not find the published tag $tag." >&2
      exit 1
    fi
    revision=$(awk -v ref="$ref" '$2 == ref {tag = $1} $2 == ref "^{}" {peeled = $1} END {print (peeled ? peeled : tag)}' <<< "$refs")
    if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
      echo "Runweld could not resolve the published tag $tag to a Git commit." >&2
      exit 1
    fi
  fi

  runweld_checkout=$(mktemp -d)
  trap 'rm -rf -- "$runweld_checkout"' EXIT
  git -C "$runweld_checkout" init --quiet
  git -C "$runweld_checkout" fetch --quiet --depth 1 --no-tags -- "$upstream" "$revision"
  fetched=$(git -C "$runweld_checkout" rev-parse --verify 'FETCH_HEAD^{commit}')
  if [[ "$revision" =~ ^[0-9a-f]{40}$ && "$fetched" != "$revision" ]]; then
    echo "Runweld fetched $fetched instead of the selected ${tag:+published }commit $revision${tag:+ ($tag)}." >&2
    exit 1
  fi
  git -C "$runweld_checkout" -c core.autocrlf=false checkout --quiet --detach "$fetched"
  if [[ -n "$tag" && "$(cat "$runweld_checkout/VERSION")" != "${tag#v}" ]]; then
    echo "Runweld VERSION does not match the published tag $tag at $fetched." >&2
    exit 1
  fi
  "$runweld_checkout/scripts/install-runweld" "$@"
)

install_runweld "$@"
