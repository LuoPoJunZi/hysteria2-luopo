#!/bin/bash
# ==========================================
# 项目: Hysteria2-LuoPo 核心管理面板 V1.0 (纯净极客版)
# 描述: 专为恶劣网络环境打造的极简 Hysteria2 运维脚本
# ==========================================

# --- 1. 全局变量与颜色输出 ---
sh_ver="v1.4.4"

_red="\033[0;31m"
_green="\033[0;32m"
_yellow="\033[0;33m"
_blue="\033[0;36m"
_plain="\033[0m"

HY2_CONF_DIR="/etc/hysteria"
HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
HY2_SERVICE="hysteria-server.service"
HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
HY2_DIAG_DIR="/tmp"
HY2_DIAG_LATEST="${HY2_DIAG_DIR}/hy2-diagnose-latest.log"
PANEL_UPDATE_URL="https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main/hy2.sh"
PANEL_TARGET_BIN="/usr/local/bin/hy2"
PANEL_BACKUP_PREFIX="/usr/local/bin/hy2.bak"
DEFAULT_PORT=443
DEFAULT_MASQUERADE_URL="https://bing.com"
DEFAULT_SELF_SNI="bing.com"
DEFAULT_UP_MBPS=20
DEFAULT_DOWN_MBPS=100
SELF_SNI_PRESETS=("bing.com" "www.cloudflare.com" "www.apple.com" "www.microsoft.com" "www.amazon.com")

msg() { echo -e "${_blue}[信息]${_plain} $1"; }
ok() { echo -e "${_green}[成功]${_plain} $1"; }
err() { echo -e "${_red}[错误]${_plain} $1"; }
print_line() { echo -e "${_blue}=====================================================${_plain}"; }
print_sub_line() { echo -e "${_blue}-----------------------------------------------------${_plain}"; }
wait_return() { read -n 1 -s -r -p "按任意键返回主菜单..."; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        err "请使用 root 用户运行此脚本。"
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "缺少依赖命令: ${cmd}"
        return 1
    fi
    return 0
}

preflight_check() {
    local missing=0
    local cmd
    for cmd in curl systemctl openssl grep awk sed hostname journalctl head mktemp chmod mv cp date; do
        if ! require_cmd "${cmd}"; then
            missing=1
        fi
    done
    if [[ "${missing}" -ne 0 ]]; then
        err "运行环境依赖不完整，请先安装缺失命令后重试。"
        exit 1
    fi
    if ! systemctl list-unit-files >/dev/null 2>&1; then
        err "当前系统未检测到可用的 systemd 环境，脚本无法继续运行。"
        exit 1
    fi
}

ensure_hy2_core_installed() {
    if ! command -v hysteria >/dev/null 2>&1; then
        err "未检测到 Hysteria2 内核，请先执行菜单 (1) 安装/更新内核。"
        return 1
    fi
    return 0
}

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

render_singbox_outbound_snippet() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"

    cat << EOF
{
  "type": "hysteria2",
  "tag": "proxy",
  "server": "${json_ip}",
  "server_port": ${port},
  "up_mbps": ${up_mbps},
  "down_mbps": ${down_mbps},
  "password": "${json_password}",
  "tls": {
    "enabled": true,
    "server_name": "${json_sni}",
    "insecure": ${insecure}
  }
}
EOF
}

render_v2rayn_yaml_snippet() {
    local ip="$1"
    local port="$2"
    local password="$3"
    local up_mbps="$4"
    local down_mbps="$5"
    local sni="$6"
    local insecure="$7"

    cat << EOF
server: ${ip}:${port}
auth: ${password}
bandwidth:
  up: ${up_mbps} mbps
  down: ${down_mbps} mbps
tls:
  sni: ${sni}
  insecure: ${insecure}
socks5:
  listen: 127.0.0.1:1080
http:
  listen: 127.0.0.1:8080
EOF
}

render_singbox_full_template() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"

    cat << EOF
{
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "cf",
        "server": "1.1.1.1"
      },
      {
        "type": "udp",
        "tag": "local",
        "server": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      },
      {
        "rule_set": "geosite-cn",
        "action": "route",
        "server": "local"
      }
    ],
    "final": "cf",
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": false
    }
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "${json_ip}",
      "server_port": ${port},
      "up_mbps": ${up_mbps},
      "down_mbps": ${down_mbps},
      "password": "${json_password}",
      "tls": {
        "enabled": true,
        "server_name": "${json_sni}",
        "insecure": ${insecure}
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-cn",
          "geoip-cn"
        ],
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      }
    ],
    "rule_set": [
      {
        "type": "remote",
        "tag": "geosite-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geosite-category-ads-all",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
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

service_control_menu() {
    while true; do
        clear
        print_line
        echo -e "               ${_green}--- 服务控制 ---${_plain}"
        print_line
        echo -e "    (1) 启动服务"
        echo -e "    (2) 停止服务"
        echo -e "    (3) 重启服务"
        echo -e "    (4) 查看状态"
        echo -e "    (0) 返回主菜单"
        print_line
        read -p " => 请选择操作 [0-4]: " action

        case "${action}" in
            1)
                if systemctl start "${HY2_SERVICE}"; then
                    ok "服务已启动。"
                else
                    err "启动失败，请检查日志。"
                fi
                sleep 1
                ;;
            2)
                if systemctl stop "${HY2_SERVICE}"; then
                    ok "服务已停止。"
                else
                    err "停止失败，请检查日志。"
                fi
                sleep 1
                ;;
            3)
                if systemctl restart "${HY2_SERVICE}"; then
                    ok "服务已重启。"
                else
                    err "重启失败，请检查日志。"
                fi
                sleep 1
                ;;
            4)
                if systemctl is-active --quiet "${HY2_SERVICE}"; then
                    ok "当前状态: 运行中"
                else
                    err "当前状态: 未运行"
                fi
                sleep 1
                ;;
            0) return 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}

# --- 2. 核心控制模块: 安装与卸载 ---
install_hy2_core() {
    if command -v hysteria &> /dev/null; then
        msg "Hysteria2 内核已安装，正在尝试更新..."
    else
        msg "正在调用官方脚本安装 Hysteria2 内核..."
    fi

    if ! bash <(curl -fsSL https://get.hy2.sh/); then
        err "内核安装/更新失败，请检查网络后重试。"
        return 1
    fi

    if ! systemctl enable "${HY2_SERVICE}" >/dev/null 2>&1; then
        err "已安装内核，但设置开机自启失败，请手动执行: systemctl enable ${HY2_SERVICE}"
        return 1
    fi
    ok "Hysteria2 内核部署/更新完成！"
}

verify_downloaded_panel() {
    local file="$1"
    local downloaded_version
    [[ -s "${file}" ]] || return 1
    head -n 1 "${file}" | grep -q '^#!/bin/bash' || return 1
    grep -q 'main_menu' "${file}" || return 1
    grep -q 'Hysteria2-LuoPo 管理面板' "${file}" || return 1
    downloaded_version="$(extract_panel_version "${file}")"
    [[ -n "${downloaded_version}" ]] || return 1
    return 0
}

extract_panel_version() {
    local file="$1"
    sed -n 's/^sh_ver="\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' "${file}" | head -n 1
}

backup_existing_panel() {
    local backup_file
    backup_file="${PANEL_BACKUP_PREFIX}.$(date '+%Y%m%d-%H%M%S')"
    if [[ ! -f "${PANEL_TARGET_BIN}" ]]; then
        return 0
    fi
    cp -p "${PANEL_TARGET_BIN}" "${backup_file}" || return 1
    printf '%s\n' "${backup_file}"
}

restore_panel_backup() {
    local backup_file="$1"
    [[ -n "${backup_file}" && -f "${backup_file}" ]] || return 1
    cp -p "${backup_file}" "${PANEL_TARGET_BIN}"
}

update_panel_script() {
    clear
    print_line
    echo -e "             ${_green}--- 更新管理面板脚本 ---${_plain}"
    print_line
    echo -e "当前版本: ${_yellow}${sh_ver}${_plain}"
    echo -e "目标路径: ${_yellow}${PANEL_TARGET_BIN}${_plain}"
    print_line
    read -p " => 确认从 GitHub 拉取最新面板脚本并覆盖本地 hy2？(y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        msg "已取消更新。"
        sleep 1
        return 0
    fi

    local tmp_file
    local backup_file=""
    local downloaded_version
    tmp_file="$(mktemp /tmp/hy2-panel.XXXXXX)" || {
        err "创建临时文件失败。"
        sleep 2
        return 1
    }

    msg "正在下载最新管理面板脚本..."
    if ! curl -fL --retry 2 --connect-timeout 8 -o "${tmp_file}" "${PANEL_UPDATE_URL}" >/dev/null 2>&1; then
        rm -f "${tmp_file}"
        err "下载失败，请检查网络或稍后重试。"
        sleep 2
        return 1
    fi

    if ! verify_downloaded_panel "${tmp_file}"; then
        rm -f "${tmp_file}"
        err "下载内容校验失败，已停止覆盖本地脚本。"
        sleep 2
        return 1
    fi

    downloaded_version="$(extract_panel_version "${tmp_file}")"
    msg "已下载版本: ${downloaded_version}"

    if [[ -f "${PANEL_TARGET_BIN}" ]]; then
        msg "正在备份当前面板脚本..."
        if ! backup_file="$(backup_existing_panel)"; then
            rm -f "${tmp_file}"
            err "备份当前脚本失败，已停止更新。"
            sleep 2
            return 1
        fi
        [[ -n "${backup_file}" ]] && msg "备份路径: ${backup_file}"
    fi

    if ! chmod +x "${tmp_file}" || ! mv -f "${tmp_file}" "${PANEL_TARGET_BIN}"; then
        rm -f "${tmp_file}"
        if [[ -n "${backup_file}" ]]; then
            restore_panel_backup "${backup_file}" >/dev/null 2>&1 || true
        fi
        err "写入 ${PANEL_TARGET_BIN} 失败，请检查权限。"
        sleep 2
        return 1
    fi

    ok "管理面板脚本已更新。重新输入 hy2 即可使用新版。"
    wait_return
}

uninstall_hy2() {
    print_line
    echo -e "${_red}[警告] 这将彻底卸载 Hysteria2 及所有节点配置！${_plain}"
    read -p " => 确定要继续吗？(y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop "${HY2_SERVICE}" >/dev/null 2>&1 || true
        systemctl disable "${HY2_SERVICE}" >/dev/null 2>&1 || true

        rm -f /usr/local/bin/hysteria
        rm -rf /etc/hysteria
        rm -f /etc/systemd/system/hysteria-server.service
        systemctl daemon-reload
        ok "Hysteria2 已彻底卸载！"

        rm -f /usr/local/bin/hy2
        exit 0
    else
        msg "已取消卸载。"
    fi
}

# --- 3. 核心控制模块: 节点配置与生成 ---
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
show_info() {
    if ! require_meta_info; then
        return
    fi

    clear
    print_line
    echo -e "               ${_green}--- Hysteria2 客户端配置 ---${_plain}"
    print_line
    echo -e "  [*] 服务器 IP : ${_yellow}${ip}${_plain}"
    echo -e "  [*] 端口      : ${_yellow}${port}${_plain}"
    echo -e "  [*] 密码      : ${_yellow}${password}${_plain}"
    echo -e "  [*] SNI伪装   : ${_yellow}${sni}${_plain}"
    echo -e "  [*] 跳过证书  : ${_yellow}${insecure}${_plain} (自签必须为true)"
    echo -e "  [*] 上行带宽  : ${_yellow}${up_mbps}${_plain} Mbps"
    echo -e "  [*] 下行带宽  : ${_yellow}${down_mbps}${_plain} Mbps"
    print_line

    local enc_password enc_sni url_host json_ip json_password json_sni
    enc_password="$(url_encode "${password}")"
    enc_sni="$(url_encode "${sni}")"
    url_host="$(format_host_for_url "${ip}")"
    local hy2_url="hysteria2://${enc_password}@${url_host}:${port}/?sni=${enc_sni}&insecure=${insecure}#Hysteria2-LuoPo"

    json_ip="$(json_escape "${ip}")"
    json_password="$(json_escape "${password}")"
    json_sni="$(json_escape "${sni}")"
    echo -e "${_green}[Link] 一键导入链接 (推荐 V2rayN / NekoBox / Clash):${_plain}"
    echo -e "${hy2_url}"
    print_line

    echo -e "${_green}[JSON] Sing-box (Android/iOS) 专属 Outbound 模块:${_plain}"
    render_singbox_outbound_snippet "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}"
    print_line
    echo -e "${_green}[YAML] v2rayN / nekoray 自定义配置片段:${_plain}"
    render_v2rayn_yaml_snippet "${ip}" "${port}" "${password}" "${up_mbps}" "${down_mbps}" "${sni}" "${insecure}"
    print_line
    wait_return
}

show_cheatsheet() {
    clear
    print_line
    echo -e "               ${_green}--- 常用指令速查 ---${_plain}"
    print_line
    echo -e "${_green}[服务器管理]${_plain}"
    echo -e "bash <(curl -fsSL hy2.evzzz.com)"
    echo -e "bash <(curl -fsSL https://get.hy2.sh/)"
    echo -e "systemctl start ${HY2_SERVICE}"
    echo -e "systemctl restart ${HY2_SERVICE}"
    echo -e "systemctl status ${HY2_SERVICE} --no-pager -l"
    echo -e "systemctl stop ${HY2_SERVICE}"
    echo -e "systemctl enable ${HY2_SERVICE}"
    echo -e "journalctl -u ${HY2_SERVICE} --no-pager -n 100 -f"
    print_line
    echo -e "${_green}[自签证书生成]${_plain}"
    echo -e "openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \\"
    echo -e "  -keyout ${HY2_CONF_DIR}/server.key -out ${HY2_CONF_DIR}/server.crt \\"
    echo -e "  -subj \"/CN=bing.com\" -days 36500"
    print_line
    echo -e "${_green}[配置文件路径]${_plain}"
    echo -e "服务配置: ${HY2_CONF_FILE}"
    echo -e "元数据  : ${HY2_META_FILE}"
    print_line
    wait_return
}

show_singbox_template() {
    if ! require_meta_info; then
        return
    fi

    local json_ip json_password json_sni
    json_ip="$(json_escape "${ip}")"
    json_password="$(json_escape "${password}")"
    json_sni="$(json_escape "${sni}")"

    clear
    print_line
    echo -e "     ${_green}--- Sing-box 完整模板 (Android/iOS / 1.12+) ---${_plain}"
    print_line
    render_singbox_full_template "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}"
    print_line
    wait_return
}

show_diagnostics() {
    local ok_count=0
    local warn_count=0
    local fail_count=0
    local line_status
    local now_ts diag_file summary_plain
    local -a diag_conclusions=()
    local -a diag_suggestions=()
    local -a diag_commands=()
    now_ts="$(date '+%Y%m%d-%H%M%S')"
    diag_file="${HY2_DIAG_DIR}/hy2-diagnose-${now_ts}.log"
    : > "${diag_file}" 2>/dev/null || diag_file=""

    diag_log() {
        local text="$1"
        if [[ -n "${diag_file}" ]]; then
            echo -e "${text}" >> "${diag_file}"
        fi
    }

    print_result() {
        local level="$1"
        local text="$2"
        case "${level}" in
            OK)
                echo -e "${_green}[OK]${_plain} ${text}"
                diag_log "[OK] ${text}"
                ok_count=$((ok_count + 1))
                ;;
            WARN)
                echo -e "${_yellow}[WARN]${_plain} ${text}"
                diag_log "[WARN] ${text}"
                warn_count=$((warn_count + 1))
                ;;
            FAIL)
                echo -e "${_red}[FAIL]${_plain} ${text}"
                diag_log "[FAIL] ${text}"
                fail_count=$((fail_count + 1))
                ;;
        esac
    }

    add_diag_item() {
        local conclusion="$1"
        local suggestion="$2"
        local command_hint="$3"
        local existing
        for existing in "${diag_conclusions[@]}"; do
            if [[ "${existing}" == "${conclusion}" ]]; then
                return 0
            fi
        done
        diag_conclusions+=("${conclusion}")
        diag_suggestions+=("${suggestion}")
        diag_commands+=("${command_hint}")
    }

    clear
    print_line
    echo -e "             ${_green}--- 一键环境诊断 ---${_plain}"
    print_line
    if [[ -n "${diag_file}" ]]; then
        diag_log "=== Hysteria2-LuoPo Diagnose @ ${now_ts} ==="
        diag_log "config_file=${HY2_CONF_FILE}"
        diag_log "meta_file=${HY2_META_FILE}"
        diag_log "service=${HY2_SERVICE}"
    fi

    if ensure_hy2_core_installed; then
        print_result "OK" "已检测到 Hysteria2 内核。"
    else
        print_result "FAIL" "未检测到 Hysteria2 内核。请先执行菜单 (1)。"
        add_diag_item \
            "未安装 Hysteria2 内核。" \
            "先安装内核，再进行节点配置与启动服务。" \
            "菜单 (1) 一键安装/更新 Hysteria2 内核"
    fi

    if systemctl is-enabled "${HY2_SERVICE}" >/dev/null 2>&1; then
        print_result "OK" "服务已设置开机自启。"
    else
        print_result "WARN" "服务未设置开机自启，可执行: systemctl enable ${HY2_SERVICE}"
        add_diag_item \
            "服务未开启开机自启。" \
            "建议开启自启，避免重启后节点离线。" \
            "systemctl enable ${HY2_SERVICE}"
    fi

    if systemctl is-active --quiet "${HY2_SERVICE}"; then
        print_result "OK" "服务当前状态: 运行中。"
    else
        print_result "WARN" "服务当前未运行，可执行菜单 (4) 启动/重启。"
        add_diag_item \
            "服务当前未运行。" \
            "先尝试启动服务，若失败再看实时日志定位原因。" \
            "systemctl restart ${HY2_SERVICE} && journalctl -u ${HY2_SERVICE} --no-pager -n 60"
    fi

    if [[ -f "${HY2_CONF_FILE}" ]]; then
        print_result "OK" "配置文件存在: ${HY2_CONF_FILE}"
    else
        print_result "FAIL" "配置文件不存在: ${HY2_CONF_FILE}"
        add_diag_item \
            "服务配置文件缺失。" \
            "重新执行节点配置生成 config.yaml。" \
            "菜单 (2) 配置 Hysteria2 节点 (CA / 自签)"
    fi

    if [[ -f "${HY2_META_FILE}" ]] && read_meta_info; then
        print_result "OK" "节点元数据存在且可解析。"
    else
        print_result "WARN" "节点元数据缺失或损坏，建议重新执行菜单 (2)。"
        add_diag_item \
            "节点元数据缺失或损坏。" \
            "重新生成节点配置，确保分享链接参数准确。" \
            "菜单 (2) 配置 Hysteria2 节点 (CA / 自签)"
    fi

    if [[ -f "${HY2_CONF_FILE}" ]]; then
        local listen_port
        listen_port="$(sed -n 's/^listen:[[:space:]]*:\([0-9]\+\).*/\1/p' "${HY2_CONF_FILE}" | head -n 1)"
        if [[ -n "${listen_port}" ]]; then
            print_result "OK" "监听端口配置为: ${listen_port}"
            if command -v ss >/dev/null 2>&1; then
                if ss -lun 2>/dev/null | grep -qE "[\:\.]${listen_port}[[:space:]]"; then
                    print_result "OK" "检测到 UDP 端口 ${listen_port} 正在监听。"
                else
                    print_result "WARN" "未检测到 UDP 端口 ${listen_port} 监听，可能服务未启动。"
                    add_diag_item \
                        "未检测到 UDP 端口 ${listen_port} 监听。" \
                        "可能服务未运行或端口被占用，请先检查服务与端口占用。" \
                        "ss -lntup | grep -E \"[:.]${listen_port}[[:space:]]\""
                fi
            else
                print_result "WARN" "系统未安装 ss，跳过端口监听检查。"
            fi
        else
            print_result "WARN" "未能从配置中解析 listen 端口。"
            add_diag_item \
                "无法从配置解析 listen 端口。" \
                "请检查 config.yaml 语法与 listen 字段格式。" \
                "hysteria server -c ${HY2_CONF_FILE}"
        fi

        if grep -q '^tls:' "${HY2_CONF_FILE}"; then
            local cert_path key_path
            cert_path="$(sed -n 's/^[[:space:]]*cert:[[:space:]]*//p' "${HY2_CONF_FILE}" | head -n 1)"
            key_path="$(sed -n 's/^[[:space:]]*key:[[:space:]]*//p' "${HY2_CONF_FILE}" | head -n 1)"
            if [[ -n "${cert_path}" && -f "${cert_path}" ]]; then
                print_result "OK" "自签证书文件存在: ${cert_path}"
            else
                print_result "FAIL" "自签证书文件缺失。"
                add_diag_item \
                    "自签证书文件缺失。" \
                    "重新执行自签配置生成证书，或检查证书路径。" \
                    "菜单 (2) -> 自签模式重新生成"
            fi
            if [[ -n "${key_path}" && -f "${key_path}" ]]; then
                print_result "OK" "自签私钥文件存在: ${key_path}"
            else
                print_result "FAIL" "自签私钥文件缺失。"
                add_diag_item \
                    "自签私钥文件缺失。" \
                    "重新执行自签配置生成私钥，确认文件权限可读。" \
                    "菜单 (2) -> 自签模式重新生成"
            fi
        elif grep -q '^acme:' "${HY2_CONF_FILE}"; then
            print_result "OK" "当前为 CA 证书模式。"
        else
            print_result "WARN" "未检测到 tls/acme 配置块，请确认配置正确。"
            add_diag_item \
                "配置未识别到 tls/acme 证书块。" \
                "配置内容可能异常，建议重新生成节点配置。" \
                "菜单 (2) 重新配置节点"
        fi
    fi

    local probe_ip
    probe_ip="$(fetch_server_ip)"
    if [[ -n "${probe_ip}" ]]; then
        print_result "OK" "公网 IP 探测成功: ${probe_ip}"
        if [[ -n "${ip:-}" && "${ip}" != "${probe_ip}" ]]; then
            print_result "WARN" "元数据 IP(${ip}) 与当前探测 IP(${probe_ip}) 不一致。"
            add_diag_item \
                "元数据 IP 与当前公网 IP 不一致。" \
                "客户端可能连向旧 IP，建议更新客户端配置。" \
                "菜单 (3) 重新获取分享链接并覆盖客户端配置"
        fi
    else
        print_result "WARN" "公网 IP 探测失败，请检查网络连接。"
        add_diag_item \
            "公网 IP 探测失败。" \
            "可能是本机网络受限或 DNS 问题，先验证基础网络连通。" \
            "curl -4 https://api.ipify.org && curl -6 https://api64.ipify.org"
    fi

    print_line
    if (( fail_count > 0 )); then
        line_status="${_red}诊断结果: ${ok_count} OK / ${warn_count} WARN / ${fail_count} FAIL${_plain}"
        summary_plain="诊断结果: ${ok_count} OK / ${warn_count} WARN / ${fail_count} FAIL"
    elif (( warn_count > 0 )); then
        line_status="${_yellow}诊断结果: ${ok_count} OK / ${warn_count} WARN / 0 FAIL${_plain}"
        summary_plain="诊断结果: ${ok_count} OK / ${warn_count} WARN / 0 FAIL"
    else
        line_status="${_green}诊断结果: ${ok_count} OK / 0 WARN / 0 FAIL${_plain}"
        summary_plain="诊断结果: ${ok_count} OK / 0 WARN / 0 FAIL"
    fi
    echo -e "${line_status}"
    diag_log "${summary_plain}"
    echo -e "${_blue}[分级]${_plain} 阻断项(FAIL): ${fail_count} | 警告项(WARN): ${warn_count} | 建议项: ${#diag_conclusions[@]}"
    diag_log "分级: 阻断项(FAIL)=${fail_count}, 警告项(WARN)=${warn_count}, 建议项=${#diag_conclusions[@]}"
    if (( ${#diag_conclusions[@]} > 0 )); then
        local idx
        print_line
        echo -e "${_yellow}[诊断建议]${_plain} 结论 + 建议 + 命令"
        diag_log "--- 诊断建议 ---"
        for idx in "${!diag_conclusions[@]}"; do
            echo -e "  [结论] ${diag_conclusions[${idx}]}"
            echo -e "  [建议] ${diag_suggestions[${idx}]}"
            echo -e "  [命令] ${diag_commands[${idx}]}"
            echo -e ""
            diag_log "[结论] ${diag_conclusions[${idx}]}"
            diag_log "[建议] ${diag_suggestions[${idx}]}"
            diag_log "[命令] ${diag_commands[${idx}]}"
            diag_log ""
        done
    fi
    if [[ -n "${diag_file}" ]]; then
        cp -f "${diag_file}" "${HY2_DIAG_LATEST}" >/dev/null 2>&1 || true
        echo -e "${_blue}[信息]${_plain} 诊断报告已导出: ${diag_file}"
        echo -e "${_blue}[信息]${_plain} 最新报告快捷路径: ${HY2_DIAG_LATEST}"
    else
        echo -e "${_yellow}[提示]${_plain} 诊断报告导出失败，仅显示终端结果。"
    fi
    print_line
    wait_return
}

show_latest_diagnostics_report() {
    clear
    print_line
    echo -e "            ${_green}--- 最近诊断报告 ---${_plain}"
    print_line
    if [[ ! -f "${HY2_DIAG_LATEST}" ]]; then
        err "未找到最近诊断报告。请先执行菜单 (9) 一键环境诊断。"
        print_line
        wait_return
        return
    fi
    cat "${HY2_DIAG_LATEST}"
    print_line
    wait_return
}

create_manual_backup() {
    local ts backup_dir
    ts="$(date '+%Y%m%d-%H%M%S')"
    backup_dir="${HY2_BACKUP_DIR}/manual-${ts}"
    if ! mkdir -p "${backup_dir}"; then
        err "创建备份目录失败: ${backup_dir}"
        return 1
    fi
    cp -f "${HY2_CONF_FILE}" "${backup_dir}/config.yaml" 2>/dev/null || true
    cp -f "${HY2_META_FILE}" "${backup_dir}/meta.info" 2>/dev/null || true
    cp -f "${HY2_CONF_DIR}/server.crt" "${backup_dir}/server.crt" 2>/dev/null || true
    cp -f "${HY2_CONF_DIR}/server.key" "${backup_dir}/server.key" 2>/dev/null || true
    ok "手动备份完成: ${backup_dir}"
    return 0
}

restore_latest_manual_backup() {
    local latest_dir
    latest_dir="$(ls -1dt "${HY2_BACKUP_DIR}"/manual-* 2>/dev/null | head -n 1 || true)"
    if [[ -z "${latest_dir}" || ! -d "${latest_dir}" ]]; then
        err "未找到可恢复的手动备份。"
        return 1
    fi

    if [[ ! -f "${latest_dir}/config.yaml" ]]; then
        err "备份中缺少 config.yaml，已中止恢复: ${latest_dir}"
        return 1
    fi
    if ! cp -f "${latest_dir}/config.yaml" "${HY2_CONF_FILE}" 2>/dev/null; then
        err "恢复 config.yaml 失败，请检查目录权限: ${HY2_CONF_FILE}"
        return 1
    fi
    if [[ -f "${latest_dir}/meta.info" ]] && ! cp -f "${latest_dir}/meta.info" "${HY2_META_FILE}" 2>/dev/null; then
        err "恢复 meta.info 失败，请检查目录权限: ${HY2_META_FILE}"
        return 1
    fi
    cp -f "${latest_dir}/server.crt" "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true
    cp -f "${latest_dir}/server.key" "${HY2_CONF_DIR}/server.key" 2>/dev/null || true
    set_config_dir_permissions
    set_server_config_permissions
    chmod 600 "${HY2_META_FILE}" 2>/dev/null || true
    chmod 600 "${HY2_CONF_DIR}/server.key" 2>/dev/null || true
    chmod 644 "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true

    if systemctl restart "${HY2_SERVICE}" >/dev/null 2>&1; then
        ok "已恢复最近备份并重启服务: ${latest_dir}"
    else
        err "已恢复文件，但服务重启失败，请查看日志。"
    fi
    return 0
}

show_backup_restore_menu() {
    while true; do
        clear
        print_line
        echo -e "           ${_green}--- 配置备份与恢复 ---${_plain}"
        print_line
        echo -e "    (1) 创建手动备份"
        echo -e "    (2) 恢复最近手动备份"
        echo -e "    (3) 查看手动备份列表"
        echo -e "    (0) 返回主菜单"
        print_line
        read -p " => 请选择操作 [0-3]: " action

        case "${action}" in
            1)
                create_manual_backup
                sleep 1
                ;;
            2)
                restore_latest_manual_backup
                sleep 2
                ;;
            3)
                echo -e "${_green}[备份列表]${_plain}"
                ls -1dt "${HY2_BACKUP_DIR}"/manual-* 2>/dev/null || echo "(空)"
                print_line
                wait_return
                ;;
            0) return 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}

# --- 5. 主菜单系统 (高兼容极客版) ---
main_menu() {
    while true; do
        clear
        print_line
        echo -e "  ${_green}Hysteria2-LuoPo 管理面板 ${sh_ver} |  快捷启动: hy2${_plain}"
        print_line

        local status="${_red}未运行${_plain}"
        local core_version="未安装"
        if command -v hysteria &> /dev/null; then
            # 精准抓取版本号，过滤 ASCII 图案
            core_version=$(hysteria version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
            [[ -z "$core_version" ]] && core_version="未知版本"

            if systemctl is-active --quiet "${HY2_SERVICE}"; then
                status="${_green}运行中${_plain}"
            fi
        fi

        echo -e "  内核版本: ${core_version}    服务状态: ${status}"
        print_sub_line
        echo -e "  节点核心管理"
        echo -e "    (1)  一键安装/更新 Hysteria2 内核"
        echo -e "    (2)  配置 Hysteria2 节点 (CA / 自签)"
        echo -e "    (3)  查看客户端配置与分享链接"
        echo -e ""
        echo -e "  服务运行控制"
        echo -e "    (4)  启动 / 停止 / 重启 / 状态"
        echo -e "    (5)  查看实时运行日志"
        echo -e "    (6)  完全卸载清理"
        echo -e "    (7)  查看常用指令速查"
        echo -e "    (8)  查看 Sing-box 完整模板"
        echo -e "    (9)  一键环境诊断"
        echo -e "    (10) 查看最近诊断报告"
        echo -e "    (11) 配置备份与恢复"
        echo -e "    (12) 更新管理面板脚本"
        echo -e "    (0)  退出面板"
        print_line

        read -p " => 请选择操作 [0-12]: " menu_num

        case "${menu_num}" in
            1) install_hy2_core; sleep 2 ;;
            2) config_hy2 ;;
            3) show_info ;;
            4)
                if ensure_hy2_core_installed; then
                    service_control_menu
                else
                    sleep 2
                fi
                ;;
            5)
                if ensure_hy2_core_installed; then
                    journalctl -u "${HY2_SERVICE}" --no-pager -n 100 -f
                else
                    sleep 2
                fi
                ;;
            6) uninstall_hy2 ;;
            7) show_cheatsheet ;;
            8) show_singbox_template ;;
            9) show_diagnostics ;;
            10) show_latest_diagnostics_report ;;
            11) show_backup_restore_menu ;;
            12) update_panel_script ;;
            0) exit 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}

# 入口运行
if [[ "${HY2_LIB_ONLY:-0}" != "1" ]]; then
    require_root
    preflight_check
    main_menu
fi
