#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
required=(RPS P99 CPU SIDECAR)

for dashboard in "$ROOT"/infra/observability/grafana/dashboards/*.json; do
  content="$(tr '[:lower:]' '[:upper:]' < "$dashboard")"
  for token in "${required[@]}"; do
    if ! grep -q "$token" <<<"$content"; then
      echo "Dashboard $dashboard is missing $token" >&2
      exit 1
    fi
  done
done

echo "Grafana dashboards expose required benchmark metrics"