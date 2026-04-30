#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
grep -R "replicas: 1" "$ROOT/infra/base/apps" >/dev/null
if grep -R "HorizontalPodAutoscaler\|autoscaling/v2" "$ROOT/infra" >/dev/null; then
  echo "Autoscaling resource detected" >&2
  exit 1
fi
echo "Environment parity files are valid"