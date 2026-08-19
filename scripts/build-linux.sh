#!/usr/bin/env bash
#
# build-linux.sh — build Mergelio for Linux.
#
# Produces a release bundle and a tar.gz archive in DIST_DIR.
#
# Usage:
#   ./scripts/build-linux.sh                 # version from pubspec.yaml
#   ./scripts/build-linux.sh 1.4.2           # explicit version in the archive name
#   CLEAN=1 ./scripts/build-linux.sh         # flutter clean first
#   SKIP_GEN=1 ./scripts/build-linux.sh      # skip code generation
#   SKIP_PACKAGE=1 ./scripts/build-linux.sh  # leave the bundle, build no archive

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

enter_repo_root
load_env .env

APP_NAME=${APP_NAME:-Mergelio}
DIST_DIR=${DIST_DIR:-dist}
# Matches APPLICATION_ID in linux/CMakeLists.txt: the desktop entry, the icon
# and the window's WM class all have to agree on it.
APP_ID=${APP_ID:-com.mergelio.mergelio}

# ─── Preflight ───────────────────────────────────────────────────────────────

step "Checking environment"

[[ $(uname -s) == Linux ]] || die "Linux builds require a Linux host."
require_cmd flutter "flutter not found in PATH."
require_cmd dart "dart not found in PATH."
check_flutter_version

# Flutter's Linux desktop toolchain. Missing pieces fail deep inside CMake with
# unhelpful errors, so check them up front and name the packages.
MISSING=()
for tool in clang cmake ninja pkg-config; do
  command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
done
if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
  MISSING+=("libgtk-3-dev")
fi

if (( ${#MISSING[@]} > 0 )); then
  die "Missing build dependencies: ${MISSING[*]}\n  Debian/Ubuntu: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev\n  Fedora:        sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel\n  Arch:          sudo pacman -S clang cmake ninja pkgconf gtk3"
fi

ok "Toolchain: clang, cmake, ninja, pkg-config, gtk+-3.0"

VERSION=$(resolve_version "${1:-}")
[[ -n $VERSION ]] || die "Could not determine the version."
ok "Version: $VERSION"

ARCH=$(host_arch)
ok "Architecture: $ARCH"

# ─── Build ───────────────────────────────────────────────────────────────────

maybe_clean
prepare_sources

step "Building (flutter build linux --release)"
flutter build linux --release

BUNDLE_DIR="build/linux/${ARCH}/release/bundle"

if [[ ! -d $BUNDLE_DIR ]]; then
  BUNDLE_DIR=$(find build/linux -maxdepth 3 -type d -name bundle -print -quit 2>/dev/null || true)
fi

[[ -n $BUNDLE_DIR && -d $BUNDLE_DIR ]] || die "No bundle was produced under build/linux"
ok "Built: $BUNDLE_DIR"

# ─── Package ─────────────────────────────────────────────────────────────────

if [[ -n ${SKIP_PACKAGE:-} ]]; then
  printf '\n%s✓ Done: %s%s\n\n' "$GREEN" "$BUNDLE_DIR" "$OFF"
  exit 0
fi

step "Packaging"

mkdir -p "$DIST_DIR"
ARCHIVE="${DIST_DIR}/${APP_NAME}-${VERSION}-linux-${ARCH}.tar.gz"
rm -f "$ARCHIVE"

# Pack the bundle's contents under a single versioned top-level directory so
# that extracting it does not scatter files into the current directory.
STAGE_NAME="${APP_NAME}-${VERSION}-linux-${ARCH}"
STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -a "$BUNDLE_DIR" "${STAGE_DIR}/${STAGE_NAME}"

# The bundle carries the icon it loads at runtime (installed by CMake into
# data/icon.png). These two are for whoever installs the archive system-wide:
# without them the app has no launcher entry and no icon in the application
# menu.
mkdir -p "${STAGE_DIR}/${STAGE_NAME}/share/applications" \
  "${STAGE_DIR}/${STAGE_NAME}/share/icons/hicolor/256x256/apps"
cp linux/packaging/${APP_ID}.desktop \
  "${STAGE_DIR}/${STAGE_NAME}/share/applications/"
cp linux/packaging/icons/${APP_ID}.png \
  "${STAGE_DIR}/${STAGE_NAME}/share/icons/hicolor/256x256/apps/"

tar -czf "$ARCHIVE" -C "$STAGE_DIR" "$STAGE_NAME"
ok "Archive: $ARCHIVE"

SIZE=$(du -h "$ARCHIVE" | cut -f1)

printf '\n%s✓ Done%s\n' "$GREEN" "$OFF"
printf '  bundle:  %s\n' "$BUNDLE_DIR"
printf '  archive: %s (%s)\n' "$ARCHIVE" "$SIZE"
printf '\n  Run it with: %s/mergelio\n\n' "$BUNDLE_DIR"
