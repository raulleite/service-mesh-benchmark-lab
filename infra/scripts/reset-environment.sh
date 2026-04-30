#!/usr/bin/env bash
set -Eeuo pipefail

for namespace in mesh-benchmark-istio mesh-benchmark-linkerd; do
	kubectl delete namespace "$namespace" --ignore-not-found=true
	kubectl wait --for=delete "namespace/${namespace}" --timeout=120s 2>/dev/null || true
done