# shellcheck shell=bash
# 职责: Hysteria2 交互配置流程编排

config_hy2() {
    if ! ensure_hy2_core_installed; then
        sleep 2
        return 1
    fi

    clear
    print_line
    echo -e "               ${_green}--- Hysteria2 节点配置 ---${_plain}"
    print_line

    reset_hy2_config_draft
    if ! collect_hy2_connection_settings; then
        return 1
    fi
    if ! collect_hy2_certificate_settings; then
        return 1
    fi

    if ! prepare_hy2_config_change; then
        return 1
    fi

    if [[ "${HY2_DRAFT_CERT_TYPE}" == "1" ]]; then
        if ! apply_hy2_ca_config \
            "${HY2_DRAFT_PORT}" \
            "${HY2_DRAFT_DOMAIN}" \
            "${HY2_DRAFT_EMAIL}" \
            "${HY2_DRAFT_PASSWORD}" \
            "${HY2_DRAFT_MASQUERADE_URL}"; then
            return 1
        fi
    else
        if ! apply_hy2_self_signed_config \
            "${HY2_DRAFT_PORT}" \
            "${HY2_DRAFT_PASSWORD}" \
            "${HY2_DRAFT_MASQUERADE_URL}" \
            "${HY2_DRAFT_SNI}"; then
            return 1
        fi
    fi

    activate_hy2_config \
        "${HY2_DRAFT_PORT}" \
        "${HY2_DRAFT_PASSWORD}" \
        "${HY2_DRAFT_SNI}" \
        "${HY2_DRAFT_INSECURE}" \
        "${HY2_DRAFT_UP_MBPS}" \
        "${HY2_DRAFT_DOWN_MBPS}"
}
