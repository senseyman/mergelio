#!/usr/bin/env bash
#
# bump-patch.sh — bugfix release: MAJOR.MINOR.PATCH+BUILD → MAJOR.MINOR.(PATCH+1)+(BUILD+1).
#
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/bump-version.sh" patch
