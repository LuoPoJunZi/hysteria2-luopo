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
