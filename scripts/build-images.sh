#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REGISTRY:-}"
TAG="${TAG:-local}"
IMAGES=(service-entry service-middle service-leaf benchmark-runner)

docker_run() {
  if [[ "${DOCKER_WITH_SUDO:-0}" == "1" ]]; then
    printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S docker "$@"
  else
    docker "$@"
  fi
}

cleanup_file() {
  if [[ "${DOCKER_WITH_SUDO:-0}" == "1" ]]; then
    printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S rm -f "$1"
  else
    rm -f "$1"
  fi
}

k3s_import() {
  local archive
  archive="$(mktemp)"
  docker_run save -o "$archive" "service-mesh/$1:${TAG}"
  if [[ "${DOCKER_WITH_SUDO:-0}" == "1" ]]; then
    printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S k3s ctr images import "$archive"
  else
    sudo k3s ctr images import "$archive"
  fi
  cleanup_file "$archive"
}

for image in "${IMAGES[@]}"; do
  docker_run build -t "service-mesh/${image}:${TAG}" -f "$ROOT/apps/${image}/Dockerfile" "$ROOT"
  if [[ -n "$REGISTRY" ]]; then
    docker_run tag "service-mesh/${image}:${TAG}" "${REGISTRY}/service-mesh/${image}:${TAG}"
    docker_run push "${REGISTRY}/service-mesh/${image}:${TAG}"
  elif command -v k3s >/dev/null 2>&1; then
    k3s_import "$image"
  fi
done