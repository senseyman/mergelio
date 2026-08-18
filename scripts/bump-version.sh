#!/usr/bin/env bash
#
# bump-version.sh — increment the application version in pubspec.yaml.
#
# The version is SemVer with a build number: MAJOR.MINOR.PATCH+BUILD.
# The build number always grows; patch/minor reset when a higher level moves.
#
# Usage (normally through the bump-patch/minor/major.sh wrappers):
#   ./scripts/bump-version.sh <patch|minor|major>
#
set -euo pipefail

LEVEL="${1:-}"
case "$LEVEL" in
  patch | minor | major) ;;
  *)
    echo "usage: $(basename "$0") <patch|minor|major>" >&2
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"

line="$(grep -E '^version:' "$PUBSPEC")" ||
  { echo "no 'version:' line found in $PUBSPEC" >&2; exit 1; }

cur="$(printf '%s' "${line#version:}" | tr -d '[:space:]')" # X.Y.Z+B
semver="${cur%%+*}"
build="${cur##*+}"
[ "$build" = "$cur" ] && build=0 # version carries no +build

IFS='.' read -r major minor patch <<<"$semver"
: "${major:?cannot parse MAJOR}" "${minor:?cannot parse MINOR}" "${patch:?cannot parse PATCH}"

case "$LEVEL" in
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
esac
build=$((build + 1))

new="${major}.${minor}.${patch}+${build}"

tmp="$(mktemp)"
sed "s/^version:.*/version: ${new}/" "$PUBSPEC" >"$tmp" && mv "$tmp" "$PUBSPEC"

printf '✓ version: %s → %s\n' "$cur" "$new"
printf '  next: build the artifacts, then `git tag v%s`\n' "${major}.${minor}.${patch}"
