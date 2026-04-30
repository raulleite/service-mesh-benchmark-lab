#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test -f "$ROOT/load/k6/mesh-benchmark.js"
grep -q '1000' "$ROOT/load/k6/scenarios.js"
echo "Repeatability inputs are present"