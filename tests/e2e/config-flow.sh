#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

fail() {
  echo "[ERROR] $1"
  exit 1
}

assert_contains_file() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "${needle}" "${file}"; then
    fail "${label} (missing: ${needle})"
  fi
}

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

export HY2_LIB_ONLY=1
# shellcheck source=../../hy2.sh
source "${ROOT_DIR}/hy2.sh"

HY2_CONF_DIR="${tmp_dir}/etc-hysteria"
HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
mkdir -p "${HY2_CONF_DIR}" "${HY2_BACKUP_DIR}"

# Mock runtime-only dependencies for deterministic e2e replay.
ensure_hy2_core_installed() { return 0; }
fetch_server_ip() { echo "9.9.9.9"; }
clear() { :; }
sleep() { :; }
systemctl() {
  case "${1:-}" in
    show) echo "root"; return 0 ;;
    restart) return 0 ;;
    is-active) return 0 ;;
    *) return 0 ;;
  esac
}

echo "[INFO] Replaying config_hy2 interactive CA flow..."
if ! config_hy2 <<< $'23456\ntest-password\n\n30\n60\n1\nexample.com\n\n'; then
  fail "config_hy2 should succeed in replay flow"
fi

[[ -f "${HY2_CONF_FILE}" ]] || fail "config file not created"
[[ -f "${HY2_META_FILE}" ]] || fail "meta file not created"

assert_contains_file "${HY2_CONF_FILE}" "listen: :23456" "listen port mismatch"
assert_contains_file "${HY2_CONF_FILE}" "domains:" "acme block missing"
assert_contains_file "${HY2_CONF_FILE}" "example.com" "domain not written"
assert_contains_file "${HY2_META_FILE}" "ip=9.9.9.9" "meta ip mismatch"
assert_contains_file "${HY2_META_FILE}" "port=23456" "meta port mismatch"
assert_contains_file "${HY2_META_FILE}" "sni=example.com" "meta sni mismatch"
assert_contains_file "${HY2_META_FILE}" "insecure=false" "meta insecure mismatch"
assert_contains_file "${HY2_META_FILE}" "up_mbps=30" "meta up_mbps mismatch"
assert_contains_file "${HY2_META_FILE}" "down_mbps=60" "meta down_mbps mismatch"

echo "[OK] E2E config flow replay passed."
