#!/usr/bin/env bash
#
# common.sh — helpers shared by the build and release scripts.
#
# Source it, do not execute it:
#
#     source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ─── Output ──────────────────────────────────────────────────────────────────

BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'

step() { printf '\n%s▶ %s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$1" "$OFF"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$OFF"; }
die()  { printf '\n%s✗ %b%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

# ─── Environment ─────────────────────────────────────────────────────────────

# Reads KEY=VALUE pairs from .env without executing anything. Values already
# present in the environment are left alone, which allows one-off overrides
# from the command line.
load_env() {
  local file=$1 line key value
  [[ -f $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    [[ $line =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key=${BASH_REMATCH[2]}
    value=${BASH_REMATCH[3]}
    if [[ $value =~ ^\"(.*)\"$ || $value =~ ^\'(.*)\'$ ]]; then
      value=${BASH_REMATCH[1]}
    fi
    [[ -n ${!key:-} ]] && continue
    export "$key=$value"
  done < "$file"
}

# Moves to the repository root, which is two levels above this file.
enter_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." \
    || die "Cannot reach the repository root."
  [[ -f pubspec.yaml && -d lib ]] \
    || die "This does not look like the Mergelio repository."
}

# ─── Common steps ────────────────────────────────────────────────────────────

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "${2:-$1 not found in PATH.}"
}

# The Flutter release this project is pinned to, taken from .fvmrc.
pinned_flutter_version() {
  [[ -f .fvmrc ]] || return 0
  sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' .fvmrc | head -1
}

# A newer Flutter than the pinned one fails deep inside build_runner with an
# analyzer stack trace that says nothing about versions, so name the mismatch
# here while the output is still readable.
check_flutter_version() {
  local pinned current
  pinned=$(pinned_flutter_version)
  [[ -n $pinned ]] || return 0

  current=$(flutter --version 2>/dev/null \
    | sed -nE 's/^Flutter ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -1)

  if [[ -z $current ]]; then
    warn "Could not read the Flutter version; this project expects $pinned."
  elif [[ $current == "$pinned" ]]; then
    ok "Flutter $current (pinned in .fvmrc)"
  else
    warn "Flutter $current, but this project is pinned to $pinned (.fvmrc)."
    warn "Code generation may fail. Switch with 'fvm use' or 'flutter downgrade $pinned'."
  fi
}

# Version from pubspec.yaml (1.4.0+14 becomes 1.4.0), or the argument if given.
resolve_version() {
  local explicit=${1:-}
  if [[ -n $explicit ]]; then
    printf '%s' "$explicit"
    return 0
  fi
  grep -m1 '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//; s/\+.*$//'
}

# Host architecture using Flutter's naming.
host_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  printf 'x64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *)             printf 'x64' ;;
  esac
}

# .dart_tool/package_config.json records absolute paths to the Flutter SDK, so
# a working copy carried between machines (scp, zip, shared volume) brings the
# other machine's paths with it. pub skips rewriting the file when it looks
# newer than the pubspecs, so `pub get` reports success and build_runner then
# dies on a path that does not exist here. Drop the file rather than let that
# happen.
discard_foreign_package_config() {
  local cfg=.dart_tool/package_config.json root path
  [[ -f $cfg ]] || return 0

  root=$(tr -d ' \n' < "$cfg" \
    | grep -o '"name":"sky_engine","rootUri":"[^"]*"' \
    | sed -E 's/.*"rootUri":"([^"]*)".*/\1/') || true
  # A relative rootUri carries nothing machine-specific; leave it alone.
  [[ $root == file://* ]] || return 0

  path=${root#file://}
  [[ -d $path ]] && return 0

  warn "package_config.json points at $path, which does not exist here."
  warn "Discarding .dart_tool so 'pub get' regenerates it for this machine."
  rm -rf .dart_tool
}

# Generated sources (*.g.dart, *.freezed.dart) are not committed, so a fresh
# clone will not compile until build_runner has run. SKIP_GEN=1 skips it once
# the generated files are already in place.
prepare_sources() {
  step "Fetching dependencies"
  discard_foreign_package_config
  flutter pub get
  ok "Dependencies ready"

  if [[ -n ${SKIP_GEN:-} ]]; then
    warn "SKIP_GEN=1 — skipping code generation"
    return 0
  fi

  step "Generating sources (freezed / json / drift)"
  dart run build_runner build --delete-conflicting-outputs
  ok "Generated sources up to date"
}

maybe_clean() {
  if [[ -n ${CLEAN:-} ]]; then
    step "Cleaning"
    flutter clean >/dev/null
    ok "flutter clean done"
  fi
}

# macOS refuses to map a library whose Team ID differs from the running
# process — dyld aborts at launch with "mapping process and mapped file
# (non-platform) have different Team IDs". An ad-hoc app therefore needs every
# framework inside it to be ad-hoc as well.
#
# A clean build already is. A bundle stops being one when a pod signs itself
# with whichever certificate happens to sit in the keychain, or when an app
# built here is dropped on top of one downloaded from a release. Neither shows
# up until the app is started, and the framework dyld names is only whichever
# loads first, not the one that is actually wrong.
#
# Signing runs inside out: sealing the bundle captures the nested signatures as
# they are at that moment, so they have to be right first.
adhoc_seal_bundle() {
  local app=$1
  local entitlements=${2:-}
  local item target status was strays=0

  while IFS= read -r -d '' item; do
    # Versioned frameworks are signed at Versions/A; codesign rejects the
    # .framework wrapper for those.
    target=$item
    [[ -d "$item/Versions/A" ]] && target="$item/Versions/A"

    status=$(codesign -dvv "$target" 2>&1 || true)
    grep -q '^TeamIdentifier=not set' <<<"$status" && continue

    if grep -q 'not signed at all' <<<"$status"; then
      was="unsigned"
    else
      was="Team ID $(grep -m1 '^TeamIdentifier=' <<<"$status" | cut -d= -f2)"
    fi

    codesign --force --sign - "$target" >/dev/null 2>&1 \
      || die "Could not re-sign ad-hoc: $target"

    # Progress goes to stderr: stdout carries the count back to the caller.
    warn "Re-signed $(basename "$item") ad-hoc — was $was" >&2
    strays=$((strays + 1))
  done < <(find "${app}/Contents" -depth \
    \( -name '*.framework' -o -name '*.dylib' \) -print0)

  # An ad-hoc bundle built with the hardened runtime cannot start either: the
  # runtime enforces library validation, and a bundle with no team has nothing
  # its frameworks can match. Re-signing without it is what makes the app
  # launchable; only the notarized build needs the flag.
  local hardened=0
  codesign -dvvv "$app" 2>&1 | grep -qE '^CodeDirectory .*flags=.*runtime' && hardened=1

  if (( strays || hardened )) || ! codesign --verify --deep --strict "$app" 2>/dev/null; then
    if [[ -n $entitlements && -f $entitlements ]]; then
      codesign --force --sign - --entitlements "$entitlements" "$app" >/dev/null 2>&1 \
        || die "Could not re-seal ad-hoc: $app"
    else
      codesign --force --sign - "$app" >/dev/null 2>&1 \
        || die "Could not re-seal ad-hoc: $app"
    fi
  fi

  if (( hardened )); then
    warn "Dropped the hardened runtime: an ad-hoc app cannot satisfy it" >&2
  fi

  codesign --verify --deep --strict "$app" 2>/dev/null \
    || die "The bundle is still not consistently signed: $app"

  printf '%s' "$strays"
}
