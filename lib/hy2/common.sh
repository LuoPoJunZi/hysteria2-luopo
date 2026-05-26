# shellcheck shell=bash
if [[ "${HY2_MODULE_COMMON_LOADED:-0}" != "1" ]]; then
is_valid_port() {
    local p="$1"
    [[ "${p}" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

is_valid_domain() {
    local d="$1"
    [[ "${d}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

is_valid_url() {
    local u="$1"
    [[ "${u}" =~ ^https?://[^[:space:]]+$ ]]
}

is_valid_email() {
    local e="$1"
    [[ "${e}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

yaml_single_quote() {
    local raw="$1"
    local escaped="${raw//\'/\'\'}"
    printf "'%s'" "${escaped}"
}

url_encode() {
    local raw="$1"
    local length="${#raw}"
    local i char out=""
    for (( i = 0; i < length; i++ )); do
        char="${raw:i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_-]) out+="${char}" ;;
            *) printf -v out '%s%%%02X' "${out}" "'${char}" ;;
        esac
    done
    printf '%s' "${out}"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "${s}"
}

format_host_for_url() {
    local host="$1"
    if [[ "${host}" == *:* ]]; then
        printf '[%s]' "${host}"
        return
    fi
    printf '%s' "${host}"
}

write_file_atomic() {
    local target="$1"
    local tmp_file
    tmp_file="$(mktemp "${target}.tmp.XXXXXX")" || return 1
    if ! cat > "${tmp_file}"; then
        rm -f "${tmp_file}" >/dev/null 2>&1 || true
        return 1
    fi
    if ! mv -f "${tmp_file}" "${target}"; then
        rm -f "${tmp_file}" >/dev/null 2>&1 || true
        return 1
    fi
    return 0
}

backup_runtime_files() {
    mkdir -p "${HY2_BACKUP_DIR}" || return 1
    cp -f "${HY2_CONF_FILE}" "${HY2_BACKUP_DIR}/config.yaml.bak" 2>/dev/null || true
    cp -f "${HY2_META_FILE}" "${HY2_BACKUP_DIR}/meta.info.bak" 2>/dev/null || true
    cp -f "${HY2_CONF_DIR}/server.crt" "${HY2_BACKUP_DIR}/server.crt.bak" 2>/dev/null || true
    cp -f "${HY2_CONF_DIR}/server.key" "${HY2_BACKUP_DIR}/server.key.bak" 2>/dev/null || true
    return 0
}

restore_runtime_files() {
    local restored=0
    if [[ -f "${HY2_BACKUP_DIR}/config.yaml.bak" ]]; then
        cp -f "${HY2_BACKUP_DIR}/config.yaml.bak" "${HY2_CONF_FILE}" && restored=1
    fi
    if [[ -f "${HY2_BACKUP_DIR}/meta.info.bak" ]]; then
        cp -f "${HY2_BACKUP_DIR}/meta.info.bak" "${HY2_META_FILE}" || true
    fi
    if [[ -f "${HY2_BACKUP_DIR}/server.crt.bak" ]]; then
        cp -f "${HY2_BACKUP_DIR}/server.crt.bak" "${HY2_CONF_DIR}/server.crt" || true
    fi
    if [[ -f "${HY2_BACKUP_DIR}/server.key.bak" ]]; then
        cp -f "${HY2_BACKUP_DIR}/server.key.bak" "${HY2_CONF_DIR}/server.key" || true
    fi
    set_config_dir_permissions
    if [[ -f "${HY2_CONF_FILE}" ]]; then
        set_server_config_permissions
    fi
    chmod 600 "${HY2_META_FILE}" >/dev/null 2>&1 || true
    if [[ -f "${HY2_CONF_DIR}/server.key" ]]; then
        set_tls_file_permissions
    fi
    if [[ "${restored}" -eq 1 ]]; then
        return 0
    fi
    return 1
}

fetch_server_ip() {
    local ip
    ip="$(curl -fsS4 --max-time 6 https://api.ipify.org 2>/dev/null || true)"
    if [[ -z "${ip}" ]]; then
        ip="$(curl -fsS6 --max-time 6 https://api64.ipify.org 2>/dev/null || true)"
    fi
    if [[ -z "${ip}" ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    fi
    echo "${ip}"
}

read_meta_info() {
    ip=""
    port=""
    password=""
    sni=""
    insecure=""
    up_mbps=""
    down_mbps=""

    while IFS='=' read -r key value; do
        case "${key}" in
            ip) ip="${value}" ;;
            port) port="${value}" ;;
            password) password="${value}" ;;
            sni) sni="${value}" ;;
            insecure) insecure="${value}" ;;
            up_mbps) up_mbps="${value}" ;;
            down_mbps) down_mbps="${value}" ;;
        esac
    done < "${HY2_META_FILE}"

    if [[ -z "${ip}" || -z "${port}" || -z "${password}" || -z "${sni}" || -z "${insecure}" ]]; then
        return 1
    fi
    if ! is_valid_port "${port}"; then
        return 1
    fi
    if [[ "${insecure}" != "true" && "${insecure}" != "false" ]]; then
        return 1
    fi
    [[ -z "${up_mbps}" ]] && up_mbps="${DEFAULT_UP_MBPS}"
    [[ -z "${down_mbps}" ]] && down_mbps="${DEFAULT_DOWN_MBPS}"
    if ! [[ "${up_mbps}" =~ ^[0-9]+$ ]] || ! [[ "${down_mbps}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if (( up_mbps < 1 || down_mbps < 1 )); then
        return 1
    fi
    return 0
}

require_meta_info() {
    if [[ ! -f "${HY2_META_FILE}" ]]; then
        err "未找到节点元数据，请先执行 (2) 配置 Hysteria2 节点！"
        sleep 2
        return 1
    fi
    if ! read_meta_info; then
        err "节点元数据损坏或缺失，请重新执行 (2) 配置节点。"
        sleep 2
        return 1
    fi
    return 0
}

set_config_dir_permissions() {
    local run_user
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        chown root:"${run_user}" "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
        chmod 750 "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
    else
        chmod 755 "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
    fi
}

set_server_config_permissions() {
    local run_user
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        chown root:"${run_user}" "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
        chmod 640 "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
    else
        chmod 644 "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
    fi
}

write_meta_info() {
    local ip="$1"
    local port="$2"
    local password="$3"
    local sni="$4"
    local insecure="$5"
    local up_mbps="$6"
    local down_mbps="$7"

    cat << EOF | write_file_atomic "${HY2_META_FILE}"
ip=${ip}
port=${port}
password=${password}
sni=${sni}
insecure=${insecure}
up_mbps=${up_mbps}
down_mbps=${down_mbps}
EOF
}

get_service_run_user() {
    local run_user
    run_user="$(systemctl show -p User --value "${HY2_SERVICE}" 2>/dev/null || true)"
    [[ -z "${run_user}" ]] && run_user="root"
    echo "${run_user}"
}

set_tls_file_permissions() {
    local run_user
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        chown "${run_user}:${run_user}" "${HY2_CONF_DIR}/server.key" "${HY2_CONF_DIR}/server.crt" >/dev/null 2>&1 || true
    fi
    chmod 600 "${HY2_CONF_DIR}/server.key" >/dev/null 2>&1 || true
    chmod 644 "${HY2_CONF_DIR}/server.crt" >/dev/null 2>&1 || true
}

restart_service_with_rollback() {
    if systemctl restart "${HY2_SERVICE}"; then
        return 0
    fi
    err "重启服务失败，正在尝试自动回滚到上一版配置..."
    show_service_failure_hint
    if restore_runtime_files && systemctl restart "${HY2_SERVICE}"; then
        err "已回滚到上一版配置，本次变更未生效。"
    else
        err "自动回滚失败，请手动检查 ${HY2_CONF_FILE} 和服务日志。"
    fi
    return 1
}

show_recent_service_logs() {
    print_line
    echo -e "${_yellow}[提示]${_plain} 最近 20 行服务日志："
    journalctl -u "${HY2_SERVICE}" --no-pager -n 20 2>/dev/null || true
    print_line
}

show_service_failure_hint() {
    local logs
    logs="$(journalctl -u "${HY2_SERVICE}" --no-pager -n 60 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [[ -z "${logs}" ]] && return 0

    if [[ "${logs}" == *"permission denied"* && "${logs}" == *"config.yaml"* ]]; then
        err "诊断结论：服务用户无权读取 config.yaml。"
        echo -e "      建议执行：systemctl show -p User,Group ${HY2_SERVICE}"
        echo -e "      建议执行：namei -l ${HY2_CONF_FILE}"
        return 0
    fi
    if [[ "${logs}" == *"address already in use"* || "${logs}" == *"bind: address already in use"* ]]; then
        err "诊断结论：监听端口被占用。"
        echo -e "      建议执行：ss -lntp | grep \":${port:-443}\\b\""
        return 0
    fi
    if [[ "${logs}" == *"acme"* && ( "${logs}" == *"timeout"* || "${logs}" == *"no such host"* || "${logs}" == *"dns"* ) ]]; then
        err "诊断结论：CA 证书申请失败（可能是 DNS/80/443 不通）。"
        echo -e "      建议检查：域名 A/AAAA 解析、80/443 入站、防火墙与云安全组。"
        return 0
    fi
    if [[ "${logs}" == *"failed to read server config"* || "${logs}" == *"yaml"* || "${logs}" == *"parse"* ]]; then
        err "诊断结论：配置文件内容异常或格式错误。"
        echo -e "      建议执行：hysteria server -c ${HY2_CONF_FILE}"
        return 0
    fi
}

HY2_MODULE_COMMON_LOADED=1
fi
