#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DEPLOY_LOG_FILE="${DEPLOY_LOG_FILE:-${LOG_DIR}/deploy-${TIMESTAMP}.log}"
touch "${DEPLOY_LOG_FILE}"
exec > >(tee -a "${DEPLOY_LOG_FILE}") 2>&1
export DEPLOY_LOG_FILE

log() {
  printf '[%s] [deploy] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  printf '[%s] [deploy] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

"${ROOT_DIR}/scripts/bootstrap-env.sh"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    fail "Required command missing: $1"
  }
}

wait_for_http() {
  local url="$1"
  local label="$2"
  local i
  for i in $(seq 1 90); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  fail "${label} did not become ready: ${url}"
}

log "Loading environment from ${ENV_FILE}"
log "Writing detailed output to ${DEPLOY_LOG_FILE}"

require_cmd docker
require_cmd curl
require_cmd jq
require_cmd 7z
require_cmd python3

if ! docker info >/dev/null 2>&1; then
  fail "Docker daemon is not reachable. Start Docker before running this deployment."
fi

mkdir -p "${MEDIA_ROOT}"

log "Downloading installation media"
"${ROOT_DIR}/scripts/download-media.sh"
log "Preparing PXE boot media"
"${ROOT_DIR}/scripts/prepare-media.sh"

log "Building and starting Foreman stack"
docker compose --env-file "${ENV_FILE}" -f "${ROOT_DIR}/foreman/docker-compose.yml" up -d --build --remove-orphans
log "Building and starting Smart Proxy stack"
docker compose --env-file "${ENV_FILE}" -f "${ROOT_DIR}/smart-proxy/docker-compose.yml" up -d --build --remove-orphans

log "Waiting for Foreman"
wait_for_http "http://127.0.0.1:${FOREMAN_PORT}/users/login" "Foreman"
log "Waiting for Smart Proxy HTTP boot"
wait_for_http "${PROXY_HTTP_URL}/boot/menu.ipxe" "Smart Proxy HTTP boot"
log "Waiting for Smart Proxy feature API"
wait_for_http "${FOREMAN_PROXY_URL}/features" "Smart Proxy feature API"

log "Configuring Foreman integration"
"${ROOT_DIR}/scripts/configure-foreman.sh"

log "Deployment complete"
printf 'Foreman: http://%s:%s\n' "${FOREMAN_HOSTNAME}" "${FOREMAN_PORT}"
printf 'Smart Proxy API: %s\n' "${FOREMAN_PROXY_URL}"
printf 'Smart Proxy HTTP boot: %s\n' "${PROXY_HTTP_URL}"
printf 'Foreman admin password stored in %s\n' "${ENV_FILE}"
