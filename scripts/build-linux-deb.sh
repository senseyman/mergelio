#!/usr/bin/env bash
#
# build-linux-deb.sh — build Mergelio and package it as a .deb installer.
#
# Installs into /opt/mergelio, links the binary onto PATH, and registers the
# desktop entry and icon so the app appears in the launcher with its icon.
#
# Usage:
#   ./scripts/build-linux-deb.sh                 # version from pubspec.yaml
#   ./scripts/build-linux-deb.sh 1.4.2           # explicit version
#   CLEAN=1 ./scripts/build-linux-deb.sh         # flutter clean first
#   SKIP_GEN=1 ./scripts/build-linux-deb.sh      # skip code generation
#   SKIP_BUILD=1 ./scripts/build-linux-deb.sh    # package an existing bundle

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
MAINTAINER=${MAINTAINER:-Neo <noreply@github.com>}
HOMEPAGE=${HOMEPAGE:-https://github.com/senseyman/mergelio}

# ─── Preflight ───────────────────────────────────────────────────────────────

step "Checking environment"

[[ $(uname -s) == Linux ]] || die "Debian packages must be built on a Linux host."
require_cmd dpkg-deb "dpkg-deb not found. Install it: sudo apt install dpkg-dev"

if [[ -z ${SKIP_BUILD:-} ]]; then
  require_cmd flutter "flutter not found in PATH."
  require_cmd dart "dart not found in PATH."
  check_flutter_version

  MISSING=()
  for tool in clang cmake ninja pkg-config; do
    command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
  done
  if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
    MISSING+=("libgtk-3-dev")
  fi
  if (( ${#MISSING[@]} > 0 )); then
    die "Missing build dependencies: ${MISSING[*]}\n  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev"
  fi
  ok "Toolchain: clang, cmake, ninja, pkg-config, gtk+-3.0"
fi

VERSION=$(resolve_version "${1:-}")
[[ -n $VERSION ]] || die "Could not determine the version."
ok "Version: $VERSION"

ARCH=$(host_arch)
# dpkg uses its own architecture names.
case "$ARCH" in
  x64)   DEB_ARCH=amd64 ;;
  arm64) DEB_ARCH=arm64 ;;
  *)     die "Unsupported architecture: $ARCH" ;;
esac
ok "Architecture: $DEB_ARCH"

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

PKG_DIR=$(mktemp -d)
trap 'rm -rf "$PKG_DIR"' EXIT

# The app itself lives under /opt; only the launcher glue goes into /usr.
mkdir -p "${PKG_DIR}${INSTALL_ROOT}"
cp -a "${BUNDLE_DIR}/." "${PKG_DIR}${INSTALL_ROOT}/"

mkdir -p "${PKG_DIR}/usr/bin"
ln -s "${INSTALL_ROOT}/${PKG_NAME}" "${PKG_DIR}/usr/bin/${PKG_NAME}"

mkdir -p "${PKG_DIR}/usr/share/applications"
cp "linux/packaging/${APP_ID}.desktop" \
  "${PKG_DIR}/usr/share/applications/${APP_ID}.desktop"

mkdir -p "${PKG_DIR}/usr/share/icons/hicolor/256x256/apps"
cp "linux/packaging/icons/${APP_ID}.png" \
  "${PKG_DIR}/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"

mkdir -p "${PKG_DIR}/usr/share/doc/${PKG_NAME}"
cp LICENSE "${PKG_DIR}/usr/share/doc/${PKG_NAME}/copyright"

find "$PKG_DIR" -type d -exec chmod 0755 {} +
chmod 0755 "${PKG_DIR}${INSTALL_ROOT}/${PKG_NAME}"

ok "Tree staged"

# ─── Control ─────────────────────────────────────────────────────────────────

step "Writing control files"

INSTALLED_KB=$(du -sk "$PKG_DIR" | cut -f1)

mkdir -p "${PKG_DIR}/DEBIAN"
cat > "${PKG_DIR}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: ${DEB_ARCH}
Maintainer: ${MAINTAINER}
Homepage: ${HOMEPAGE}
Installed-Size: ${INSTALLED_KB}
Depends: libgtk-3-0 | libgtk-3-0t64, libglib2.0-0 | libglib2.0-0t64, libstdc++6, zlib1g, git
Description: Free, cross-platform visual Git client
 Mergelio is a desktop Git client with a commit graph, staging, diffs,
 merge and rebase tooling, and worktree support.
EOF

# Ubuntu 24.04 renamed several runtime libraries with a t64 suffix for the
# 64-bit time_t transition, so both names are accepted above.

cat > "${PKG_DIR}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = configure ]; then
  # Without these the entry and icon exist on disk but the shell keeps showing
  # a stale menu and a generic icon until the next login.
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
  fi
fi

exit 0
EOF

cat > "${PKG_DIR}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = remove ] || [ "$1" = purge ]; then
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
  fi
fi

exit 0
EOF

chmod 0755 "${PKG_DIR}/DEBIAN/postinst" "${PKG_DIR}/DEBIAN/postrm"
ok "control, postinst, postrm written"

# ─── Build the package ───────────────────────────────────────────────────────

step "Building the .deb"

mkdir -p "$DIST_DIR"
DEB="${DIST_DIR}/${PKG_NAME}_${VERSION}_${DEB_ARCH}.deb"
rm -f "$DEB"

# --root-owner-group gives every file root:root without needing fakeroot.
dpkg-deb --root-owner-group --build "$PKG_DIR" "$DEB" >/dev/null
ok "Package: $DEB"

if command -v lintian >/dev/null 2>&1; then
  step "Running lintian"
  lintian --no-tag-display-limit "$DEB" || warn "lintian reported findings (not fatal)."
fi

SIZE=$(du -h "$DEB" | cut -f1)

printf '\n%s✓ Done%s\n' "$GREEN" "$OFF"
printf '  package: %s (%s)\n' "$DEB" "$SIZE"
printf '\n  Install with: sudo apt install ./%s\n' "$DEB"
printf '  Remove with:  sudo apt remove %s\n\n' "$PKG_NAME"
