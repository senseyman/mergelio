#!/usr/bin/env bash
#
# build-linux-rpm.sh — build Mergelio and package it as an .rpm installer.
#
# Installs into /opt/mergelio, links the binary onto PATH, and registers the
# desktop entry and icon so the app appears in the launcher with its icon.
#
# The package is tied to the distribution it was built on: its Release carries
# a %{dist} tag and its dependencies resolve against that distribution's
# libraries. Build it on Fedora, or in a fedora container, not on Ubuntu.
#
# Usage:
#   ./scripts/build-linux-rpm.sh                 # version from pubspec.yaml
#   ./scripts/build-linux-rpm.sh 1.4.2           # explicit version
#   CLEAN=1 ./scripts/build-linux-rpm.sh         # flutter clean first
#   SKIP_GEN=1 ./scripts/build-linux-rpm.sh      # skip code generation
#   SKIP_BUILD=1 ./scripts/build-linux-rpm.sh    # package an existing bundle

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

enter_repo_root
load_env .env

DIST_DIR=${DIST_DIR:-dist}
# Matches APPLICATION_ID in linux/CMakeLists.txt. The desktop entry, the icon
# and the window's WM class all have to agree on it or the shell will not
# associate the running window with the launcher entry.
APP_ID=${APP_ID:-com.mergelio.mergelio}
PKG_NAME=${PKG_NAME:-mergelio}
INSTALL_ROOT=${INSTALL_ROOT:-/opt/${PKG_NAME}}
SPEC_FILE=${SPEC_FILE:-linux/packaging/mergelio.spec}

# ─── Preflight ───────────────────────────────────────────────────────────────

step "Checking environment"

[[ $(uname -s) == Linux ]] || die "RPM packages must be built on a Linux host."
require_cmd rpmbuild "rpmbuild not found. Install it: sudo dnf install rpm-build"
[[ -f $SPEC_FILE ]] || die "No spec file at $SPEC_FILE"

if [[ -z ${SKIP_BUILD:-} ]]; then
  require_cmd flutter "flutter not found in PATH."
  require_cmd dart "dart not found in PATH."
  check_flutter_version

  MISSING=()
  for tool in clang cmake ninja pkg-config; do
    command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
  done
  if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
    MISSING+=("gtk3-devel")
  fi
  if (( ${#MISSING[@]} > 0 )); then
    die "Missing build dependencies: ${MISSING[*]}\n  sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel"
  fi
  ok "Toolchain: clang, cmake, ninja, pkg-config, gtk+-3.0"
fi

VERSION=$(resolve_version "${1:-}")
[[ -n $VERSION ]] || die "Could not determine the version."
# A dash in Version makes rpmbuild fail late and cryptically, so reject it here.
[[ $VERSION == *-* ]] && die "RPM versions cannot contain a dash: $VERSION"
ok "Version: $VERSION"

ARCH=$(host_arch)
# rpm uses its own architecture names.
case "$ARCH" in
  x64)   RPM_ARCH=x86_64 ;;
  arm64) RPM_ARCH=aarch64 ;;
  *)     die "Unsupported architecture: $ARCH" ;;
esac
ok "Architecture: $RPM_ARCH"

# ─── Build ───────────────────────────────────────────────────────────────────

if [[ -n ${SKIP_BUILD:-} ]]; then
  warn "SKIP_BUILD=1 — packaging whatever bundle is already built"
else
  maybe_clean
  prepare_sources

  step "Building (flutter build linux --release)"
  flutter build linux --release
fi

BUNDLE_DIR="build/linux/${ARCH}/release/bundle"
if [[ ! -d $BUNDLE_DIR ]]; then
  BUNDLE_DIR=$(find build/linux -maxdepth 3 -type d -name bundle -print -quit 2>/dev/null || true)
fi
[[ -n $BUNDLE_DIR && -d $BUNDLE_DIR ]] || die "No bundle was produced under build/linux"
[[ -x "${BUNDLE_DIR}/${PKG_NAME}" ]] || die "No ${PKG_NAME} executable in ${BUNDLE_DIR}"
ok "Bundle: $BUNDLE_DIR"

# The runtime icon is installed into the bundle by linux/CMakeLists.txt. Its
# absence means the app would launch without a window icon, which is the whole
# point of this package, so fail rather than ship it.
[[ -f "${BUNDLE_DIR}/data/icon.png" ]] \
  || die "No data/icon.png in the bundle — the icon install rule in linux/CMakeLists.txt did not run."
ok "Runtime icon present"

# ─── Stage ───────────────────────────────────────────────────────────────────

step "Staging the package tree"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

STAGE_DIR="${WORK_DIR}/stage"
TOP_DIR="${WORK_DIR}/rpmbuild"
mkdir -p "$STAGE_DIR" "${TOP_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# The app itself lives under /opt; only the launcher glue goes into /usr.
mkdir -p "${STAGE_DIR}${INSTALL_ROOT}"
cp -a "${BUNDLE_DIR}/." "${STAGE_DIR}${INSTALL_ROOT}/"

mkdir -p "${STAGE_DIR}/usr/bin"
ln -s "${INSTALL_ROOT}/${PKG_NAME}" "${STAGE_DIR}/usr/bin/${PKG_NAME}"

mkdir -p "${STAGE_DIR}/usr/share/applications"
cp "linux/packaging/${APP_ID}.desktop" \
  "${STAGE_DIR}/usr/share/applications/${APP_ID}.desktop"

mkdir -p "${STAGE_DIR}/usr/share/icons/hicolor/256x256/apps"
cp "linux/packaging/icons/${APP_ID}.png" \
  "${STAGE_DIR}/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"

mkdir -p "${STAGE_DIR}/usr/share/licenses/${PKG_NAME}"
cp LICENSE "${STAGE_DIR}/usr/share/licenses/${PKG_NAME}/LICENSE"

find "$STAGE_DIR" -type d -exec chmod 0755 {} +
chmod 0755 "${STAGE_DIR}${INSTALL_ROOT}/${PKG_NAME}"

ok "Tree staged"

# ─── Build the package ───────────────────────────────────────────────────────

step "Building the .rpm"

rpmbuild -bb \
  --define "_topdir ${TOP_DIR}" \
  --define "app_version ${VERSION}" \
  --define "stagedir ${STAGE_DIR}" \
  --target "$RPM_ARCH" \
  "$SPEC_FILE"

BUILT_RPM=$(find "${TOP_DIR}/RPMS" -name "${PKG_NAME}-${VERSION}-*.rpm" -print -quit)
[[ -n $BUILT_RPM ]] || die "rpmbuild reported success but produced no package."

mkdir -p "$DIST_DIR"
RPM="${DIST_DIR}/$(basename "$BUILT_RPM")"
rm -f "$RPM"
cp "$BUILT_RPM" "$RPM"
ok "Package: $RPM"

if command -v rpmlint >/dev/null 2>&1; then
  step "Running rpmlint"
  rpmlint "$RPM" || warn "rpmlint reported findings (not fatal)."
fi

SIZE=$(du -h "$RPM" | cut -f1)

printf '\n%s✓ Done%s\n' "$GREEN" "$OFF"
printf '  package: %s (%s)\n' "$RPM" "$SIZE"
printf '\n  Install with: sudo dnf install ./%s\n' "$RPM"
printf '  Remove with:  sudo dnf remove %s\n\n' "$PKG_NAME"
