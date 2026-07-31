#!/usr/bin/env bats

setup() {
  export HY2_LIB_ONLY=1
  # shellcheck source=../../hy2.sh
  source "${BATS_TEST_DIRNAME}/../../hy2.sh"

  TMP_DIR="$(mktemp -d)"
  export HY2_CONF_DIR="${TMP_DIR}/etc-hysteria"
  export HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
  export HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
  export HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
  export HY2_DIAG_DIR="${TMP_DIR}"
  export HY2_DIAG_LATEST="${TMP_DIR}/hy2-diagnose-latest.log"
  mkdir -p "${HY2_CONF_DIR}" "${HY2_BACKUP_DIR}"
}

teardown() {
  rm -rf "${TMP_DIR}"
}

@test "validators should accept/reject expected values" {
  run is_valid_port "443"
  [ "${status}" -eq 0 ]

  run is_valid_port "70000"
  [ "${status}" -ne 0 ]

  run is_valid_port "00008"
  [ "${status}" -eq 0 ]

  run is_positive_integer "00008"
  [ "${status}" -eq 0 ]

  run is_positive_integer "0"
  [ "${status}" -ne 0 ]

  run is_valid_domain "example.com"
  [ "${status}" -eq 0 ]

  run is_valid_domain "-bad.com"
  [ "${status}" -ne 0 ]

  run is_valid_url "https://example.com"
  [ "${status}" -eq 0 ]

  run is_valid_url "ftp://example.com"
  [ "${status}" -ne 0 ]
}

@test "config and meta writers should preserve values correctly" {
  write_self_signed_config "443" "pa'ss" "https://example.com"
  [ "$?" -eq 0 ]
  grep -Fq "password: 'pa''ss'" "${HY2_CONF_FILE}"

  write_meta_info "1.2.3.4" "443" "pa'ss" "bing.com" "true" "20" "100"
  [ "$?" -eq 0 ]

  read_meta_info
  [ "$?" -eq 0 ]
  [ "${ip}" = "1.2.3.4" ]
  [ "${port}" = "443" ]
  [ "${password}" = "pa'ss" ]
  [ "${sni}" = "bing.com" ]
  [ "${insecure}" = "true" ]
}

@test "restart_service_with_rollback should restore backup after restart failure" {
  systemctl() {
    if [ "${1:-}" = "restart" ]; then
      restart_calls=$((restart_calls + 1))
      if [ "${restart_calls}" -eq 1 ]; then
        return 1
      fi
      return 0
    fi
    return 0
  }

  printf "stable-config" > "${HY2_CONF_FILE}"
  printf "stable-meta" > "${HY2_META_FILE}"
  printf "stable-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "stable-key" > "${HY2_CONF_DIR}/server.key"
  backup_runtime_files
  printf "broken-config" > "${HY2_CONF_FILE}"
  printf "broken-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "broken-key" > "${HY2_CONF_DIR}/server.key"

  run restart_service_with_rollback
  [ "${status}" -ne 0 ]
  [ "$(cat "${HY2_CONF_FILE}")" = "stable-config" ]
  [ "$(cat "${HY2_CONF_DIR}/server.crt")" = "stable-cert" ]
  [ "$(cat "${HY2_CONF_DIR}/server.key")" = "stable-key" ]
}

@test "runtime snapshot should replace stale backups and preserve absent files" {
  printf "stable-config" > "${HY2_CONF_FILE}"
  printf "stable-meta" > "${HY2_META_FILE}"
  printf "stale-cert" > "${HY2_BACKUP_DIR}/server.crt.bak"

  backup_runtime_files
  [ "$?" -eq 0 ]
  [ ! -e "${HY2_BACKUP_DIR}/server.crt.bak" ]
  [ -f "${HY2_BACKUP_DIR}/server.crt.bak.absent" ]

  printf "generated-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "generated-key" > "${HY2_CONF_DIR}/server.key"
  restore_runtime_files
  [ "$?" -eq 0 ]
  [ ! -e "${HY2_CONF_DIR}/server.crt" ]
  [ ! -e "${HY2_CONF_DIR}/server.key" ]
}

@test "manual CA backup restore should remove stale self-signed files" {
  systemctl() {
    case "${1:-}" in
      show) echo "root" ;;
      restart) return 0 ;;
    esac
    return 0
  }

  cat > "${HY2_CONF_FILE}" <<'EOF'
listen: :443
acme:
  domains:
    - example.com
EOF
  printf "stable-meta" > "${HY2_META_FILE}"
  create_manual_backup
  [ "$?" -eq 0 ]

  printf "changed-config" > "${HY2_CONF_FILE}"
  printf "changed-meta" > "${HY2_META_FILE}"
  printf "stale-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "stale-key" > "${HY2_CONF_DIR}/server.key"

  restore_latest_manual_backup
  [ "$?" -eq 0 ]
  grep -Fq "acme:" "${HY2_CONF_FILE}"
  [ "$(cat "${HY2_META_FILE}")" = "stable-meta" ]
  [ ! -e "${HY2_CONF_DIR}/server.crt" ]
  [ ! -e "${HY2_CONF_DIR}/server.key" ]
}

@test "show_service_failure_hint should classify permission denied logs" {
  journalctl() {
    cat <<'EOF'
FATAL failed to read server config {"error":"open /etc/hysteria/config.yaml: permission denied"}
EOF
  }

  run show_service_failure_hint
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"服务用户无权读取 config.yaml"* ]]
}

@test "sing-box full template should use modern rule-set format" {
  rendered="$(render_singbox_full_template "8.8.8.8" "45612" "20" "100" "abc123" "bing.com" "true")"
  [[ "${rendered}" == *'"rule_set": "geosite-cn"'* ]]
  [[ "${rendered}" == *'"action": "hijack-dns"'* ]]
  [[ "${rendered}" == *'"address": ['* ]]
  [[ "${rendered}" == *'"type": "https"'* ]]
  [[ "${rendered}" == *'"detour": "proxy"'* ]]
  [[ "${rendered}" == *'"default_domain_resolver": "cf"'* ]]
  [[ "${rendered}" == *'"download_detour": "proxy"'* ]]
  [[ "${rendered}" != *'"geosite":'* ]]
  [[ "${rendered}" != *'"geoip":'* ]]
  [[ "${rendered}" != *'"inet4_address"'* ]]
  [[ "${rendered}" != *'"type": "dns"'* ]]
  [[ "${rendered}" != *'"detour": "direct"'* ]]
}

@test "v2rayN insecure notice should warn self-signed users" {
  run print_v2rayn_insecure_notice
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"v2rayN / Xray 自签证书提醒"* ]]
  [[ "${output}" == *"insecure=1"* ]]
  [[ "${output}" == *"pinSHA256"* ]]
  [[ "${output}" == *"pcs"* ]]
  [[ "${output}" == *"Xray-core >= 26.2.6"* ]]
  [[ "${output}" == *"pinnedPeerCertSha256"* ]]
  [[ "${output}" == *"已移除 allowInsecure"* ]]
  [[ "${output}" == *"重新导入节点"* ]]
}

@test "hysteria2 share URL should use URI boolean values" {
  cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  run render_hysteria2_share_url "8.8.8.8" "45612" "pa ss" "bing.com" "true" "${cert_sha}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "hysteria2://pa%20ss@8.8.8.8:45612/?sni=bing.com&insecure=1&pinSHA256=${cert_sha}&pcs=${cert_sha}#Hysteria2-LuoPo" ]
  [[ "${output}" != *"allowInsecure"* ]]

  run render_hysteria2_share_url "2001:db8::1" "443" "abc123" "example.com" "false"
  [ "${status}" -eq 0 ]
  [ "${output}" = "hysteria2://abc123@[2001:db8::1]:443/?sni=example.com#Hysteria2-LuoPo" ]
}

@test "hysteria2 share URL should reject invalid insecure values" {
  run render_hysteria2_share_url "8.8.8.8" "443" "abc123" "bing.com" "yes"
  [ "${status}" -ne 0 ]
}

@test "URL encoder should percent-encode UTF-8 bytes" {
  run url_encode "密码"
  [ "${status}" -eq 0 ]
  [ "${output}" = "%E5%AF%86%E7%A0%81" ]
}

@test "certificate fingerprint normalizer should return lowercase hex" {
  raw="sha256 Fingerprint=AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
  run normalize_certificate_sha256 "${raw}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899" ]

  run normalize_certificate_sha256 "not-a-fingerprint"
  [ "${status}" -ne 0 ]
}

@test "native Hysteria2 YAML should include certificate pin when available" {
  cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  run render_v2rayn_yaml_snippet "8.8.8.8" "45612" "abc123" "20" "100" "bing.com" "true" "${cert_sha}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"pinSHA256: ${cert_sha}"* ]]
}

@test "native Hysteria2 YAML should quote special values and format IPv6" {
  run render_v2rayn_yaml_snippet "2001:db8::1" "443" "pa'ss #1" "20" "100" "example.com" "false"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"server: '[2001:db8::1]:443'"* ]]
  [[ "${output}" == *"auth: 'pa''ss #1'"* ]]
  [[ "${output}" == *"sni: 'example.com'"* ]]
}

@test "verify_hy2_installer should require Bash syntax and shebang" {
  installer_file="${TMP_DIR}/hysteria-installer.sh"
  cat > "${installer_file}" <<'EOF'
#!/usr/bin/env bash
echo "Hysteria installer"
EOF

  run verify_hy2_installer "${installer_file}"
  [ "${status}" -eq 0 ]

  printf '\nif then\n' >> "${installer_file}"
  run verify_hy2_installer "${installer_file}"
  [ "${status}" -ne 0 ]
}

@test "verify_downloaded_panel should require a valid panel version" {
  panel_file="${TMP_DIR}/hy2-valid.sh"
  cat > "${panel_file}" <<'EOF'
#!/bin/bash
sh_ver="v9.8.7"
echo "Hysteria2-LuoPo 管理面板"
main_menu() { :; }
EOF

  run verify_downloaded_panel "${panel_file}"
  [ "${status}" -eq 0 ]
  run extract_panel_version "${panel_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "v9.8.7" ]

  printf '\nif then\n' >> "${panel_file}"
  run verify_downloaded_panel "${panel_file}"
  [ "${status}" -ne 0 ]
  sed -i '$d' "${panel_file}"
  sed -i '$d' "${panel_file}"

  sed -i '/^sh_ver=/d' "${panel_file}"
  run verify_downloaded_panel "${panel_file}"
  [ "${status}" -ne 0 ]
}
