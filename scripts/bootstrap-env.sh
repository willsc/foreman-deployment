#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command missing while building .env: %s\n' "$1" >&2
    exit 1
  }
}

require_cmd ip
require_cmd python3
require_cmd hostname

log() {
  printf '[%s] [bootstrap] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  printf '[%s] [bootstrap] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

trim_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "${value}"
}

get_env_value() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "${ENV_FILE}" 2>/dev/null | head -n1)"
  trim_quotes "${value}"
}

is_valid_proxy_mode() {
  case "$1" in
    managed|external) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_proxy_mode() {
  local reply selected
  printf 'Is there already a DHCP server on this LAN? [y/N]: ' >&2
  read -r reply || true
  case "${reply}" in
    [Yy]|[Yy][Ee][Ss])
      selected="external"
      ;;
    *)
      selected="managed"
      ;;
  esac
  printf '%s' "${selected}"
}

default_iface_from_proc() {
  awk '$2 == "00000000" {print $1; exit}' /proc/net/route 2>/dev/null || true
}

default_gw_from_proc() {
  awk '$2 == "00000000" {
    hex = $3
    if (length(hex) == 8) {
      printf "%d.%d.%d.%d\n", strtonum("0x" substr(hex,7,2)), strtonum("0x" substr(hex,5,2)), strtonum("0x" substr(hex,3,2)), strtonum("0x" substr(hex,1,2))
      exit
    }
  }' /proc/net/route 2>/dev/null || true
}

pick_first_global_iface() {
  ip -o -4 addr show scope global 2>/dev/null | awk '{print $2; exit}' || true
}

get_ipv4_cidr_for_iface() {
  local iface="$1"
  ip -o -4 addr show dev "${iface}" scope global 2>/dev/null | awk '{print $4; exit}' || true
}

get_default_iface() {
  local iface
  iface="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || true)"
  if [[ -z "${iface}" ]]; then
    iface="$(default_iface_from_proc)"
  fi
  if [[ -z "${iface}" ]]; then
    iface="$(pick_first_global_iface)"
  fi
  printf '%s' "${iface}"
}

get_default_gw() {
  local gw
  gw="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}' || true)"
  if [[ -z "${gw}" ]]; then
    gw="$(default_gw_from_proc)"
  fi
  printf '%s' "${gw}"
}

EXISTING_FOREMAN_PORT=8080
EXISTING_PROXY_MODE=managed
EXISTING_WINDOWS_URL=
EXISTING_WINDOWS_LANGUAGE="English International"
EXISTING_PLAYWRIGHT_IMAGE="mcr.microsoft.com/playwright/python:v1.52.0-noble"
EXISTING_PLAYWRIGHT_PYTHON_VERSION="1.52.0"
EXISTING_MEDIA_ROOT="${ROOT_DIR}/media"
EXISTING_FOREMAN_IMAGE="quay.io/foreman/foreman:3.18"
EXISTING_FOREMAN_DB_NAME="foreman"
EXISTING_FOREMAN_DB_USER="foreman"
EXISTING_FOREMAN_DB_PASSWORD="foreman"
EXISTING_UBUNTU_USERNAME="admin"
EXISTING_UBUNTU_PASSWORD="admin"
EXISTING_UBUNTU_REALNAME="Ubuntu Admin"
EXISTING_UBUNTU_HOSTNAME="ubuntu-client"
EXISTING_UBUNTU_LOCALE="en_GB.UTF-8"
EXISTING_UBUNTU_KEYBOARD="gb"
EXISTING_UBUNTU_TIMEZONE="Etc/UTC"
EXISTING_WINDOWS_IMAGE_NAME="Windows 11 Pro"
EXISTING_WINDOWS_ADMIN_USER="admin"
EXISTING_WINDOWS_ADMIN_PASSWORD="admin"
EXISTING_WINDOWS_COMPUTER_NAME="WIN11-%SERIAL%"
EXISTING_WINDOWS_LOCALE="en-GB"
EXISTING_WINDOWS_TARGET_DISK="0"
EXISTING_FOREMAN_PUBLIC_URL=
EXISTING_FOREMAN_HOSTNAME=
EXISTING_FOREMAN_PASSWORD=
EXISTING_PXE_INTERFACE=
REGENERATE=1
SELECTED_PROXY_MODE="${PROXY_DHCP_MODE:-}"

if [[ -f "${ENV_FILE}" ]]; then
  EXISTING_FOREMAN_PORT="$(get_env_value FOREMAN_PORT)"
  EXISTING_PROXY_MODE="$(get_env_value PROXY_DHCP_MODE)"
  EXISTING_WINDOWS_URL="$(get_env_value WINDOWS_11_ISO_URL)"
  EXISTING_WINDOWS_LANGUAGE="$(get_env_value WINDOWS_11_LANGUAGE)"
  EXISTING_PLAYWRIGHT_IMAGE="$(get_env_value PLAYWRIGHT_IMAGE)"
  EXISTING_PLAYWRIGHT_PYTHON_VERSION="$(get_env_value PLAYWRIGHT_PYTHON_VERSION)"
  EXISTING_MEDIA_ROOT="$(get_env_value MEDIA_ROOT)"
  EXISTING_FOREMAN_IMAGE="$(get_env_value FOREMAN_IMAGE)"
  EXISTING_FOREMAN_DB_NAME="$(get_env_value FOREMAN_DB_NAME)"
  EXISTING_FOREMAN_DB_USER="$(get_env_value FOREMAN_DB_USER)"
  EXISTING_FOREMAN_DB_PASSWORD="$(get_env_value FOREMAN_DB_PASSWORD)"
  EXISTING_UBUNTU_USERNAME="$(get_env_value UBUNTU_AUTOINSTALL_USERNAME)"
  EXISTING_UBUNTU_PASSWORD="$(get_env_value UBUNTU_AUTOINSTALL_PASSWORD)"
  EXISTING_UBUNTU_REALNAME="$(get_env_value UBUNTU_AUTOINSTALL_REALNAME)"
  EXISTING_UBUNTU_HOSTNAME="$(get_env_value UBUNTU_AUTOINSTALL_HOSTNAME)"
  EXISTING_UBUNTU_LOCALE="$(get_env_value UBUNTU_AUTOINSTALL_LOCALE)"
  EXISTING_UBUNTU_KEYBOARD="$(get_env_value UBUNTU_AUTOINSTALL_KEYBOARD)"
  EXISTING_UBUNTU_TIMEZONE="$(get_env_value UBUNTU_AUTOINSTALL_TIMEZONE)"
  EXISTING_WINDOWS_IMAGE_NAME="$(get_env_value WINDOWS_IMAGE_NAME)"
  EXISTING_WINDOWS_ADMIN_USER="$(get_env_value WINDOWS_LOCAL_ADMIN_USER)"
  EXISTING_WINDOWS_ADMIN_PASSWORD="$(get_env_value WINDOWS_LOCAL_ADMIN_PASSWORD)"
  EXISTING_WINDOWS_COMPUTER_NAME="$(get_env_value WINDOWS_COMPUTER_NAME)"
  EXISTING_WINDOWS_LOCALE="$(get_env_value WINDOWS_LOCALE)"
  EXISTING_WINDOWS_TARGET_DISK="$(get_env_value WINDOWS_TARGET_DISK)"
  EXISTING_FOREMAN_HOSTNAME="$(get_env_value FOREMAN_HOSTNAME)"
  EXISTING_FOREMAN_PASSWORD="$(get_env_value FOREMAN_ADMIN_PASSWORD)"
  EXISTING_PXE_INTERFACE="$(get_env_value PXE_INTERFACE)"
  EXISTING_FOREMAN_PUBLIC_URL="$(get_env_value FOREMAN_PUBLIC_URL)"

  EXISTING_FOREMAN_PORT="${EXISTING_FOREMAN_PORT:-8080}"
  EXISTING_PROXY_MODE="${EXISTING_PROXY_MODE:-managed}"
  EXISTING_WINDOWS_LANGUAGE="${EXISTING_WINDOWS_LANGUAGE:-English International}"
  EXISTING_PLAYWRIGHT_IMAGE="${EXISTING_PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright/python:v1.52.0-noble}"
  EXISTING_PLAYWRIGHT_PYTHON_VERSION="${EXISTING_PLAYWRIGHT_PYTHON_VERSION:-1.52.0}"
  EXISTING_MEDIA_ROOT="${EXISTING_MEDIA_ROOT:-${ROOT_DIR}/media}"
  EXISTING_FOREMAN_IMAGE="${EXISTING_FOREMAN_IMAGE:-quay.io/foreman/foreman:3.18}"
  EXISTING_FOREMAN_DB_NAME="${EXISTING_FOREMAN_DB_NAME:-foreman}"
  EXISTING_FOREMAN_DB_USER="${EXISTING_FOREMAN_DB_USER:-foreman}"
  EXISTING_FOREMAN_DB_PASSWORD="${EXISTING_FOREMAN_DB_PASSWORD:-foreman}"
  EXISTING_UBUNTU_USERNAME="${EXISTING_UBUNTU_USERNAME:-admin}"
  EXISTING_UBUNTU_PASSWORD="${EXISTING_UBUNTU_PASSWORD:-admin}"
  EXISTING_UBUNTU_REALNAME="${EXISTING_UBUNTU_REALNAME:-Ubuntu Admin}"
  EXISTING_UBUNTU_HOSTNAME="${EXISTING_UBUNTU_HOSTNAME:-ubuntu-client}"
  EXISTING_UBUNTU_LOCALE="${EXISTING_UBUNTU_LOCALE:-en_GB.UTF-8}"
  EXISTING_UBUNTU_KEYBOARD="${EXISTING_UBUNTU_KEYBOARD:-gb}"
  EXISTING_UBUNTU_TIMEZONE="${EXISTING_UBUNTU_TIMEZONE:-Etc/UTC}"
  EXISTING_WINDOWS_IMAGE_NAME="${EXISTING_WINDOWS_IMAGE_NAME:-Windows 11 Pro}"
  EXISTING_WINDOWS_ADMIN_USER="${EXISTING_WINDOWS_ADMIN_USER:-admin}"
  EXISTING_WINDOWS_ADMIN_PASSWORD="${EXISTING_WINDOWS_ADMIN_PASSWORD:-admin}"
  EXISTING_WINDOWS_COMPUTER_NAME="${EXISTING_WINDOWS_COMPUTER_NAME:-WIN11-%SERIAL%}"
  EXISTING_WINDOWS_LOCALE="${EXISTING_WINDOWS_LOCALE:-en-GB}"
  EXISTING_WINDOWS_TARGET_DISK="${EXISTING_WINDOWS_TARGET_DISK:-0}"

  if [[ -n "${EXISTING_FOREMAN_PASSWORD}" ]] && \
     [[ -n "${EXISTING_FOREMAN_PUBLIC_URL}" ]] && \
     [[ -n "${EXISTING_FOREMAN_IMAGE}" ]] && \
     [[ -n "${EXISTING_UBUNTU_USERNAME}" ]] && \
     [[ -n "${EXISTING_UBUNTU_PASSWORD}" ]] && \
     [[ -n "${EXISTING_WINDOWS_IMAGE_NAME}" ]] && \
     [[ -n "${EXISTING_WINDOWS_ADMIN_USER}" ]] && \
     [[ -n "${EXISTING_WINDOWS_ADMIN_PASSWORD}" ]] && \
     [[ -n "${EXISTING_WINDOWS_TARGET_DISK}" ]] && \
     [[ "${EXISTING_FOREMAN_HOSTNAME}" != "foreman.local" ]] && \
     [[ "${EXISTING_PXE_INTERFACE}" != "eth0" ]]; then
    REGENERATE=0
  fi
fi

if [[ -n "${SELECTED_PROXY_MODE}" ]]; then
  if ! is_valid_proxy_mode "${SELECTED_PROXY_MODE}"; then
    fail "Unsupported PROXY_DHCP_MODE '${SELECTED_PROXY_MODE}'. Use 'managed' or 'external'."
  fi
  if [[ "${SELECTED_PROXY_MODE}" != "${EXISTING_PROXY_MODE}" ]]; then
    REGENERATE=1
  fi
elif [[ -t 0 ]]; then
  SELECTED_PROXY_MODE="$(prompt_proxy_mode)"
  log "Selected DHCP mode: ${SELECTED_PROXY_MODE}"
  if [[ "${SELECTED_PROXY_MODE}" != "${EXISTING_PROXY_MODE}" ]]; then
    REGENERATE=1
  fi
else
  SELECTED_PROXY_MODE="${EXISTING_PROXY_MODE}"
fi

if ! is_valid_proxy_mode "${SELECTED_PROXY_MODE}"; then
  SELECTED_PROXY_MODE="managed"
fi

if [[ "${REGENERATE}" -eq 0 ]]; then
  log "DHCP mode confirmed as ${SELECTED_PROXY_MODE}"
  log "Reusing existing ${ENV_FILE}"
  exit 0
fi

DEFAULT_IFACE="$(get_default_iface)"

if [[ -z "${DEFAULT_IFACE}" ]]; then
  if [[ -f "${ENV_FILE}" ]]; then
    log "Unable to determine a usable network interface for PXE. Reusing existing ${ENV_FILE}"
    exit 0
  fi
  printf 'Unable to determine a usable network interface for PXE.\n' >&2
  exit 1
fi

IP_CIDR="$(get_ipv4_cidr_for_iface "${DEFAULT_IFACE}")"
if [[ -z "${IP_CIDR}" ]]; then
  if [[ -f "${ENV_FILE}" ]]; then
    log "Unable to determine an IPv4 address on interface ${DEFAULT_IFACE}. Reusing existing ${ENV_FILE}"
    exit 0
  fi
  printf 'Unable to determine an IPv4 address on interface %s.\n' "${DEFAULT_IFACE}" >&2
  exit 1
fi

DEFAULT_GW="$(get_default_gw)"
HOST_FQDN="$(hostname -f 2>/dev/null || hostname)"
HOST_DOMAIN="$(printf '%s' "${HOST_FQDN}" | cut -s -d. -f2-)"

if [[ -z "${HOST_DOMAIN}" ]]; then
  HOST_DOMAIN=localdomain
fi

SMART_PROXY_HOST="smartproxy.${HOST_DOMAIN}"
FOREMAN_FQDN="foreman.${HOST_DOMAIN}"
DNS_SERVERS="$(awk '/^nameserver / {print $2}' /etc/resolv.conf | grep -v '^127\.' | paste -sd, - || true)"
DNS_SERVERS="${DNS_SERVERS:-}"
if [[ -z "${DNS_SERVERS}" ]]; then
  DNS_SERVERS="$(resolvectl dns "${DEFAULT_IFACE}" 2>/dev/null | awk '{for (i = 3; i <= NF; i++) print $i}' | grep -E '^[0-9.]+$' | paste -sd, - || true)"
fi
if [[ -z "${DNS_SERVERS}" ]]; then
  DNS_SERVERS="1.1.1.1,8.8.8.8"
fi

eval "$(
python3 - "${IP_CIDR}" <<'PY'
import ipaddress
import sys

iface = ipaddress.ip_interface(sys.argv[1])
network = iface.network
usable_count = max(network.num_addresses - 2, 1)
first_host = int(network.network_address) + 1
last_host = int(network.broadcast_address) - 1 if network.num_addresses > 2 else first_host

start_offset = 99 if usable_count > 199 else max(9, usable_count // 4)
end_offset = 198 if usable_count > 199 else min(usable_count - 1, start_offset + max(10, usable_count // 8))

start = ipaddress.ip_address(min(first_host + start_offset, last_host))
end = ipaddress.ip_address(min(first_host + end_offset, last_host))

print(f"HOST_IP={iface.ip}")
print(f"PXE_SUBNET={network.network_address}")
print(f"PXE_NETMASK={network.netmask}")
print(f"PXE_DHCP_RANGE_START={start}")
print(f"PXE_DHCP_RANGE_END={end}")
PY
)"

ADMIN_PASSWORD="admin"

cat > "${ENV_FILE}" <<EOF
FOREMAN_VERSION=3.18
FOREMAN_IMAGE=${EXISTING_FOREMAN_IMAGE}
FOREMAN_HOSTNAME=${FOREMAN_FQDN}
FOREMAN_PUBLIC_URL=http://${HOST_IP}:${EXISTING_FOREMAN_PORT}
FOREMAN_PORT=${EXISTING_FOREMAN_PORT}
FOREMAN_ADMIN_USER=admin
FOREMAN_ADMIN_PASSWORD=${ADMIN_PASSWORD}
FOREMAN_ADMIN_EMAIL=admin@${HOST_DOMAIN}
FOREMAN_ORGANIZATION="Default Organization"
FOREMAN_LOCATION="Default Location"
FOREMAN_PROXY_NAME=${SMART_PROXY_HOST}
FOREMAN_PROXY_URL=http://${HOST_IP}:9090
PROXY_HTTP_URL=http://${HOST_IP}:8081
PROXY_TFTP_SERVER=${HOST_IP}
PROXY_DHCP_MODE=${SELECTED_PROXY_MODE}
PXE_INTERFACE=${DEFAULT_IFACE}
PXE_SUBNET=${PXE_SUBNET}
PXE_NETMASK=${PXE_NETMASK}
PXE_GATEWAY=${DEFAULT_GW}
PXE_DNS_SERVERS=${DNS_SERVERS}
PXE_DHCP_RANGE_START=${PXE_DHCP_RANGE_START}
PXE_DHCP_RANGE_END=${PXE_DHCP_RANGE_END}
PXE_NEXT_SERVER=${HOST_IP}
PXE_BOOTFILE_BIOS=undionly.kpxe
PXE_BOOTFILE_UEFI=ipxe.efi
PXE_DOMAIN=${HOST_DOMAIN}
MEDIA_ROOT=${EXISTING_MEDIA_ROOT}
WINDOWS_11_ISO_URL="${EXISTING_WINDOWS_URL}"
WINDOWS_11_LANGUAGE="${EXISTING_WINDOWS_LANGUAGE}"
PLAYWRIGHT_IMAGE=${EXISTING_PLAYWRIGHT_IMAGE}
PLAYWRIGHT_PYTHON_VERSION=${EXISTING_PLAYWRIGHT_PYTHON_VERSION}
FOREMAN_DB_NAME=${EXISTING_FOREMAN_DB_NAME}
FOREMAN_DB_USER=${EXISTING_FOREMAN_DB_USER}
FOREMAN_DB_PASSWORD=${EXISTING_FOREMAN_DB_PASSWORD}
UBUNTU_AUTOINSTALL_USERNAME=${EXISTING_UBUNTU_USERNAME}
UBUNTU_AUTOINSTALL_PASSWORD=${EXISTING_UBUNTU_PASSWORD}
UBUNTU_AUTOINSTALL_REALNAME="${EXISTING_UBUNTU_REALNAME}"
UBUNTU_AUTOINSTALL_HOSTNAME=${EXISTING_UBUNTU_HOSTNAME}
UBUNTU_AUTOINSTALL_LOCALE=${EXISTING_UBUNTU_LOCALE}
UBUNTU_AUTOINSTALL_KEYBOARD=${EXISTING_UBUNTU_KEYBOARD}
UBUNTU_AUTOINSTALL_TIMEZONE=${EXISTING_UBUNTU_TIMEZONE}
WINDOWS_IMAGE_NAME="${EXISTING_WINDOWS_IMAGE_NAME}"
WINDOWS_LOCAL_ADMIN_USER=${EXISTING_WINDOWS_ADMIN_USER}
WINDOWS_LOCAL_ADMIN_PASSWORD=${EXISTING_WINDOWS_ADMIN_PASSWORD}
WINDOWS_COMPUTER_NAME="${EXISTING_WINDOWS_COMPUTER_NAME}"
WINDOWS_LOCALE=${EXISTING_WINDOWS_LOCALE}
WINDOWS_TARGET_DISK=${EXISTING_WINDOWS_TARGET_DISK}
EOF

chmod 0600 "${ENV_FILE}"
log "Generated ${ENV_FILE} for host ${HOST_FQDN} on ${DEFAULT_IFACE}"
