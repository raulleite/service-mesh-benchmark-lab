#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT="$ROOT/results/runs/official/grafana-dashboards.tar.gz"
mkdir -p "$(dirname "$OUT")"
tar -czf "$OUT" -C "$ROOT/infra/observability/grafana" dashboards
echo "Exported dashboards to $OUT"