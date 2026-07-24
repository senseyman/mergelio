#!/usr/bin/env bash
#
# bump-minor.sh — minor release: MAJOR.MINOR.PATCH+BUILD → MAJOR.(MINOR+1).0+(BUILD+1).
#
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/bump-version.sh" minor
