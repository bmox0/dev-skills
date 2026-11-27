#!/usr/bin/env bash
set -euo pipefail

version=$(git show "$GITHUB_SHA:VERSION")
if [[ "$BEFORE" != 0000000000000000000000000000000000000000 ]]; then
  previous=$(git show "$BEFORE:VERSION")
  if [[ "$version" == "$previous" ]]; then
    echo "VERSION is still $version"
    exit 0
  fi
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: $version" >&2
  exit 1
fi
tag="v$version"
if git show-ref --verify --quiet "refs/tags/$tag"; then
  if [[ "$(git rev-parse "refs/tags/$tag^{commit}")" != "$GITHUB_SHA" ]]; then
    echo "$tag already points to a different commit" >&2
    exit 1
  fi
  if [[ "$(gh release view "$tag" --json isDraft --jq '.isDraft')" == false ]]; then
    echo "$tag is already published"
    exit 0
  fi
fi

notes="docs/releases/$version.md"
args=(--generate-notes)
if [[ -s "$notes" ]]; then
  args=(--notes-file "$notes")
fi
if [[ "$version" == *-* ]]; then
  args+=(--prerelease)
fi
gh release create "$tag" --target "$GITHUB_SHA" --title "Runweld $version" "${args[@]}"
