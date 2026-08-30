#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

PYTHON_BIN="${PYTHON_BIN:-python3}"

fail() {
  echo "[ERROR] $1"
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "${label} (missing: ${needle})"
  fi
}

validate_singbox_json() {
  local payload="$1"
  printf '%s\n' "${payload}" | "${PYTHON_BIN}" -c '
import json
import sys

data = json.load(sys.stdin)
assert data["dns"]["servers"][0]["detour"] == "proxy"
assert "detour" not in data["dns"]["servers"][1]
assert data["route"]["default_domain_resolver"] == "cf"
assert all(item["download_detour"] == "proxy" for item in data["route"]["rule_set"])
assert data["route"]["final"] == "proxy"
' || fail "Sing-box full template is not valid modern JSON"
}

export HY2_LIB_ONLY=1
# shellcheck source=../../hy2.sh
source "${ROOT_DIR}/hy2.sh"

cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
public_key_sha="47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="

echo "[INFO] Parsing CA and self-signed Sing-box templates..."
ca_json="$(render_singbox_full_template "8.8.8.8" "443" "20" "100" "abc123" "example.com" "false")"
self_json="$(render_singbox_full_template "8.8.8.8" "443" "20" "100" "abc123" "bing.com" "true" "${public_key_sha}")"
validate_singbox_json "${ca_json}"
validate_singbox_json "${self_json}"
assert_contains "${self_json}" '"certificate_public_key_sha256": ["'"${public_key_sha}"'"]' "self-signed public key pin missing"
if [[ "${ca_json}" == *"certificate_public_key_sha256"* ]]; then
  fail "CA template should not contain a self-signed public key pin"
fi

echo "[INFO] Checking client export safety gate..."
wait_return() { :; }
insecure="true"
if ensure_client_export_material "" "${public_key_sha}" >/dev/null 2>&1; then
  fail "client export should reject a missing certificate fingerprint"
fi
if ensure_client_export_material "${cert_sha}" "" >/dev/null 2>&1; then
  fail "client export should reject a missing public key pin"
fi
ensure_client_export_material "${cert_sha}" "${public_key_sha}" || fail "complete self-signed export material should pass"
insecure="false"
ensure_client_export_material "" "" || fail "CA export should not require self-signed pins"

echo "[INFO] Rendering combined client exports..."
ip="8.8.8.8"
port="443"
password="abc123"
sni="bing.com"
up_mbps="20"
down_mbps="100"
insecure="true"
clear() { :; }
summary="$(print_client_summary "${cert_sha}" "${public_key_sha}")"
assert_contains "${summary}" "服务器 IP :" "client summary server label missing"
assert_contains "${summary}" "${cert_sha}" "client summary certificate pin missing"
assert_contains "${summary}" "${public_key_sha}" "client summary public key pin missing"

exports="$(print_client_exports "${cert_sha}" "${public_key_sha}")"
assert_contains "${exports}" "pinSHA256=${cert_sha}" "Hysteria2 certificate pin missing"
assert_contains "${exports}" "pcs=${cert_sha}" "v2rayN/Xray certificate pin missing"
assert_contains "${exports}" '"certificate_public_key_sha256": ["'"${public_key_sha}"'"]' "Sing-box public key pin missing"
assert_contains "${exports}" "pinSHA256: ${cert_sha}" "native Hysteria2 YAML pin missing"
if [[ "${exports}" == *"allowInsecure"* ]]; then
  fail "client exports must not contain removed allowInsecure"
fi

echo "[OK] Client render flow passed."
