#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MESH="${2:-${MESH:-istio}}"

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

default_target_endpoint_for_mesh() {
  case "$1" in
    istio) printf 'http://127.0.0.1:30080/invoke\n' ;;
    linkerd) printf 'http://127.0.0.1:30082/invoke\n' ;;
    *)
      printf 'Unsupported mesh %s\n' "$1" >&2
      exit 1
      ;;
  esac
}

default_prometheus_api_for_mesh() {
  case "$1" in
    istio) printf '%s\n' "${ISTIO_PROMETHEUS_API:-http://127.0.0.1:30090/api/v1/query}" ;;
    linkerd) printf '%s\n' "${LINKERD_PROMETHEUS_API:-http://127.0.0.1:30090/api/v1/query}" ;;
    *)
      printf 'Unsupported mesh %s\n' "$1" >&2
      exit 1
      ;;
  esac
}

default_k6_api_address_for_mesh() {
  case "$1" in
    istio) printf '127.0.0.1:6565\n' ;;
    linkerd) printf '127.0.0.1:6566\n' ;;
    *)
      printf 'Unsupported mesh %s\n' "$1" >&2
      exit 1
      ;;
  esac
}

run_all_meshes() {
  local istio_pid
  local linkerd_pid
  local status=0

  ISTIO_TARGET_ENDPOINT="${ISTIO_TARGET_ENDPOINT:-$(default_target_endpoint_for_mesh istio)}"
  LINKERD_TARGET_ENDPOINT="${LINKERD_TARGET_ENDPOINT:-$(default_target_endpoint_for_mesh linkerd)}"
  ISTIO_PROMETHEUS_API="${ISTIO_PROMETHEUS_API:-$(default_prometheus_api_for_mesh istio)}"
  LINKERD_PROMETHEUS_API="${LINKERD_PROMETHEUS_API:-$(default_prometheus_api_for_mesh linkerd)}"

  echo "Running istio and linkerd benchmarks in parallel"

  ISTIO_PROMETHEUS_API="$ISTIO_PROMETHEUS_API" "$0" "$ISTIO_TARGET_ENDPOINT" istio &
  istio_pid=$!

  LINKERD_PROMETHEUS_API="$LINKERD_PROMETHEUS_API" "$0" "$LINKERD_TARGET_ENDPOINT" linkerd &
  linkerd_pid=$!

  if ! wait "$istio_pid"; then
    echo "Istio benchmark failed" >&2
    status=1
  fi

  if ! wait "$linkerd_pid"; then
    echo "Linkerd benchmark failed" >&2
    status=1
  fi

  return "$status"
}

if [[ "$MESH" == "all" ]]; then
  run_all_meshes
  exit 0
fi

BENCHMARK_NAMESPACE="${BENCHMARK_NAMESPACE:-$(namespace_for_mesh "$MESH")}"
TARGET_ENDPOINT="${1:-${TARGET_ENDPOINT:-$(default_target_endpoint_for_mesh "$MESH")}}"
K6_API_ADDRESS="${K6_API_ADDRESS:-$(default_k6_api_address_for_mesh "$MESH")}"
RUN_ID="run-$(date -u +%Y%m%d%H%M%S)-${MESH}"
OUT_DIR="$ROOT/results/runs/$RUN_ID"
SHARED_RESULTS_ROOT="${SHARED_RESULTS_ROOT:-/var/lib/service-mesh/benchmark-summaries}"
PROMETHEUS_API="${PROMETHEUS_API:-$(default_prometheus_api_for_mesh "$MESH")}"
mkdir -p "$OUT_DIR"

STATE_ROOT_LOCAL="$ROOT/results/runs/.state"
STATE_ROOT_SHARED="$SHARED_RESULTS_ROOT/.state"
KNOWN_TOPOLOGIES=(two-hop three-hop)

prune_run_directories() {
  local runs_root="$1"
  local mesh="$2"
  local keep_count="${3:-2}"
  local run_dirs=()
  local prune_count index

  [[ -d "$runs_root" ]] || return 0

  while IFS= read -r run_dir; do
    run_dirs+=("$run_dir")
  done < <(find "$runs_root" -mindepth 1 -maxdepth 1 -type d -name "run-*-${mesh}" | sort)

  if (( ${#run_dirs[@]} <= keep_count )); then
    return 0
  fi

  prune_count=$(( ${#run_dirs[@]} - keep_count ))
  for ((index = 0; index < prune_count; index++)); do
    rm -rf "${run_dirs[$index]}"
  done
}

write_execution_state() {
  local topology="$1"
  local active="$2"
  local updated_at state_root state_file

  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  for state_root in "$STATE_ROOT_LOCAL" "$STATE_ROOT_SHARED"; do
    mkdir -p "$state_root"
    state_file="$state_root/${MESH}-${topology}.json"
    jq -n \
      --arg runId "$RUN_ID" \
      --arg mesh "$MESH" \
      --arg topology "$topology" \
      --arg targetEndpoint "$TARGET_ENDPOINT" \
      --arg updatedAt "$updated_at" \
      --argjson active "$active" \
      '{
        runId: $runId,
        mesh: $mesh,
        topology: $topology,
        targetEndpoint: $targetEndpoint,
        updatedAt: $updatedAt,
        active: $active
      }' > "$state_file"
  done
}

reset_execution_states() {
  local topology

  for topology in "${KNOWN_TOPOLOGIES[@]}"; do
    write_execution_state "$topology" false
  done
}

current_running_pod_regex() {
  local pod_regex

  if [[ -z "${KUBECONFIG:-}" ]] || ! command -v kubectl >/dev/null 2>&1; then
    printf '^service-entry-.*$\n'
    return 0
  fi

  pod_regex="$(kubectl -n "$BENCHMARK_NAMESPACE" get pods --field-selector=status.phase=Running -o json \
    | jq -r '[.items[].metadata.name] | map(select(length > 0)) | if length == 0 then empty else "^(" + join("|") + ")$" end')"

  if [[ -z "$pod_regex" ]]; then
    return 1
  fi

  printf '%s\n' "$pod_regex"
}

query_prometheus_scalar() {
  local query="$1"
  local response

  if ! response="$(curl -fsS -G --data-urlencode "query=${query}" "$PROMETHEUS_API" 2>/dev/null)"; then
    return 1
  fi

  jq -r '.data.result[0].value[1] // empty' <<<"$response"
}

capture_sidecar_cpu_snapshot() {
  local pod_regex usage_query limit_query usage_value limit_value timestamp attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if ! pod_regex="$(current_running_pod_regex)"; then
      sleep 5
      continue
    fi

    usage_query="sum(container_cpu_usage_seconds_total{namespace=\"${BENCHMARK_NAMESPACE}\",pod=~\"${pod_regex}\",container=~\"istio-proxy|linkerd-proxy\"})"
    limit_query="sum((kube_pod_container_resource_limits{namespace=\"${BENCHMARK_NAMESPACE}\",pod=~\"${pod_regex}\",container=~\"istio-proxy|linkerd-proxy\",resource=\"cpu\",unit=\"core\"}) or (kube_pod_init_container_resource_limits{namespace=\"${BENCHMARK_NAMESPACE}\",pod=~\"${pod_regex}\",container=~\"istio-proxy|linkerd-proxy\",resource=\"cpu\",unit=\"core\"}))"

    usage_value="$(query_prometheus_scalar "$usage_query" || true)"
    limit_value="$(query_prometheus_scalar "$limit_query" || true)"

    if [[ -n "$usage_value" && -n "$limit_value" ]]; then
      timestamp="$(date +%s)"
      printf '%s;%s;%s\n' "$usage_value" "$limit_value" "$timestamp"
      return 0
    fi

    sleep 10
  done

  printf '0;0;%s\n' "$(date +%s)"
}

calculate_sidecar_cpu_limit_percent() {
  local start_usage="$1"
  local end_usage="$2"
  local cpu_limit_cores="$3"
  local start_timestamp="$4"
  local end_timestamp="$5"

  awk -v start_usage="$start_usage" \
      -v end_usage="$end_usage" \
      -v cpu_limit_cores="$cpu_limit_cores" \
      -v start_timestamp="$start_timestamp" \
      -v end_timestamp="$end_timestamp" '
    BEGIN {
      duration = end_timestamp - start_timestamp
      usage_delta = end_usage - start_usage

      if (duration <= 0 || cpu_limit_cores <= 0 || usage_delta < 0) {
        print 0
        exit
      }

      print (100 * (usage_delta / duration) / cpu_limit_cores)
    }
  '
}

write_summary() {
  local topology="$1"
  local start_snapshot="$2"
  local end_snapshot="$3"
  local summary_path="$OUT_DIR/summary-${topology}.json"
  local k6_path="$OUT_DIR/k6-${topology}.json"
  local generated_at rps p99 sidecar_cpu_limit_percent
  local start_usage start_limit start_timestamp end_usage end_limit end_timestamp cpu_limit_cores

  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  rps="$(jq '.metrics.http_reqs.rate // 0' "$k6_path")"
  p99="$(jq '.metrics.http_req_duration["p(99)"] // 0' "$k6_path")"
  IFS=';' read -r start_usage start_limit start_timestamp <<<"$start_snapshot"
  IFS=';' read -r end_usage end_limit end_timestamp <<<"$end_snapshot"

  cpu_limit_cores="$end_limit"
  if [[ -z "$cpu_limit_cores" || "$cpu_limit_cores" == "0" ]]; then
    cpu_limit_cores="$start_limit"
  fi

  sidecar_cpu_limit_percent="$(calculate_sidecar_cpu_limit_percent "$start_usage" "$end_usage" "$cpu_limit_cores" "$start_timestamp" "$end_timestamp")"

  jq -n \
    --arg runId "$RUN_ID" \
    --arg mesh "$MESH" \
    --arg topology "$topology" \
    --arg targetEndpoint "$TARGET_ENDPOINT" \
    --arg generatedAt "$generated_at" \
    --argjson rps "$rps" \
    --argjson p99LatencyMs "$p99" \
    --argjson sidecarCpuLimitPercent "$sidecar_cpu_limit_percent" \
    '{
      runId: $runId,
      mesh: $mesh,
      topology: $topology,
      targetEndpoint: $targetEndpoint,
      generatedAt: $generatedAt,
      rps: $rps,
      p99LatencyMs: $p99LatencyMs,
      sidecarCpuLimitPercent: $sidecarCpuLimitPercent
    }' > "$summary_path"
}

sync_shared_summaries() {
  local shared_out_dir="$SHARED_RESULTS_ROOT/$RUN_ID"

  if ! mkdir -p "$shared_out_dir" 2>/dev/null; then
    echo "Shared benchmark summary directory unavailable at $SHARED_RESULTS_ROOT; skipping shared summary sync." >&2
    return 0
  fi

  cp "$OUT_DIR"/summary-*.json "$shared_out_dir"/
  prune_run_directories "$SHARED_RESULTS_ROOT" "$MESH"
}

cleanup_benchmark_state() {
  reset_execution_states
}

trap cleanup_benchmark_state EXIT
reset_execution_states

benchmark_status=0

for topology in two-hop three-hop; do
  write_execution_state "$topology" true
  start_snapshot="$(capture_sidecar_cpu_snapshot)"
  echo "Running ${topology} against ${TARGET_ENDPOINT}"
  if ! TARGET_ENDPOINT="$TARGET_ENDPOINT" TOPOLOGY="$topology" K6_SUMMARY_EXPORT="$OUT_DIR/k6-${topology}.json" k6 run --address "$K6_API_ADDRESS" "$ROOT/load/k6/mesh-benchmark.js"; then
    echo "Benchmark failed for ${MESH}/${topology}; continuing to the next topology" >&2
    benchmark_status=1
  fi
  end_snapshot="$(capture_sidecar_cpu_snapshot)"
  if [[ -f "$OUT_DIR/k6-${topology}.json" ]]; then
    write_summary "$topology" "$start_snapshot" "$end_snapshot"
  else
    echo "Skipping summary for ${MESH}/${topology}; k6 output was not generated" >&2
  fi
  write_execution_state "$topology" false
done

jq -n --arg runId "$RUN_ID" --arg mesh "$MESH" --arg endpoint "$TARGET_ENDPOINT" '{runId:$runId, mesh:$mesh, endpoint:$endpoint, generatedAt:now|todate}' > "$OUT_DIR/environment-metadata.json"
sync_shared_summaries
prune_run_directories "$ROOT/results/runs" "$MESH"
echo "Results saved to $OUT_DIR"
exit "$benchmark_status"