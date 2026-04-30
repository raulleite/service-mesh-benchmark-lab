#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MESH="${1:-${MESH:-istio}}"

namespace_for_mesh() {
	case "$1" in
		istio) printf 'mesh-benchmark-istio\n' ;;
		linkerd) printf 'mesh-benchmark-linkerd\n' ;;
		*)
			printf 'Unsupported mesh %s\n' "$1" >&2
			exit 1
			;;
	esac
}

if [[ "$MESH" == "all" ]]; then
	meshes=(istio linkerd)
else
	meshes=("$MESH")
fi

deployments=(service-entry service-middle service-leaf benchmark-runner)

for mesh in "${meshes[@]}"; do
	NAMESPACE="$(namespace_for_mesh "$mesh")"
	existing_deployments=()

	for deployment in "${deployments[@]}"; do
		if kubectl -n "$NAMESPACE" get deploy "$deployment" >/dev/null 2>&1; then
			existing_deployments+=("$deployment")
		fi
	done

	kubectl apply -k "$ROOT/infra/clusters/${mesh}"

	for deployment in "${deployments[@]}"; do
		if [[ " ${existing_deployments[*]} " == *" ${deployment} "* ]]; then
			kubectl -n "$NAMESPACE" delete pod -l app="$deployment" --wait=true >/dev/null 2>&1 || true
		fi
		kubectl -n "$NAMESPACE" rollout status "deploy/${deployment}" --timeout=180s
	done
done