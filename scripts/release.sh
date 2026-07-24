#!/usr/bin/env bash
#
# release.sh — build, sign, package and notarize the macOS app.
#
# Usage:
#   ./scripts/release.sh              # version taken from pubspec.yaml
#   ./scripts/release.sh 1.4.2        # explicit version in the DMG name
#   SKIP_NOTARIZE=1 ./scripts/release.sh   # build and DMG only, no Apple round-trip
#
set -euo pipefail

# ─── Settings ────────────────────────────────────────────────────────────

APP_NAME="Mergelio"
SIGN_IDENTITY="Developer ID Application: Jane Doe (ABCDE12345)"
NOTARY_PROFILE="mergelio-notary"
ENTITLEMENTS="macos/Runner/Release.entitlements"
DIST_DIR="dist"

# ─── Helpers ────────────────────────────────────────────────────────────────

BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'

step() { printf '\n%s▶ %s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$1" "$OFF"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$OFF"; }
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"

# ─── 0. Preflight checks ──────────────────────────────────────────────

step "Environment check"

[[ -d "macos" && -f "pubspec.yaml" ]] || die "Run this from the Flutter project root."

for tool in flutter codesign xcrun; do
  command -v "$tool" >/dev/null 2>&1 || die "Not found: '$tool' in PATH."
done

if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
  command -v create-dmg >/dev/null 2>&1 \
    || die "create-dmg not found. Install it: brew install create-dmg"
fi

[[ -f "$ENTITLEMENTS" ]] || die "Missing entitlements file: $ENTITLEMENTS"

if grep -q "get-task-allow" "$ENTITLEMENTS"; then
  die "$ENTITLEMENTS contains get-task-allow - notarization would be rejected."
fi

security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY" \
  || die "Certificate not found in Keychain:\n  $SIGN_IDENTITY"

if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "Notary profile '$NOTARY_PROFILE' is not available.\n  Create it: xcrun notarytool store-credentials"
fi

ok "Everything in place"

# ─── Version ──────────────────────────────────────────────────────────────────

if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version: *//; s/+.*//' | tr -d '[:space:]')"
fi
[[ -n "$VERSION" ]] || die "Could not determine the version."

DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
ok "Version: $VERSION"

# ─── 1. Build ───────────────────────────────────────────────────────────────

step "Build (flutter build macos --release)"

if [[ -n "${CLEAN:-}" ]]; then
  flutter clean >/dev/null
  ok "flutter clean done"
fi

flutter build macos --release

[[ -d "$APP_PATH" ]] || die "App did not build: $APP_PATH"
ok "Built: $APP_PATH"

# ─── 2. Re-sign ───────────────────────────────────────────────────────────
# Xcode injects com.apple.security.get-task-allow even in Release.
# Re-sign the outer bundle with clean entitlements.
# No --deep: the embedded frameworks are already signed correctly, --deep breaks them.

step "Re-signing with clean entitlements"

rm -f "${APP_PATH}/Contents/embedded.provisionprofile"

codesign --force \
  --sign "$SIGN_IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

ok "Signed"

# ─── 3. Signature validation ────────────────────────────────────────────────────

step "Signature check"

SIGN_INFO="$(codesign -dvv "$APP_PATH" 2>&1)"

grep -q "Authority=Developer ID Application" <<<"$SIGN_INFO" \
  || die "Signature is not Developer ID Application:\n$(grep 'Authority=' <<<"$SIGN_INFO" | head -1)"
ok "Authority: Developer ID Application"

grep -q "flags=.*runtime" <<<"$SIGN_INFO" \
  || die "Hardened Runtime is disabled - notarization would fail."
ok "Hardened Runtime enabled"

grep -q "^Timestamp=" <<<"$SIGN_INFO" \
  || die "No secure timestamp present."
ok "Timestamp present"

if codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "get-task-allow"; then
  die "get-task-allow is still present in the binary."
fi
ok "get-task-allow absent"

codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
  || die "codesign --verify failed (check the embedded frameworks)."
ok "All embedded frameworks are valid"

# ─── 4. DMG ──────────────────────────────────────────────────────────────────

if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
  warn "SKIP_NOTARIZE=1 — stopping after the app build."
  printf '\n%s✓ Done: %s%s\n\n' "$GREEN" "$APP_PATH" "$OFF"
  exit 0
fi

step "Packaging the DMG"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

create-dmg \
  --volname "$APP_NAME" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 150 200 \
  --app-drop-link 450 200 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH" \
  || [[ -f "$DMG_PATH" ]] || die "create-dmg did not produce an image."

codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
ok "DMG created and signed: $DMG_PATH"

# ─── 5. Notarization ──────────────────────────────────────────────────────────

step "Notarization (usually 1-5 minutes)"

NOTARY_LOG="$(mktemp -t notary)"
trap 'rm -f "$NOTARY_LOG"' EXIT

set +e
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait 2>&1 | tee "$NOTARY_LOG"
set -e

SUBMISSION_ID="$(grep -m1 -E '^[[:space:]]*id:' "$NOTARY_LOG" | awk '{print $2}')"
STATUS="$(grep -m1 -E '^[[:space:]]*status:' "$NOTARY_LOG" | awk '{print $2}')"

if [[ "$STATUS" != "Accepted" ]]; then
  printf '\n%s─── Failure details ───%s\n' "$YELLOW" "$OFF"
  [[ -n "$SUBMISSION_ID" ]] && \
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
  die "Notarization failed (status: ${STATUS:-unknown})."
fi

ok "Status: Accepted"

# ─── 6. Staple and final check ──────────────────────────────────────────

step "Stapling the ticket"

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH" >/dev/null || die "stapler validate failed."
ok "Ticket stapled"

step "Gatekeeper check"

SPCTL_OUT="$(spctl -a -vvv -t install "$DMG_PATH" 2>&1)" || true
if grep -q "source=Notarized Developer ID" <<<"$SPCTL_OUT"; then
  ok "source=Notarized Developer ID"
else
  warn "Unexpected spctl output:"
  printf '%s\n' "$SPCTL_OUT"
fi

# ─── Done ──────────────────────────────────────────────────────────────────

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d '[:space:]')"
printf '\n%s✓ Release ready%s\n' "$GREEN" "$OFF"
printf '  %s  (%s)\n\n' "$DMG_PATH" "$SIZE"