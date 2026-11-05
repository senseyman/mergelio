#!/usr/bin/env bash
# build.sh — render the site into OUT_DIR. The page links only to the project
# on GitHub; the latest release supplies the sitemap's lastmod date.
#
#   ./website/build.sh _site                 # asks the GitHub API
#   ./website/build.sh _site release.json    # uses a saved API response
set -euo pipefail

OUT_DIR=${1:?usage: build.sh OUT_DIR [release.json]}
RELEASE_JSON=${2:-}
REPO=${REPO:-senseyman/mergelio}
SRC_DIR=$(cd "$(dirname "$0")" && pwd)

if [[ -n "$RELEASE_JSON" ]]; then
  release=$(cat "$RELEASE_JSON")
else
  auth=()
  [[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GH_TOKEN}")
  release=$(curl -fsSL ${auth[@]+"${auth[@]}"} -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${REPO}/releases/latest")
fi

tag=$(jq -r '.tag_name' <<<"$release")
date=$(jq -r '.published_at' <<<"$release" | cut -c1-10)

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -R "$SRC_DIR/img" "$SRC_DIR/fonts" "$SRC_DIR/style.css" "$SRC_DIR/main.js" "$SRC_DIR/index.html" "$SRC_DIR/privacy.html" "$SRC_DIR/CNAME" "$SRC_DIR/robots.txt" "$OUT_DIR/"

# The page only changes meaningfully with a release, so that date is lastmod.
sed -e "s|{{DATE_ISO}}|${date}|g" "$SRC_DIR/sitemap.xml" > "$OUT_DIR/sitemap.xml"

for page in index.html privacy.html sitemap.xml; do
  if grep -q '{{' "$OUT_DIR/$page"; then
    echo "error: unfilled placeholder left in ${page}:" >&2
    grep -o '{{[A-Z_]*}}' "$OUT_DIR/$page" | sort -u >&2
    exit 1
  fi
done

echo "Built ${OUT_DIR} for ${tag}"
