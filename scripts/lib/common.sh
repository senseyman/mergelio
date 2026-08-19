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
