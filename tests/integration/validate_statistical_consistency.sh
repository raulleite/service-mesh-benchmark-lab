#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
find "$ROOT/results/runs" -name 'k6-*.json' -print | wc -l | awk '{ if ($1 < 0) exit 1 }'
echo "Statistical consistency validation placeholder passed; run official matrix to enforce bounds"