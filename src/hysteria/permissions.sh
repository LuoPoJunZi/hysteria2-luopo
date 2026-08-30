# shellcheck shell=bash
# 职责: 配置、证书与 systemd 用户权限

set_config_dir_permissions() {
    local run_user run_group
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        run_group="$(get_service_run_group "${run_user}")"
        chown root:"${run_group}" "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
        chmod 750 "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
    else
        chmod 755 "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
    fi
}

set_server_config_permissions() {
    local run_user run_group
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        run_group="$(get_service_run_group "${run_user}")"
        chown root:"${run_group}" "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
        chmod 640 "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
    else
        chmod 644 "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
    fi
}

get_service_run_user() {
    local run_user
    run_user="$(systemctl show -p User --value "${HY2_SERVICE}" 2>/dev/null || true)"
    [[ -z "${run_user}" ]] && run_user="root"
    echo "${run_user}"
}

get_service_run_group() {
    local run_user="$1"
    local run_group
    run_group="$(systemctl show -p Group --value "${HY2_SERVICE}" 2>/dev/null || true)"
    if [[ -z "${run_group}" ]]; then
        run_group="$(id -gn "${run_user}" 2>/dev/null || true)"
    fi
    [[ -z "${run_group}" ]] && run_group="root"
    echo "${run_group}"
}

set_tls_file_permissions() {
    local run_user run_group
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        run_group="$(get_service_run_group "${run_user}")"
        chown "${run_user}:${run_group}" "${HY2_CONF_DIR}/server.key" "${HY2_CONF_DIR}/server.crt" >/dev/null 2>&1 || true
    fi
    chmod 600 "${HY2_CONF_DIR}/server.key" >/dev/null 2>&1 || true
    chmod 644 "${HY2_CONF_DIR}/server.crt" >/dev/null 2>&1 || true
}
