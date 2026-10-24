#!/usr/bin/env bash
# build.sh — render the site into OUT_DIR with the latest release's version
# and download links filled in.
#
#   ./website/build.sh _site                 # asks the GitHub API
#   ./website/build.sh _site release.json    # uses a saved API response
#
# Fails when the release lacks any of the platform files, so a deploy never
# publishes a page with a dead download button.
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
version=${tag#v}
date=$(jq -r '.published_at' <<<"$release" | cut -c1-10)
release_url=$(jq -r '.html_url' <<<"$release")

# asset <regex> — browser download URL of the one asset whose name matches.
asset() {
  local url
  url=$(jq -r --arg re "$1" '[.assets[] | select(.name | test($re))][0].browser_download_url // empty' <<<"$release")
  if [[ -z "$url" ]]; then
    echo "error: release ${tag} has no asset matching /$1/" >&2
    exit 1
  fi
  echo "$url"
}

mac_url=$(asset '-macos-arm64\.dmg$')
win_url=$(asset '-windows-x64-setup\.exe$')
deb_url=$(asset '_amd64\.deb$')
rpm_url=$(asset '\.x86_64\.rpm$')
sums_url=$(asset '^SHA256SUMS\.txt$')

pretty_date=$(date -u -d "$date" '+%B %-d, %Y' 2>/dev/null || date -u -j -f '%Y-%m-%d' "$date" '+%B %-d, %Y')

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -R "$SRC_DIR/img" "$SRC_DIR/style.css" "$SRC_DIR/main.js" "$SRC_DIR/CNAME" "$OUT_DIR/"

# URLs never contain '|', so it is a safe sed delimiter.
sed \
  -e "s|{{VERSION}}|${version}|g" \
  -e "s|{{DATE}}|${pretty_date}|g" \
  -e "s|{{RELEASE_URL}}|${release_url}|g" \
  -e "s|{{MAC_URL}}|${mac_url}|g" \
  -e "s|{{WIN_URL}}|${win_url}|g" \
  -e "s|{{DEB_URL}}|${deb_url}|g" \
  -e "s|{{RPM_URL}}|${rpm_url}|g" \
  -e "s|{{DEB_FILE}}|${deb_url##*/}|g" \
  -e "s|{{RPM_FILE}}|${rpm_url##*/}|g" \
  -e "s|{{SUMS_URL}}|${sums_url}|g" \
  "$SRC_DIR/index.html" > "$OUT_DIR/index.html"

# The page only changes meaningfully with a release, so that date is lastmod.
sed -e "s|{{DATE_ISO}}|${date}|g" "$SRC_DIR/sitemap.xml" > "$OUT_DIR/sitemap.xml"

for page in index.html sitemap.xml; do
  if grep -q '{{' "$OUT_DIR/$page"; then
    echo "error: unfilled placeholder left in ${page}:" >&2
    grep -o '{{[A-Z_]*}}' "$OUT_DIR/$page" | sort -u >&2
    exit 1
  fi
done

echo "Built ${OUT_DIR} for ${tag}"
