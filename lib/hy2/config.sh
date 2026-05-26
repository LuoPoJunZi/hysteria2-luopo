# shellcheck shell=bash
if [[ "${HY2_MODULE_CONFIG_LOADED:-0}" != "1" ]]; then
if [[ "${HY2_MODULE_COMMON_LOADED:-0}" != "1" ]]; then
    if declare -F load_module >/dev/null 2>&1; then
        load_module common
    else
        __hy2_module_dir="${HY2_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
        # shellcheck source=/dev/null
        . "${__hy2_module_dir}/common.sh"
        unset __hy2_module_dir
    fi
fi

write_ca_config() {
    local port="$1"
    local domain="$2"
    local email="$3"
    local password="$4"
    local masquerade_url="$5"

    cat << EOF | write_file_atomic "${HY2_CONF_FILE}"
listen: :${port}
acme:
  domains:
    - $(yaml_single_quote "${domain}")
  email: $(yaml_single_quote "${email}")
auth:
  type: password
  password: $(yaml_single_quote "${password}")
masquerade:
  type: proxy
  proxy:
    url: $(yaml_single_quote "${masquerade_url}")
    rewriteHost: true
EOF
}

write_self_signed_config() {
    local port="$1"
    local password="$2"
    local masquerade_url="$3"

    cat << EOF | write_file_atomic "${HY2_CONF_FILE}"
listen: :${port}
tls:
  cert: ${HY2_CONF_DIR}/server.crt
  key: ${HY2_CONF_DIR}/server.key
auth:
  type: password
  password: $(yaml_single_quote "${password}")
masquerade:
  type: proxy
  proxy:
    url: $(yaml_single_quote "${masquerade_url}")
    rewriteHost: true
EOF
}

pick_self_signed_sni() {
    local pick custom_sni
    PICKED_SNI=""
    echo -e " [*] 请选择自签 SNI 预设域名："
    echo -e "     (1) ${SELF_SNI_PRESETS[0]} (默认)"
    echo -e "     (2) ${SELF_SNI_PRESETS[1]}"
    echo -e "     (3) ${SELF_SNI_PRESETS[2]}"
    echo -e "     (4) ${SELF_SNI_PRESETS[3]}"
    echo -e "     (5) ${SELF_SNI_PRESETS[4]}"
    echo -e "     (0) 手动输入域名"
    read -p " [*] 请选择 [0-5] (默认 1): " pick
    [[ -z "${pick}" ]] && pick=1

    case "${pick}" in
        1) PICKED_SNI="${SELF_SNI_PRESETS[0]}" ;;
        2) PICKED_SNI="${SELF_SNI_PRESETS[1]}" ;;
        3) PICKED_SNI="${SELF_SNI_PRESETS[2]}" ;;
        4) PICKED_SNI="${SELF_SNI_PRESETS[3]}" ;;
        5) PICKED_SNI="${SELF_SNI_PRESETS[4]}" ;;
        0)
            read -p " [*] 请输入用于伪装的 SNI 域名 (默认 ${DEFAULT_SELF_SNI}): " custom_sni
            [[ -z "${custom_sni}" ]] && custom_sni="${DEFAULT_SELF_SNI}"
            PICKED_SNI="${custom_sni}"
            ;;
        *)
            err "输入无效，已使用默认 SNI: ${DEFAULT_SELF_SNI}"
            PICKED_SNI="${DEFAULT_SELF_SNI}"
            ;;
    esac
}

config_hy2() {
    if ! ensure_hy2_core_installed; then
        sleep 2
        return 1
    fi

    clear
    print_line
    echo -e "               ${_green}--- Hysteria2 节点配置 ---${_plain}"
    print_line
    
    read -p " => 请设置监听端口 (默认 ${DEFAULT_PORT}): " port
    [[ -z "${port}" ]] && port="${DEFAULT_PORT}"
    if ! is_valid_port "${port}"; then
        err "端口无效，请输入 1-65535 的整数。"
        sleep 2
        return 1
    fi
    
    local default_pwd=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
    read -p " => 请设置认证密码 (默认随机: ${default_pwd}): " password
    [[ -z "${password}" ]] && password="${default_pwd}"

    read -p " => 请设置伪装网址 (默认 ${DEFAULT_MASQUERADE_URL}): " masquerade_url
    [[ -z "${masquerade_url}" ]] && masquerade_url="${DEFAULT_MASQUERADE_URL}"
    if ! is_valid_url "${masquerade_url}"; then
        err "伪装网址格式无效，必须以 http:// 或 https:// 开头。"
        sleep 2
        return 1
    fi

    read -p " => 请设置上行带宽 Mbps (默认 ${DEFAULT_UP_MBPS}): " up_mbps
    [[ -z "${up_mbps}" ]] && up_mbps="${DEFAULT_UP_MBPS}"
    if ! [[ "${up_mbps}" =~ ^[0-9]+$ ]] || (( up_mbps < 1 )); then
        err "上行带宽无效，请输入大于 0 的整数。"
        sleep 2
        return 1
    fi

    read -p " => 请设置下行带宽 Mbps (默认 ${DEFAULT_DOWN_MBPS}): " down_mbps
    [[ -z "${down_mbps}" ]] && down_mbps="${DEFAULT_DOWN_MBPS}"
    if ! [[ "${down_mbps}" =~ ^[0-9]+$ ]] || (( down_mbps < 1 )); then
        err "下行带宽无效，请输入大于 0 的整数。"
        sleep 2
        return 1
    fi

    echo -e "\n[*] 请选择证书模式："
    echo -e "  (1) CA 域名证书 (推荐，需要提前将域名解析到本 VPS)"
    echo -e "  (2) 自签证书 (无需域名，直接使用 IP 连通)"
    read -p " => 请选择 [1-2]: " cert_type
    if [[ "${cert_type}" != "1" && "${cert_type}" != "2" ]]; then
        err "证书模式输入无效，请输入 1 或 2。"
        sleep 2
        return 1
    fi

    if ! mkdir -p "${HY2_CONF_DIR}"; then
        err "创建配置目录失败: ${HY2_CONF_DIR}"
        sleep 2
        return 1
    fi
    set_config_dir_permissions
    if ! backup_runtime_files; then
        err "备份当前配置失败，已中止以避免覆盖现有配置。"
        sleep 2
        return 1
    fi

    if [[ "${cert_type}" == "1" ]]; then
        read -p " [*] 请输入已解析到本机的域名: " domain
        if ! is_valid_domain "${domain}"; then
            err "域名格式无效，请输入有效域名（例如 example.com）。"
            sleep 2
            return 1
        fi
        read -p " [*] 请输入邮箱 (用于自动申请证书，随意填): " email
        [[ -z "${email}" ]] && email="admin@${domain}"
        if ! is_valid_email "${email}"; then
            err "邮箱格式无效，请重新输入。"
            sleep 2
            return 1
        fi
        
        if ! write_ca_config "${port}" "${domain}" "${email}" "${password}" "${masquerade_url}"; then
            err "写入 CA 配置失败，请检查磁盘空间与目录权限。"
            sleep 2
            return 1
        fi
        set_server_config_permissions
        local sni="${domain}"
        local insecure="false"

    else
        msg "正在生成高强度自签名证书..."
        pick_self_signed_sni
        sni="${PICKED_SNI}"
        if ! is_valid_domain "${sni}"; then
            err "SNI 域名格式无效，请输入有效域名。"
            sleep 2
            return 1
        fi
        
        if ! openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout ${HY2_CONF_DIR}/server.key -out ${HY2_CONF_DIR}/server.crt \
        -subj "/CN=${sni}" -days 36500 >/dev/null 2>&1; then
            err "自签证书生成失败，请确认系统已安装 openssl。"
            sleep 2
            return 1
        fi
        
        set_tls_file_permissions
        
        if ! write_self_signed_config "${port}" "${password}" "${masquerade_url}"; then
            err "写入自签配置失败，请检查磁盘空间与目录权限。"
            sleep 2
            return 1
        fi
        set_server_config_permissions
        local insecure="true"
    fi

    SERVER_IP="$(fetch_server_ip)"
    if [[ -z "${SERVER_IP}" ]]; then
        err "无法获取服务器 IP，请检查网络后重试。"
        sleep 2
        return 1
    fi

    if ! write_meta_info "${SERVER_IP}" "${port}" "${password}" "${sni}" "${insecure}" "${up_mbps}" "${down_mbps}"; then
        err "写入节点元数据失败，请检查磁盘空间与目录权限。"
        sleep 2
        return 1
    fi
    chmod 600 "${HY2_META_FILE}" >/dev/null 2>&1 || true

    msg "检测到服务运行用户: $(get_service_run_user)"
    msg "正在重启 Hysteria2 服务以应用新配置..."
    if ! restart_service_with_rollback; then
        sleep 2
        return 1
    fi
    sleep 2
    if systemctl is-active --quiet "${HY2_SERVICE}"; then
        ok "Hysteria2 节点配置并启动成功！"
    else
        err "启动失败！可能是端口被占用，或 CA 证书申请失败。请使用菜单 (5) 查看日志。"
        show_service_failure_hint
        err "检测到服务未保持运行，正在尝试自动回滚到上一版配置..."
        if restore_runtime_files && systemctl restart "${HY2_SERVICE}"; then
            err "已自动回滚到上一版配置，本次变更未生效。"
        else
            err "自动回滚失败，请手动检查配置与日志。"
        fi
        show_recent_service_logs
        sleep 3
        return 1
    fi
    sleep 2
}

# --- 4. 客户端订阅与展示模块 ---

HY2_MODULE_CONFIG_LOADED=1
fi
