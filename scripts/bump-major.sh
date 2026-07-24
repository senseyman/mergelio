#!/usr/bin/env bash
#
# bump-major.sh — major release: MAJOR.MINOR.PATCH+BUILD → (MAJOR+1).0.0+(BUILD+1).
#
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/bump-version.sh" major
