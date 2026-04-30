#!/usr/bin/env bash
set -Eeuo pipefail

namespace_for_mesh() {
  case "$1" in
    istio) printf 'mesh-benchmark-istio\n' ;;
    linkerd) printf 'mesh-benchmark-linkerd\n' ;;
    *)
      echo "Unsupported mesh $1" >&2
      exit 1
      ;;
  esac
}

mesh="${MESH:-istio}"
namespace="${NAMESPACE:-$(namespace_for_mesh "$mesh")}"
expected_replicas="1"

for deploy in service-entry service-middle service-leaf benchmark-runner; do
  replicas="$(kubectl -n "$namespace" get deploy "$deploy" -o jsonpath='{.spec.replicas}')"
  if [[ "$replicas" != "$expected_replicas" ]]; then
    echo "Deployment $deploy has $replicas replicas; expected $expected_replicas" >&2
    exit 1
  fi
done

if kubectl -n "$namespace" get hpa 2>/dev/null | grep -q .; then
  echo "HPA resources are not allowed by the benchmark constitution" >&2
  exit 1
fi

echo "Parity verified for namespace $namespace"