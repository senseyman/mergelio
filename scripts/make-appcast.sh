#!/usr/bin/env bash
# Builds appcast.json for one published release and an Ed25519 signature
# beside it.
#
#   make-appcast.sh <tag> <assets-dir> <out-dir>
#
# The hashes are taken from SHA256SUMS.txt rather than recomputed: that file is
# what the GPG signature in the release covers, so reusing it keeps one source
# of truth for every artifact hash.
set -euo pipefail

TAG=${1:?tag required}
ASSETS=${2:?assets dir required}
OUT=${3:?output dir required}
REPO=${GITHUB_REPOSITORY:-senseyman/mergelio}
# Where the artifacts will be reachable from. Overridden when rehearsing the
# whole flow against a local server instead of a real release.
BASE_URL=${ASSET_BASE_URL:-https://github.com/$REPO/releases/download/$TAG}
SUMS="$ASSETS/SHA256SUMS.txt"

[[ -f $SUMS ]] || { echo "missing $SUMS" >&2; exit 1; }

[[ -n ${UPDATE_SIGNING_KEY:-} ]] \
  || { echo "::error::UPDATE_SIGNING_KEY is not set - refusing to publish an unsigned manifest."; exit 1; }

# -rawin arrived with OpenSSL 3; LibreSSL, which is what /usr/bin/openssl is on
# macOS, cannot sign Ed25519 this way and fails with an unhelpful message.
openssl pkeyutl -help 2>&1 | grep -q -- -rawin \
  || { echo "openssl lacks -rawin (LibreSSL?); use OpenSSL 3.x" >&2; exit 1; }

# The runner is Linux and the developers are on macOS. `stat` cannot bridge the
# two: -f is "size" on BSD and "file system" on GNU, and the GNU form succeeds
# while printing something else entirely, so a fallback chain silently yields
# garbage. wc -c means the same thing everywhere.
file_size() {
  local size
  size=$(wc -c < "$1" | tr -d '[:space:]')
  [[ $size =~ ^[0-9]+$ ]] || { echo "cannot size $1: got '$size'" >&2; exit 1; }
  printf '%s' "$size"
}

VERSION=${TAG#v}
BUILD=$(sed -n 's/^version: .*+\([0-9]*\)$/\1/p' pubspec.yaml)
[[ -n $BUILD ]] || { echo "no build number in pubspec.yaml" >&2; exit 1; }

# Maps an artifact filename to the platform key the client looks up.
platform_key() {
  case $1 in
    *-macos-arm64-update.zip) echo macos-arm64 ;;
    *-windows-x64-setup.exe)  echo windows-x64 ;;
    *_amd64.deb)              echo linux-x64-deb ;;
    *.x86_64.rpm)             echo linux-x64-rpm ;;
    *)                        echo '' ;;
  esac
}

artifacts='{}'
while read -r sha file; do
  key=$(platform_key "$file")
  [[ -n $key ]] || continue
  [[ -f "$ASSETS/$file" ]] || { echo "listed in SHA256SUMS.txt but missing: $file" >&2; exit 1; }
  size=$(file_size "$ASSETS/$file")
  artifacts=$(jq \
    --arg k "$key" \
    --arg u "$BASE_URL/$file" \
    --arg s "$sha" \
    --argjson n "$size" \
    '.[$k] = {url: $u, sha256: $s, size: $n}' <<<"$artifacts")
done < <(awk '{gsub(/^\*/, "", $2); print $1, $2}' "$SUMS")

count=$(jq 'length' <<<"$artifacts")
[[ $count -ge 1 ]] || { echo "no known artifacts in $SUMS" >&2; exit 1; }

# A macOS release is always signed and notarized, so the absence of the zip
# means the build went wrong rather than that macOS was skipped.
jq -e 'has("macos-arm64")' <<<"$artifacts" >/dev/null \
  || { echo "no macos-arm64 update zip in $SUMS" >&2; exit 1; }

mkdir -p "$OUT"
jq -n \
  --argjson schema 1 \
  --arg version "$VERSION" \
  --argjson build "$BUILD" \
  --arg published "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg notes "https://github.com/$REPO/releases/tag/$TAG" \
  --argjson artifacts "$artifacts" \
  '{schema: $schema, version: $version, build: $build,
    published: $published, notes_url: $notes, artifacts: $artifacts}' \
  > "$OUT/appcast.json"

echo "appcast.json: $count artifact(s)"

umask 077
keyfile=$(mktemp)
trap 'rm -f "$keyfile"' EXIT
printf '%s' "$UPDATE_SIGNING_KEY" > "$keyfile"
# -rawin: Ed25519 signs the message itself, not a digest of it.
openssl pkeyutl -sign -rawin -inkey "$keyfile" \
  -in "$OUT/appcast.json" -out "$OUT/appcast.sig.bin"
# No base64 -w0: BSD base64 does not have it. tr does the same job everywhere.
base64 < "$OUT/appcast.sig.bin" | tr -d '\n' > "$OUT/appcast.json.sig"
rm -f "$OUT/appcast.sig.bin"
echo "appcast.json.sig: signed"
