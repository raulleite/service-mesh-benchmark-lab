#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESH="${MESH:-istio}"
SETUP_ROLE="${SETUP_ROLE:-single-node}"
TARGET_ENDPOINT="${TARGET_ENDPOINT:-}"
VERBOSE="${VERBOSE:-0}"
SUDO_USER_NAME="${SUDO_USER_NAME:-}"
SUDO_PASSWORD="${SUDO_PASSWORD:-}"
SUDO_PASSWORDLESS="${SUDO_PASSWORDLESS:-auto}"
SUDO_USER_HOME=""
KUBECONFIG_PATH=""
ISTIO_VPS_IP="${ISTIO_VPS_IP:-}"
LINKERD_VPS_IP="${LINKERD_VPS_IP:-}"
ISTIO_TARGET_ENDPOINT="${ISTIO_TARGET_ENDPOINT:-}"
LINKERD_TARGET_ENDPOINT="${LINKERD_TARGET_ENDPOINT:-}"
ISTIO_PROMETHEUS_API="${ISTIO_PROMETHEUS_API:-}"
LINKERD_PROMETHEUS_API="${LINKERD_PROMETHEUS_API:-}"
RUN_BENCHMARK_ON_SETUP="${RUN_BENCHMARK_ON_SETUP:-auto}"

if [[ "$VERBOSE" == "1" ]]; then
  set -x
fi

log() { printf '[setup] %s\n' "$*"; }
fail() { printf '[setup] ERROR: %s\n' "$*" >&2; exit 1; }

role_requires_k3s() {
  [[ "$1" != "control-plane" ]]
}

role_requires_docker() {
  return 0
}

role_requires_k6() {
  [[ "$1" == "control-plane" || "$1" == "single-node" ]]
}

role_requires_grafana() {
  [[ "$1" == "control-plane" || "$1" == "single-node" ]]
}

role_requires_prometheus() {
  [[ "$1" != "control-plane" ]]
}

role_mesh() {
  case "$1" in
    istio-node) printf 'istio\n' ;;
    linkerd-node) printf 'linkerd\n' ;;
    single-node) printf '%s\n' "$MESH" ;;
    control-plane) printf 'none\n' ;;
    *) fail "Unsupported SETUP_ROLE '$1'. Use single-node, istio-node, linkerd-node, or control-plane." ;;
  esac
}

should_run_benchmark_on_setup() {
  case "$RUN_BENCHMARK_ON_SETUP" in
    1|true|TRUE|yes|YES)
      return 0
      ;;
    0|false|FALSE|no|NO)
      return 1
      ;;
    auto)
      [[ "$SETUP_ROLE" == "single-node" ]]
      ;;
    *)
      fail "Unsupported RUN_BENCHMARK_ON_SETUP value '$RUN_BENCHMARK_ON_SETUP'. Use auto, 1, or 0."
      ;;
  esac
}

default_target_endpoint_for_mesh() {
  case "$1" in
    istio) printf 'http://127.0.0.1:30080/invoke\n' ;;
    linkerd) printf 'http://127.0.0.1:30082/invoke\n' ;;
    *) fail "Unsupported mesh '$1'. Use MESH=istio, MESH=linkerd, or MESH=all." ;;
  esac
}

default_prometheus_api_for_mesh() {
  case "$1" in
    istio) printf 'http://127.0.0.1:30090/api/v1/query\n' ;;
    linkerd) printf 'http://127.0.0.1:30090/api/v1/query\n' ;;
    *) fail "Unsupported mesh '$1'. Use MESH=istio, MESH=linkerd, or MESH=all." ;;
  esac
}

configure_control_plane_endpoints() {
  if [[ -n "$ISTIO_VPS_IP" && -z "$ISTIO_TARGET_ENDPOINT" ]]; then
    ISTIO_TARGET_ENDPOINT="http://${ISTIO_VPS_IP}:30080/invoke"
  fi
  if [[ -n "$LINKERD_VPS_IP" && -z "$LINKERD_TARGET_ENDPOINT" ]]; then
    LINKERD_TARGET_ENDPOINT="http://${LINKERD_VPS_IP}:30082/invoke"
  fi
  if [[ -n "$ISTIO_VPS_IP" && -z "$ISTIO_PROMETHEUS_API" ]]; then
    ISTIO_PROMETHEUS_API="http://${ISTIO_VPS_IP}:30090/api/v1/query"
  fi
  if [[ -n "$LINKERD_VPS_IP" && -z "$LINKERD_PROMETHEUS_API" ]]; then
    LINKERD_PROMETHEUS_API="http://${LINKERD_VPS_IP}:30090/api/v1/query"
  fi
}

cleanup_conflicting_role_state() {
  if [[ "$SETUP_ROLE" == "control-plane" ]]; then
    if sudo_run test -x /usr/local/bin/k3s-uninstall.sh; then
      log "Removing existing k3s installation for control-plane role"
      sudo_run /usr/local/bin/k3s-uninstall.sh || true
    elif sudo_run test -x /usr/bin/k3s-uninstall.sh; then
      log "Removing existing k3s installation for control-plane role"
      sudo_run /usr/bin/k3s-uninstall.sh || true
    fi

    sudo_run rm -f /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/ctr >/dev/null 2>&1 || true
    sudo_run rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet /var/lib/cni /etc/cni >/dev/null 2>&1 || true
    return
  fi

  if sudo_run docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx grafana; then
    log "Removing standalone Grafana container for k3s-backed role"
    sudo_run docker rm -f grafana >/dev/null 2>&1 || true
  fi
}

validate_role_inputs() {
  case "$SETUP_ROLE" in
    single-node)
      ;;
    istio-node|linkerd-node)
      ;;
    control-plane)
      configure_control_plane_endpoints
      [[ -n "$ISTIO_TARGET_ENDPOINT" ]] || fail "control-plane requires ISTIO_TARGET_ENDPOINT or ISTIO_VPS_IP."
      [[ -n "$LINKERD_TARGET_ENDPOINT" ]] || fail "control-plane requires LINKERD_TARGET_ENDPOINT or LINKERD_VPS_IP."
      [[ -n "$ISTIO_PROMETHEUS_API" ]] || fail "control-plane requires ISTIO_PROMETHEUS_API or ISTIO_VPS_IP."
      [[ -n "$LINKERD_PROMETHEUS_API" ]] || fail "control-plane requires LINKERD_PROMETHEUS_API or LINKERD_VPS_IP."
      ;;
    *)
      fail "Unsupported SETUP_ROLE '$SETUP_ROLE'. Use single-node, istio-node, linkerd-node, or control-plane."
      ;;
  esac
}

wait_for_http_ok() {
  local url="$1"
  local attempts="${2:-30}"
  local sleep_seconds="${3:-5}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done

  return 1
}

resolve_user_home() {
  getent passwd "$1" | cut -d: -f6
}

ask_credentials() {
  if [[ -z "$SUDO_USER_NAME" ]]; then
    read -r -p "Ubuntu sudo user: " SUDO_USER_NAME
  fi
  if [[ "$SUDO_PASSWORDLESS" == "1" ]]; then
    SUDO_PASSWORD="__PASSWORDLESS__"
  elif [[ -z "$SUDO_PASSWORD" ]]; then
    read -r -s -p "Sudo password: " SUDO_PASSWORD
    printf '\n'
  fi
  id "$SUDO_USER_NAME" >/dev/null 2>&1 || fail "User '$SUDO_USER_NAME' does not exist on this Ubuntu VPS."
  SUDO_USER_HOME="$(resolve_user_home "$SUDO_USER_NAME")"
  [[ -n "$SUDO_USER_HOME" ]] || fail "Could not resolve home directory for '$SUDO_USER_NAME'."
  KUBECONFIG_PATH="$SUDO_USER_HOME/.kube/config"
}

sudo_run() {
  if [[ "$SUDO_PASSWORDLESS" == "1" ]]; then
    sudo -n -u root "$@"
  else
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -u root "$@"
  fi
}

sudo_as_user() {
  if [[ "$SUDO_PASSWORDLESS" == "1" ]]; then
    sudo -n -u "$SUDO_USER_NAME" "$@"
  else
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -u "$SUDO_USER_NAME" "$@"
  fi
}

require_ubuntu_vps() {
  [[ -f /etc/os-release ]] || fail "Could not detect the host operating system."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || fail "This setup script targets Ubuntu VPS hosts. Detected '${ID:-unknown}'."
}

validate_sudo_access() {
  if sudo -n true >/dev/null 2>&1; then
    SUDO_PASSWORDLESS="1"
    SUDO_PASSWORD="__PASSWORDLESS__"
    return
  fi

  [[ "$SUDO_PASSWORDLESS" != "1" ]] || fail "Passwordless sudo was requested but is not available for '$SUDO_USER_NAME'."
  printf '%s\n' "$SUDO_PASSWORD" | sudo -S -v >/dev/null 2>&1 || fail "Invalid sudo password or missing sudo privileges for '$SUDO_USER_NAME'."
}

install_system_dependencies() {
  log "Updating apt packages"
  sudo_run apt-get update -y
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git gnupg lsb-release ufw jq unzip tar apt-transport-https software-properties-common
}

install_docker() {
  role_requires_docker "$SETUP_ROLE" || return 0

  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed"
  else
    log "Installing Docker"
    sudo_run bash -c "curl -fsSL https://get.docker.com | sh"
  fi
  sudo_run usermod -aG docker "$SUDO_USER_NAME"
  sudo_run systemctl enable --now docker
}

install_k3s() {
  role_requires_k3s "$SETUP_ROLE" || return 0

  if command -v kubectl >/dev/null 2>&1 && sudo_run test -f /etc/rancher/k3s/k3s.yaml; then
    log "k3s already installed"
  else
    log "Installing k3s single-node Kubernetes"
    sudo_run env INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --disable traefik" bash -c "curl -sfL https://get.k3s.io | sh -"
  fi
  sudo_run mkdir -p "$SUDO_USER_HOME/.kube"
  sudo_run cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_PATH"
  sudo_run chown -R "$SUDO_USER_NAME:$SUDO_USER_NAME" "$SUDO_USER_HOME/.kube"
  export KUBECONFIG="$KUBECONFIG_PATH"
}

install_k6() {
  role_requires_k6 "$SETUP_ROLE" || return 0

  if command -v k6 >/dev/null 2>&1; then
    log "k6 already installed"
    return
  fi
  log "Installing k6"
  sudo_run gpg -k || true
  sudo_run bash -c "curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg"
  echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo_run tee /etc/apt/sources.list.d/k6.list >/dev/null
  sudo_run apt-get update -y
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y k6
}

install_helm() {
  role_requires_k3s "$SETUP_ROLE" || return 0

  if command -v helm >/dev/null 2>&1; then
    log "Helm already installed"
    return
  fi
  log "Installing Helm"
  sudo_run bash -c "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
}

install_gateway_api_crds() {
  role_requires_k3s "$SETUP_ROLE" || return 0

  if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    log "Gateway API CRDs already installed"
    return
  fi

  log "Installing Gateway API CRDs"
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
}

install_mesh_clis() {
  local mesh_role

  mesh_role="$(role_mesh "$SETUP_ROLE")"

  if ! command -v istioctl >/dev/null 2>&1; then
    if [[ "$mesh_role" == "istio" || "$mesh_role" == "all" || "$SETUP_ROLE" == "single-node" ]]; then
      log "Installing istioctl"
      local istio_tmp
      istio_tmp="$(mktemp -d)"
      pushd "$istio_tmp" >/dev/null
      curl -L https://istio.io/downloadIstio | env ISTIO_VERSION="${ISTIO_VERSION:-}" sh -
      sudo_run install -m 0755 istio-*/bin/istioctl /usr/local/bin/istioctl
      popd >/dev/null
      rm -rf "$istio_tmp"
    fi
  fi
  if ! command -v linkerd >/dev/null 2>&1; then
    if [[ "$mesh_role" == "linkerd" || "$mesh_role" == "all" || "$SETUP_ROLE" == "single-node" ]]; then
      log "Installing linkerd CLI"
      sudo_as_user env HOME="$SUDO_USER_HOME" bash -c "curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh"
      sudo_run install -m 0755 "$SUDO_USER_HOME/.linkerd2/bin/linkerd" /usr/local/bin/linkerd
    fi
  fi
}

configure_firewall() {
  log "Configuring ufw"
  sudo_run ufw --force reset
  sudo_run ufw default deny incoming
  sudo_run ufw default allow outgoing
  sudo_run ufw allow OpenSSH
  if role_requires_k3s "$SETUP_ROLE"; then
    sudo_run ufw allow 6443/tcp comment 'Kubernetes API'
    sudo_run ufw allow 10250/tcp comment 'kubelet'
    sudo_run ufw allow 8472/udp comment 'flannel vxlan'
  fi
  case "$SETUP_ROLE" in
    single-node)
      sudo_run ufw allow 30080/tcp comment 'benchmark target service-entry'
      sudo_run ufw allow 30081/tcp comment 'benchmark runner API'
      sudo_run ufw allow 30082/tcp comment 'benchmark target service-entry linkerd'
      sudo_run ufw allow 30083/tcp comment 'benchmark runner API linkerd'
      sudo_run ufw allow 30090/tcp comment 'prometheus'
      sudo_run ufw allow 30300/tcp comment 'grafana'
      ;;
    istio-node)
      sudo_run ufw allow 30080/tcp comment 'istio benchmark target service-entry'
      sudo_run ufw allow 30081/tcp comment 'istio benchmark runner API'
      sudo_run ufw allow 30090/tcp comment 'istio prometheus'
      ;;
    linkerd-node)
      sudo_run ufw allow 30082/tcp comment 'linkerd benchmark target service-entry'
      sudo_run ufw allow 30083/tcp comment 'linkerd benchmark runner API'
      sudo_run ufw allow 30090/tcp comment 'linkerd prometheus'
      ;;
    control-plane)
      sudo_run ufw allow 30300/tcp comment 'grafana'
      ;;
  esac
  sudo_run ufw --force enable
}

prepare_shared_benchmark_storage() {
  log "Preparing shared benchmark summary storage"
  sudo_run mkdir -p /var/lib/service-mesh/benchmark-summaries
  sudo_run chown -R "$SUDO_USER_NAME:$SUDO_USER_NAME" /var/lib/service-mesh
}

install_mesh() {
  local mesh_role

  mesh_role="$(role_mesh "$SETUP_ROLE")"
  case "$mesh_role" in
    istio)
      log "Installing Istio"
      istioctl install -y --set profile=minimal
      ;;
    linkerd)
      log "Installing Linkerd"
      install_gateway_api_crds
      linkerd check --pre || true
      linkerd install --crds | kubectl apply -f -
      linkerd install | kubectl apply -f -
      linkerd check || true
      ;;
    all)
      log "Installing Istio"
      istioctl install -y --set profile=minimal
      log "Installing Linkerd"
      install_gateway_api_crds
      linkerd check --pre || true
      linkerd install --crds | kubectl apply -f -
      linkerd install | kubectl apply -f -
      linkerd check || true
      ;;
    none)
      ;;
    *) fail "Unsupported mesh '$MESH'. Use MESH=istio, MESH=linkerd, or MESH=all." ;;
  esac
}

deploy_observability() {
  if role_requires_prometheus "$SETUP_ROLE"; then
    log "Deploying Prometheus"
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update
    kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
    helm upgrade --install prometheus prometheus-community/prometheus -n observability -f "$PROJECT_ROOT/infra/observability/prometheus/prometheus-values.yaml"
    kubectl -n observability rollout status deploy/prometheus-server --timeout=180s
  fi

  if role_requires_grafana "$SETUP_ROLE"; then
    deploy_grafana
  fi
}

deploy_grafana() {
  if [[ "$SETUP_ROLE" == "control-plane" ]]; then
    log "Deploying Grafana via Docker"
    sudo_run docker rm -f grafana >/dev/null 2>&1 || true
    sudo_run mkdir -p /var/lib/service-mesh/grafana
      sudo_run chown -R 472:472 /var/lib/service-mesh/grafana
    sudo_run docker run -d \
      --name grafana \
      --restart unless-stopped \
      -p 30300:3000 \
      -e GF_SECURITY_ADMIN_PASSWORD=admin \
      -v /var/lib/service-mesh/grafana:/var/lib/grafana \
      grafana/grafana:12.0.2 >/dev/null
    wait_for_http_ok "http://127.0.0.1:30300/api/health" 36 5 || fail "Grafana API did not become ready on port 30300."
    import_grafana_dashboards
    return
  fi

  log "Deploying Grafana"
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update
  kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install grafana grafana/grafana -n observability --set service.type=NodePort --set service.nodePort=30300 --set adminPassword=admin --set persistence.enabled=false
  kubectl -n observability rollout status deploy/grafana --timeout=180s
  import_grafana_dashboards
}

import_grafana_dashboards() {
  local grafana_api="http://127.0.0.1:30300/api"
  local dashboard_file
  local dashboard_uid
  local dashboard_json
  local payload

  log "Importing Grafana dashboards"
  wait_for_http_ok "$grafana_api/health" 36 5 || fail "Grafana API did not become ready on port 30300."
  ensure_grafana_prometheus_datasources

  for dashboard_file in "$PROJECT_ROOT"/infra/observability/grafana/dashboards/*.json; do
    dashboard_uid="$(basename "$dashboard_file" .json)"
    dashboard_json="$(jq --arg uid "$dashboard_uid" '. + {id:null, uid:$uid, schemaVersion:(.schemaVersion // 41), version:(.version // 1)}' "$dashboard_file")"
    payload="$(jq -n --argjson dashboard "$dashboard_json" '{dashboard:$dashboard, overwrite:true}')"

    curl -fsS -u admin:admin \
      -H 'Content-Type: application/json' \
      -X POST \
      "$grafana_api/dashboards/db" \
      -d "$payload" >/dev/null
  done
}

ensure_grafana_prometheus_datasources() {
  if [[ "$SETUP_ROLE" == "control-plane" ]]; then
    ensure_grafana_datasource "Prometheus Istio" "prometheus-istio" "$(prometheus_datasource_url "$ISTIO_PROMETHEUS_API")"
    ensure_grafana_datasource "Prometheus Linkerd" "prometheus-linkerd" "$(prometheus_datasource_url "$LINKERD_PROMETHEUS_API")"
    ensure_grafana_datasource "Prometheus" "prometheus" "$(prometheus_datasource_url "$ISTIO_PROMETHEUS_API")"
    return
  fi

  ensure_grafana_datasource "Prometheus" "prometheus" "http://prometheus-server.observability.svc.cluster.local"
}

prometheus_datasource_url() {
  printf '%s\n' "${1%/api/v1/query}"
}

ensure_grafana_datasource() {
  local name="$1"
  local uid="$2"
  local url="$3"
  local grafana_api="http://127.0.0.1:30300/api"
  local payload

  payload="$(jq -n \
    --arg name "$name" \
    --arg uid "$uid" \
    --arg url "$url" \
    '{name:$name, uid:$uid, type:"prometheus", access:"proxy", url:$url, isDefault:($uid == "prometheus")}')"

  if curl -fsS -u admin:admin "$grafana_api/datasources/uid/$uid" >/dev/null 2>&1; then
    curl -fsS -u admin:admin \
      -H 'Content-Type: application/json' \
      -X PUT \
      "$grafana_api/datasources/uid/$uid" \
      -d "$payload" >/dev/null
    return 0
  fi

  curl -fsS -u admin:admin \
    -H 'Content-Type: application/json' \
    -X POST \
    "$grafana_api/datasources" \
    -d "$payload" >/dev/null
}

run_project_automation() {
  export SUDO_PASSWORD
  export DOCKER_WITH_SUDO=1
  if role_requires_k3s "$SETUP_ROLE"; then
    export KUBECONFIG="$KUBECONFIG_PATH"
  fi

  case "$SETUP_ROLE" in
    single-node)
      "$PROJECT_ROOT/scripts/build-images.sh"

      if [[ "$MESH" == "all" ]]; then
        "$PROJECT_ROOT/scripts/deploy.sh" all
        ISTIO_TARGET_ENDPOINT="${ISTIO_TARGET_ENDPOINT:-$(default_target_endpoint_for_mesh istio)}" \
        LINKERD_TARGET_ENDPOINT="${LINKERD_TARGET_ENDPOINT:-$(default_target_endpoint_for_mesh linkerd)}" \
          MESH=all "$PROJECT_ROOT/scripts/run-benchmark.sh"
        return
      fi

      TARGET_ENDPOINT="${TARGET_ENDPOINT:-$(default_target_endpoint_for_mesh "$MESH")}" \
        "$PROJECT_ROOT/scripts/deploy.sh" "$MESH"
      TARGET_ENDPOINT="${TARGET_ENDPOINT:-$(default_target_endpoint_for_mesh "$MESH")}" \
        "$PROJECT_ROOT/scripts/run-benchmark.sh" "$TARGET_ENDPOINT" "$MESH"
      ;;
    istio-node|linkerd-node)
      local role_mesh_name
      role_mesh_name="$(role_mesh "$SETUP_ROLE")"
      MESH="$role_mesh_name" "$PROJECT_ROOT/scripts/build-images.sh"
      "$PROJECT_ROOT/scripts/deploy.sh" "$role_mesh_name"
      ;;
    control-plane)
      if should_run_benchmark_on_setup; then
        ISTIO_TARGET_ENDPOINT="$ISTIO_TARGET_ENDPOINT" \
        LINKERD_TARGET_ENDPOINT="$LINKERD_TARGET_ENDPOINT" \
        ISTIO_PROMETHEUS_API="$ISTIO_PROMETHEUS_API" \
        LINKERD_PROMETHEUS_API="$LINKERD_PROMETHEUS_API" \
        MESH=all "$PROJECT_ROOT/scripts/run-benchmark.sh"
      else
        log "Skipping benchmark execution during control-plane setup. Run scripts/run-benchmark.sh explicitly when the environment is ready."
      fi
      ;;
  esac
}

main() {
  ask_credentials
  require_ubuntu_vps
  validate_role_inputs
  validate_sudo_access
  cleanup_conflicting_role_state
  install_system_dependencies
  install_docker
  install_k3s
  install_helm
  install_k6
  install_mesh_clis
  configure_firewall
  prepare_shared_benchmark_storage
  install_mesh
  deploy_observability
  run_project_automation
  log "External provider firewall premise: if your VPS has a security group, edge ACL, or NAT firewall, publish the role-specific ports configured by SETUP_ROLE outside this script."
  case "$SETUP_ROLE" in
    control-plane)
      log "Control-plane ready. Grafana: http://<vps-ip>:30300, Istio target: $ISTIO_TARGET_ENDPOINT, Linkerd target: $LINKERD_TARGET_ENDPOINT"
      ;;
    istio-node)
      log "Istio node ready. Service entry: http://<vps-ip>:30080/invoke, Prometheus: http://<vps-ip>:30090"
      ;;
    linkerd-node)
      log "Linkerd node ready. Service entry: http://<vps-ip>:30082/invoke, Prometheus: http://<vps-ip>:30090"
      ;;
    *)
      log "Environment ready. Grafana: http://<vps-ip>:30300, Prometheus: http://<vps-ip>:30090, Istio target: http://<vps-ip>:30080/invoke, Linkerd target: http://<vps-ip>:30082/invoke"
      ;;
  esac
}

main "$@"