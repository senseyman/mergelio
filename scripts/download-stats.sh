#!/usr/bin/env bash
#
# download-stats.sh — show how often each release file was downloaded.
#
# GitHub only keeps a running total per file, so to see downloads over a
# period (say, while an ad campaign runs) save a snapshot now and again later:
# the difference between two rows is the downloads in between.
#
# Usage:
#   ./scripts/download-stats.sh                    # table for every release
#   ./scripts/download-stats.sh --log stats.csv    # also append a dated row of
#                                                  # per-platform totals
#
# Uses the public API without a token (60 requests an hour is plenty); set
# GH_TOKEN to use an authenticated request instead.
#
set -euo pipefail

REPO=${REPO:-senseyman/mergelio}
LOG_FILE=""

case "${1:-}" in
  "") ;;
  --log)
    LOG_FILE=${2:?usage: $(basename "$0") [--log FILE]}
    ;;
  *)
    echo "usage: $(basename "$0") [--log FILE]" >&2
    exit 1
    ;;
esac

auth=()
[[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GH_TOKEN}")
releases=$(curl -fsSL ${auth[@]+"${auth[@]}"} -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/${REPO}/releases?per_page=100")

# platform <asset name> — which download card the file belongs to. Checksums,
# signatures, the appcast and the in-app update zip count as "other", so the
# totals are fresh installs rather than self-updates.
platform='
  def platform:
    if test("-macos-.*\\.dmg$") then "macos"
    elif test("-windows-.*-setup\\.exe$") then "windows"
    elif test("\\.deb$") then "deb"
    elif test("\\.rpm$") then "rpm"
    else "other" end;'

jq -r "$platform"'
  ["release", "macos", "windows", "deb", "rpm", "total"],
  (.[] | select(.draft | not) |
    (reduce .assets[] as $a ({}; .[$a.name | platform] += $a.download_count)) as $c |
    [.tag_name, ($c.macos // 0), ($c.windows // 0), ($c.deb // 0), ($c.rpm // 0),
     (($c.macos // 0) + ($c.windows // 0) + ($c.deb // 0) + ($c.rpm // 0))])
  | @tsv' <<<"$releases" | column -t

if [[ -n "$LOG_FILE" ]]; then
  [[ -s "$LOG_FILE" ]] || echo "date,macos,windows,deb,rpm,total" >"$LOG_FILE"
  jq -r --arg date "$(date -u '+%Y-%m-%d')" "$platform"'
    (reduce (.[] | select(.draft | not) | .assets[]) as $a ({}; .[$a.name | platform] += $a.download_count)) as $c |
    [$date, ($c.macos // 0), ($c.windows // 0), ($c.deb // 0), ($c.rpm // 0),
     (($c.macos // 0) + ($c.windows // 0) + ($c.deb // 0) + ($c.rpm // 0))]
    | @csv' <<<"$releases" | tr -d '"' >>"$LOG_FILE"
  echo
  echo "Appended totals to ${LOG_FILE}:"
  tail -n 1 "$LOG_FILE"
fi
