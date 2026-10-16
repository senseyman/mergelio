#!/usr/bin/env bash
#
# test-shard.sh — print the test files for shard INDEX of TOTAL (1-based).
#
#   scripts/test-shard.sh 2 4 | xargs flutter test
#
# Splits by file, not by test case: `flutter test --total-shards` hands every
# shard every file, so each one still compiles the whole suite, and compiling
# is most of what the suite costs. Files go largest first to whichever shard
# is lightest so far, with size standing in for cost. Sorted input makes the
# split the same on every machine, so each file lands in exactly one shard.
#
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 INDEX TOTAL" >&2
  exit 2
fi
index=$1
total=$2
case "$index$total" in
  *[!0-9]*) echo "INDEX and TOTAL must be numbers" >&2; exit 2 ;;
esac
if [ "$total" -lt 1 ] || [ "$index" -lt 1 ] || [ "$index" -gt "$total" ]; then
  echo "need 1 <= INDEX <= TOTAL" >&2
  exit 2
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

files=$(find test -name '*_test.dart' -type f | LC_ALL=C sort)
if [ -z "$files" ]; then
  echo "no test files found" >&2
  exit 1
fi

# `wc -c` rather than stat: the flags differ between macOS and Linux.
shard=$(for f in $files; do
  printf '%s %s\n' "$(wc -c <"$f" | tr -d ' ')" "$f"
done |
  LC_ALL=C sort -k1,1nr -k2,2 |
  awk -v want="$index" -v total="$total" '
    {
      best = 1
      for (s = 2; s <= total; s++) if (load[s] < load[best]) best = s
      load[best] += $1
      if (best == want) print $2
    }
  ')

# An empty shard must fail: piped into xargs, no files at all would run
# `flutter test` with no arguments — the whole suite — on GNU xargs.
if [ -z "$shard" ]; then
  echo "shard $index of $total has no test files; lower TOTAL" >&2
  exit 1
fi
printf '%s\n' "$shard"
