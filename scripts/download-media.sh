#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

log() {
  printf '[%s] [media] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

fail() {
  printf '[%s] [media] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

ISO_CACHE="${ROOT_DIR}/.iso-cache"
MEDIA_ROOT="${MEDIA_ROOT:-${ROOT_DIR}/media}"
UBUNTU_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.4-desktop-amd64.iso"
UBUNTU_ISO="${ISO_CACHE}/ubuntu-24.04.4-desktop-amd64.iso"
WINDOWS_ISO="${ISO_CACHE}/windows11-x64.iso"
PLAYWRIGHT_IMAGE="${PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright/python:v1.52.0-noble}"
PLAYWRIGHT_PYTHON_VERSION="${PLAYWRIGHT_PYTHON_VERSION:-1.52.0}"

mkdir -p "${ISO_CACHE}" "${MEDIA_ROOT}"

download_if_missing() {
  local url="$1"
  local out="$2"
  local curl_opts=(-fL --retry 5 --retry-delay 5 --progress-bar)

  if [[ -s "${out}" ]]; then
    log "Reusing ${out}"
    return
  fi

  log "Downloading ${url}"
  curl "${curl_opts[@]}" -o "${out}" "${url}"
  log "Saved ${out}"
}

discover_windows_url() {
  if [[ -n "${WINDOWS_11_ISO_URL:-}" ]]; then
    log "Using explicit direct Windows 11 ISO URL from WINDOWS_11_ISO_URL"
    printf '%s\n' "${WINDOWS_11_ISO_URL}"
    return 0
  fi

  log "Trying lightweight scrape of the official Microsoft Windows 11 download page"
  if python3 "${ROOT_DIR}/scripts/fetch_windows_iso.py" \
    --download-page "https://www.microsoft.com/en-us/software-download/windows11" \
    --language "${WINDOWS_11_LANGUAGE:-English International}"; then
    return 0
  fi

  log "Falling back to a browser-driven extraction of the temporary Microsoft ISO link"
  docker run --rm \
    -v "${ROOT_DIR}:/workspace" \
    -w /workspace \
    "${PLAYWRIGHT_IMAGE}" \
    bash -lc '
      export PIP_DISABLE_PIP_VERSION_CHECK=1 &&
      python3 -m pip install --quiet --disable-pip-version-check --root-user-action=ignore "playwright=='"${PLAYWRIGHT_PYTHON_VERSION}"'" >/dev/null 2>&1 &&
      python3 /workspace/scripts/fetch_windows_iso_playwright.py \
        --page "https://www.microsoft.com/en-us/software-download/windows11" \
        --edition "Download Windows 11 (multi-edition ISO for x64 devices)" \
        --language "'"${WINDOWS_11_LANGUAGE:-English International}"'"
    '
}

log "Preparing Ubuntu 24.04.4 media"
download_if_missing "${UBUNTU_URL}" "${UBUNTU_ISO}"

if [[ ! -s "${WINDOWS_ISO}" ]]; then
  log "Preparing Windows 11 media"
  WINDOWS_DIRECT_URL="$(discover_windows_url || true)"
  if [[ -z "${WINDOWS_DIRECT_URL}" ]]; then
    fail "Unable to derive a direct Windows 11 ISO URL from Microsoft. The Microsoft page URL is not itself an ISO file. Set WINDOWS_11_ISO_URL in .env to a real temporary ISO link and rerun."
  fi
  log "Resolved temporary direct Windows 11 ISO URL"
  curl -fL --retry 5 --retry-delay 5 --progress-bar -o "${WINDOWS_ISO}" "${WINDOWS_DIRECT_URL}"
  log "Saved ${WINDOWS_ISO}"
else
  log "Reusing ${WINDOWS_ISO}"
fi
