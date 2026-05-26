#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

fail() {
    echo "[ERROR] $1"
    exit 1
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [[ "${actual}" != "${expected}" ]]; then
        fail "${label} (expected: ${expected}, actual: ${actual})"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        fail "${label} (missing: ${needle})"
    fi
}

export HY2_LIB_ONLY=1
export HY2_LIB_DIR="${ROOT_DIR}/lib/hy2"
# shellcheck source=../hy2.sh
source "${ROOT_DIR}/hy2.sh"

echo "[INFO] Running module loader checks..."
[[ "${HY2_MODULE_COMMON_LOADED:-0}" != "1" ]] || fail "common module should not be loaded by launcher"
load_module config || fail "config module should load"
[[ "${HY2_MODULE_COMMON_LOADED:-0}" == "1" ]] || fail "config module should load common dependency"
load_module config || fail "config module should be repeat-load safe"
load_module client || fail "client module should load"
saved_lib_dir="${HY2_LIB_DIR}"
HY2_LIB_DIR="${tmp_dir:-/tmp}/missing-hy2-lib"
HY2_DISABLE_MODULE_BOOTSTRAP=1
if load_module diagnostics 2>/dev/null; then
    fail "missing diagnostics module should fail to load"
fi
unset HY2_DISABLE_MODULE_BOOTSTRAP
HY2_LIB_DIR="${saved_lib_dir}"

__mock_systemctl_mode="always_success"
__mock_systemctl_calls=0
__mock_journalctl_log=""
systemctl() {
    if [[ "${1:-}" == "restart" ]]; then
        __mock_systemctl_calls=$((__mock_systemctl_calls + 1))
        case "${__mock_systemctl_mode}" in
            always_success) return 0 ;;
            fail_then_success)
                if [[ "${__mock_systemctl_calls}" -eq 1 ]]; then
                    return 1
                fi
                return 0
                ;;
            always_fail) return 1 ;;
        esac
    fi
    return 0
}
journalctl() {
    printf "%s\n" "${__mock_journalctl_log}"
    return 0
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "${tmp_dir}"
}
trap cleanup EXIT

HY2_CONF_DIR="${tmp_dir}/etc-hysteria"
HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
HY2_DIAG_DIR="${tmp_dir}"
HY2_DIAG_LATEST="${HY2_DIAG_DIR}/hy2-diagnose-latest.log"
mkdir -p "${HY2_CONF_DIR}" "${HY2_BACKUP_DIR}"

echo "[INFO] Running panel bundle install checks..."
load_module core || fail "core module should load"
bundle_dir="${tmp_dir}/bundle"
mkdir -p "${bundle_dir}/lib/hy2"
cp -f "${ROOT_DIR}/hy2.sh" "${bundle_dir}/hy2.sh"
for module in $(panel_module_list); do
    cp -f "${ROOT_DIR}/lib/hy2/${module}.sh" "${bundle_dir}/lib/hy2/${module}.sh"
done
verify_downloaded_panel_bundle "${bundle_dir}" || fail "current bundle should validate"
PANEL_TARGET_BIN="${tmp_dir}/bin/hy2"
PANEL_TARGET_LIB_DIR="${tmp_dir}/installed-lib"
install_panel_bundle_from_dir "${bundle_dir}" || fail "panel bundle should install to temp paths"
[[ -x "${PANEL_TARGET_BIN}" ]] || fail "installed launcher should be executable"
[[ -f "${PANEL_TARGET_LIB_DIR}/common.sh" ]] || fail "installed common module missing"
bad_bundle="${tmp_dir}/bad-bundle"
mkdir -p "${bad_bundle}/lib/hy2"
cp -f "${ROOT_DIR}/hy2.sh" "${bad_bundle}/hy2.sh"
if verify_downloaded_panel_bundle "${bad_bundle}"; then
    fail "incomplete bundle should not validate"
fi
HY2_LIB_DIR="${saved_lib_dir}"
unset PANEL_TARGET_LIB_DIR

echo "[INFO] Running validator checks..."
is_valid_port "1" || fail "port 1 should be valid"
is_valid_port "65535" || fail "port 65535 should be valid"
! is_valid_port "0" || fail "port 0 should be invalid"
! is_valid_port "70000" || fail "port 70000 should be invalid"
is_valid_domain "example.com" || fail "example.com should be valid domain"
! is_valid_domain "-bad.com" || fail "-bad.com should be invalid domain"
is_valid_url "https://bing.com" || fail "https URL should be valid"
! is_valid_url "ftp://example.com" || fail "ftp URL should be invalid"
is_valid_email "dev@example.com" || fail "email should be valid"
! is_valid_email "dev@localhost" || fail "email without TLD should be invalid"

echo "[INFO] Running config generation checks..."
write_self_signed_config "443" "pa'ss" "https://example.com"
write_meta_info "1.2.3.4" "443" "pa'ss" "bing.com" "true" "30" "120"

conf_text="$(cat "${HY2_CONF_FILE}")"
assert_contains "${conf_text}" "listen: :443" "self-signed config listen missing"
assert_contains "${conf_text}" "password: 'pa''ss'" "password yaml escaping mismatch"

read_meta_info || fail "read_meta_info should succeed for valid meta"
assert_eq "${ip}" "1.2.3.4" "meta ip mismatch"
assert_eq "${port}" "443" "meta port mismatch"
assert_eq "${password}" "pa'ss" "meta password mismatch"
assert_eq "${sni}" "bing.com" "meta sni mismatch"
assert_eq "${insecure}" "true" "meta insecure mismatch"
assert_eq "${up_mbps}" "30" "meta up_mbps mismatch"
assert_eq "${down_mbps}" "120" "meta down_mbps mismatch"

echo "[INFO] Running SNI picker checks..."
pick_self_signed_sni <<< ""
assert_eq "${PICKED_SNI}" "bing.com" "default SNI selection mismatch"

pick_self_signed_sni <<< "4"
assert_eq "${PICKED_SNI}" "www.microsoft.com" "preset SNI selection mismatch"

pick_self_signed_sni <<< $'0\ncustom.example.com\n'
assert_eq "${PICKED_SNI}" "custom.example.com" "manual SNI input mismatch"

pick_self_signed_sni <<< "9"
assert_eq "${PICKED_SNI}" "bing.com" "invalid SNI fallback mismatch"

echo "[INFO] Running share snippet checks..."
rendered_json="$(render_singbox_outbound_snippet "8.8.8.8" "45612" "20" "100" "abc123" "bing.com" "true")"
assert_contains "${rendered_json}" "\"type\": \"hysteria2\"" "sing-box type missing"
assert_contains "${rendered_json}" "\"server_port\": 45612" "sing-box port missing"
assert_contains "${rendered_json}" "\"server_name\": \"bing.com\"" "sing-box sni missing"

rendered_yaml="$(render_v2rayn_yaml_snippet "8.8.8.8" "45612" "abc123" "20" "100" "bing.com" "true")"
assert_contains "${rendered_yaml}" "server: 8.8.8.8:45612" "v2rayN server line missing"
assert_contains "${rendered_yaml}" "auth: abc123" "v2rayN auth line missing"

assert_eq "$(format_host_for_url "2001:db8::1")" "[2001:db8::1]" "IPv6 host formatting mismatch"
assert_eq "$(format_host_for_url "8.8.8.8")" "8.8.8.8" "IPv4 host formatting mismatch"

echo "[INFO] Running rollback checks..."
printf "stable-config" > "${HY2_CONF_FILE}"
printf "stable-meta" > "${HY2_META_FILE}"
backup_runtime_files || fail "backup_runtime_files should succeed"
printf "broken-config" > "${HY2_CONF_FILE}"

__mock_systemctl_mode="fail_then_success"
__mock_systemctl_calls=0
if restart_service_with_rollback; then
    fail "restart_service_with_rollback should fail when first restart fails"
fi
assert_eq "${__mock_systemctl_calls}" "2" "rollback restart call count mismatch"
assert_eq "$(cat "${HY2_CONF_FILE}")" "stable-config" "config should be restored after rollback"

__mock_systemctl_mode="always_success"
__mock_systemctl_calls=0
restart_service_with_rollback || fail "restart_service_with_rollback should pass when restart succeeds"
assert_eq "${__mock_systemctl_calls}" "1" "success restart call count mismatch"

echo "[INFO] Running failure hint checks..."
__mock_journalctl_log="FATAL failed to read server config {\"error\": \"open /etc/hysteria/config.yaml: permission denied\"}"
hint_output="$(show_service_failure_hint 2>&1 || true)"
assert_contains "${hint_output}" "服务用户无权读取 config.yaml" "permission hint missing"

__mock_journalctl_log="listen tcp :443: bind: address already in use"
hint_output="$(show_service_failure_hint 2>&1 || true)"
assert_contains "${hint_output}" "监听端口被占用" "port conflict hint missing"

__mock_journalctl_log="acme: challenge timeout and dns lookup failed"
hint_output="$(show_service_failure_hint 2>&1 || true)"
assert_contains "${hint_output}" "CA 证书申请失败" "acme hint missing"

echo "[OK] Smoke E2E checks passed."
