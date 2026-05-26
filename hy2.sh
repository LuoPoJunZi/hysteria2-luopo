#!/bin/bash
# ==========================================
# 项目: Hysteria2-LuoPo 核心管理面板 V1.0 (纯净极客版)
# 描述: 专为恶劣网络环境打造的极简 Hysteria2 运维脚本
# ==========================================

# --- 1. 全局变量与颜色输出 ---
sh_ver="v1.4.1"

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
PANEL_UPDATE_BASE_URL="https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main"
PANEL_UPDATE_URL="${PANEL_UPDATE_BASE_URL}/hy2.sh"
PANEL_TARGET_BIN="/usr/local/bin/hy2"
PANEL_TARGET_LIB_DIR="${PANEL_TARGET_LIB_DIR:-/usr/local/lib/hy2-luopo}"
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
    for cmd in curl systemctl openssl grep awk hostname journalctl head mktemp chmod mv cp mkdir rm; do
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


HY2_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${HY2_LIB_DIR:-}" ]]; then
    if [[ -d "${HY2_SCRIPT_DIR}/lib/hy2" ]]; then
        HY2_LIB_DIR="${HY2_SCRIPT_DIR}/lib/hy2"
    else
        HY2_LIB_DIR="/usr/local/lib/hy2-luopo"
    fi
fi

HY2_CORE_VERSION_CACHE=""

panel_module_list() {
    echo "common core config client diagnostics backup"
}

download_bootstrap_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 2 --connect-timeout 8 -o "${output}" "${url}" >/dev/null 2>&1 && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qO "${output}" "${url}" >/dev/null 2>&1 && return 0
    fi
    return 1
}

bootstrap_panel_modules() {
    local target_lib="${PANEL_TARGET_LIB_DIR}"
    local tmp_dir module
    tmp_dir="$(mktemp -d /tmp/hy2-modules.XXXXXX)" || return 1
    mkdir -p "${tmp_dir}/lib" || {
        rm -rf "${tmp_dir}"
        return 1
    }

    for module in $(panel_module_list); do
        if ! download_bootstrap_file "${PANEL_UPDATE_BASE_URL}/lib/hy2/${module}.sh" "${tmp_dir}/lib/${module}.sh"; then
            rm -rf "${tmp_dir}"
            return 1
        fi
        if ! grep -q "HY2_MODULE_${module^^}_LOADED" "${tmp_dir}/lib/${module}.sh"; then
            rm -rf "${tmp_dir}"
            return 1
        fi
    done

    mkdir -p "${target_lib}" || {
        rm -rf "${tmp_dir}"
        return 1
    }
    for module in $(panel_module_list); do
        cp -f "${tmp_dir}/lib/${module}.sh" "${target_lib}/${module}.sh" || {
            rm -rf "${tmp_dir}"
            return 1
        }
    done
    chmod 644 "${target_lib}"/*.sh >/dev/null 2>&1 || true
    rm -rf "${tmp_dir}"
    HY2_LIB_DIR="${target_lib}"
    return 0
}

load_module() {
    local module="$1"
    case "${module}" in
        common|core|config|client|diagnostics|backup) ;;
        *) err "unknown module: ${module}"; return 1 ;;
    esac

    local loaded_var="HY2_MODULE_${module^^}_LOADED"
    if [[ "${!loaded_var:-0}" == "1" ]]; then
        return 0
    fi

    local module_file="${HY2_LIB_DIR}/${module}.sh"
    if [[ ! -r "${module_file}" ]]; then
        if [[ "${HY2_DISABLE_MODULE_BOOTSTRAP:-0}" != "1" ]]; then
            msg "missing module directory, trying to bootstrap panel modules..."
        fi
        if [[ "${HY2_DISABLE_MODULE_BOOTSTRAP:-0}" != "1" ]] && bootstrap_panel_modules; then
            module_file="${HY2_LIB_DIR}/${module}.sh"
        fi
    fi
    if [[ ! -r "${module_file}" ]]; then
        err "missing module: ${module_file}"
        return 1
    fi

    # shellcheck source=/dev/null
    . "${module_file}"
    if [[ "${!loaded_var:-0}" != "1" ]]; then
        err "failed to load module: ${module}"
        return 1
    fi
    return 0
}

get_core_version_cached() {
    if ! command -v hysteria >/dev/null 2>&1; then
        printf "%s" "not installed"
        return 0
    fi
    if [[ -z "${HY2_CORE_VERSION_CACHE}" ]]; then
        HY2_CORE_VERSION_CACHE="$(hysteria version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
        [[ -z "${HY2_CORE_VERSION_CACHE}" ]] && HY2_CORE_VERSION_CACHE="unknown version"
    fi
    printf "%s" "${HY2_CORE_VERSION_CACHE}"
}

refresh_core_version_cache() {
    HY2_CORE_VERSION_CACHE=""
}

main_menu() {
    while true; do
        clear
        print_line
        echo -e "  ${_green}Hysteria2-LuoPo 管理面板 ${sh_ver} |  快捷启动: hy2${_plain}"
        print_line
        
        local status="${_red}stopped${_plain}"
        local core_version
        core_version="$(get_core_version_cached)"
        if command -v hysteria >/dev/null 2>&1 && systemctl is-active --quiet "${HY2_SERVICE}"; then
            status="${_green}running${_plain}"
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
            1) load_module core && install_hy2_core; refresh_core_version_cache; sleep 2 ;;
            2) load_module config && config_hy2 ;;
            3) load_module client && show_info ;;
            4)
                if ensure_hy2_core_installed; then
                    load_module core && service_control_menu
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
            6) load_module core && uninstall_hy2 ;;
            7) load_module client && show_cheatsheet ;;
            8) load_module client && show_singbox_template ;;
            9) load_module diagnostics && show_diagnostics ;;
            10) load_module diagnostics && show_latest_diagnostics_report ;;
            11) load_module backup && show_backup_restore_menu ;;
            12) load_module core && update_panel_script ;;
            0) exit 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}


# Runtime entrypoint
if [[ "${HY2_LIB_ONLY:-0}" != "1" ]]; then
    require_root
    preflight_check
    main_menu
fi
