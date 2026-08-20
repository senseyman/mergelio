#!/usr/bin/env bash
#
# build-macos-app.sh — build Mergelio for macOS.
#
# Produces an ad-hoc signed .app and a zip archive in DIST_DIR. No Apple
# Developer account is needed. The result runs on the machine that built it;
# for a Developer ID signed and notarized DMG use
# scripts/build-macos-dmg.sh instead.
#
# Usage:
#   ./scripts/build-macos-app.sh                 # version from pubspec.yaml
#   ./scripts/build-macos-app.sh 1.4.2           # explicit version in the archive name
#   CLEAN=1 ./scripts/build-macos-app.sh         # flutter clean first
#   SKIP_GEN=1 ./scripts/build-macos-app.sh      # skip code generation
#   SKIP_PACKAGE=1 ./scripts/build-macos-app.sh  # leave the .app, build no archive

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

enter_repo_root
load_env .env

APP_NAME=${APP_NAME:-Mergelio}
DIST_DIR=${DIST_DIR:-dist}

# ─── Preflight ───────────────────────────────────────────────────────────────

step "Checking environment"

[[ $(uname -s) == Darwin ]] || die "macOS builds require a macOS host."
require_cmd flutter "flutter not found in PATH."
require_cmd dart "dart not found in PATH."
check_flutter_version
ok "Host: macOS $(sw_vers -productVersion 2>/dev/null || echo '')"

VERSION=$(resolve_version "${1:-}")
[[ -n $VERSION ]] || die "Could not determine the version."
ok "Version: $VERSION"

# ─── Build ───────────────────────────────────────────────────────────────────

maybe_clean
prepare_sources

step "Building (flutter build macos --release)"
flutter build macos --release

PRODUCTS_DIR="build/macos/Build/Products/Release"

# Take the name off disk rather than assuming "$APP_NAME.app": PRODUCT_NAME is
# lowercase, and on a case-insensitive volume a guessed name would silently
# match while a case-sensitive one would not.
APP_PATH=$(find "$PRODUCTS_DIR" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)

[[ -n $APP_PATH && -d $APP_PATH ]] || die "No app was produced in $PRODUCTS_DIR"
ok "Built: $APP_PATH"

# codesign reports "Signature=adhoc" for ad-hoc builds and "Signature size=N"
# plus an Authority chain once a real identity is involved.
SIGN_INFO=$(codesign -dvv "$APP_PATH" 2>&1 || true)
if grep -q '^Signature=adhoc' <<<"$SIGN_INFO"; then
  ADHOC=1
  ok "Signature: ad-hoc"
else
  ADHOC=0
  AUTHORITY=$(grep -m1 '^Authority=' <<<"$SIGN_INFO" | sed 's/^Authority=//' || true)
  ok "Signature: ${AUTHORITY:-present}"
fi

# ─── Package ─────────────────────────────────────────────────────────────────

if [[ -n ${SKIP_PACKAGE:-} ]]; then
  printf '\n%s✓ Done: %s%s\n\n' "$GREEN" "$APP_PATH" "$OFF"
  exit 0
fi

step "Packaging"

mkdir -p "$DIST_DIR"
ARCHIVE="${DIST_DIR}/${APP_NAME}-${VERSION}-macos-$(host_arch).zip"
rm -f "$ARCHIVE"

# ditto rather than zip: it preserves the bundle's symlinks and metadata.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE"
ok "Archive: $ARCHIVE"

SIZE=$(du -h "$ARCHIVE" | cut -f1)

printf '\n%s✓ Done%s\n' "$GREEN" "$OFF"
printf '  app:     %s\n' "$APP_PATH"
printf '  archive: %s (%s)\n' "$ARCHIVE" "$SIZE"
if (( ADHOC )); then
  printf '\n  Ad-hoc signed: other Macs will refuse it until it is signed with a\n'
  printf '  Developer ID and notarized. See scripts/build-macos-dmg.sh.\n\n'
else
  printf '\n  Signed with a Developer ID. For a notarized DMG use\n'
  printf '  scripts/build-macos-dmg.sh.\n\n'
fi
