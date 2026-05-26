# shellcheck shell=bash
if [[ "${HY2_MODULE_CORE_LOADED:-0}" != "1" ]]; then
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
    [[ -s "${file}" ]] || return 1
    head -n 1 "${file}" | grep -q '^#!/bin/bash' || return 1
    grep -q 'main_menu' "${file}" || return 1
    grep -q 'load_module' "${file}" || return 1
    return 0
}

panel_module_list() {
    echo "common core config client diagnostics backup"
}

verify_downloaded_panel_bundle() {
    local bundle_dir="$1"
    local module
    verify_downloaded_panel "${bundle_dir}/hy2.sh" || return 1
    for module in $(panel_module_list); do
        [[ -s "${bundle_dir}/lib/hy2/${module}.sh" ]] || return 1
        grep -q "HY2_MODULE_${module^^}_LOADED" "${bundle_dir}/lib/hy2/${module}.sh" || return 1
    done
    return 0
}

download_panel_file() {
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

install_panel_bundle_from_dir() {
    local bundle_dir="$1"
    local target_bin="${PANEL_TARGET_BIN}"
    local target_lib="${PANEL_TARGET_LIB_DIR:-${HY2_LIB_DIR:-/usr/local/lib/hy2-luopo}}"
    local target_bin_dir target_lib_parent new_lib old_lib tmp_bin module

    target_bin_dir="$(dirname "${target_bin}")"
    target_lib_parent="$(dirname "${target_lib}")"
    mkdir -p "${target_bin_dir}" "${target_lib_parent}" || return 1

    new_lib="$(mktemp -d "${target_lib}.new.XXXXXX")" || return 1
    for module in $(panel_module_list); do
        cp -f "${bundle_dir}/lib/hy2/${module}.sh" "${new_lib}/${module}.sh" || {
            rm -rf "${new_lib}"
            return 1
        }
    done
    chmod 755 "${new_lib}" >/dev/null 2>&1 || true
    chmod 644 "${new_lib}"/*.sh >/dev/null 2>&1 || true

    tmp_bin="$(mktemp "${target_bin_dir}/.hy2.XXXXXX")" || {
        rm -rf "${new_lib}"
        return 1
    }
    cp -f "${bundle_dir}/hy2.sh" "${tmp_bin}" || {
        rm -rf "${new_lib}" "${tmp_bin}"
        return 1
    }
    chmod +x "${tmp_bin}" || {
        rm -rf "${new_lib}" "${tmp_bin}"
        return 1
    }

    old_lib=""
    if [[ -d "${target_lib}" ]]; then
        old_lib="${target_lib}.bak.$$"
        mv "${target_lib}" "${old_lib}" || {
            rm -rf "${new_lib}" "${tmp_bin}"
            return 1
        }
    fi
    if ! mv "${new_lib}" "${target_lib}"; then
        [[ -n "${old_lib}" && -d "${old_lib}" ]] && mv "${old_lib}" "${target_lib}" >/dev/null 2>&1 || true
        rm -rf "${new_lib}" "${tmp_bin}"
        return 1
    fi
    if ! mv -f "${tmp_bin}" "${target_bin}"; then
        rm -f "${tmp_bin}"
        rm -rf "${target_lib}"
        [[ -n "${old_lib}" && -d "${old_lib}" ]] && mv "${old_lib}" "${target_lib}" >/dev/null 2>&1 || true
        return 1
    fi
    [[ -n "${old_lib}" ]] && rm -rf "${old_lib}"
    return 0
}

update_panel_script() {
    clear
    print_line
    echo -e "             ${_green}--- Update Panel ---${_plain}"
    print_line
    echo -e "Current version: ${_yellow}${sh_ver}${_plain}"
    echo -e "Target command: ${_yellow}${PANEL_TARGET_BIN}${_plain}"
    echo -e "Module dir: ${_yellow}${PANEL_TARGET_LIB_DIR:-/usr/local/lib/hy2-luopo}${_plain}"
    print_line
    read -p " => Download and replace the local hy2 panel? (y/n): " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        msg "Update cancelled."
        sleep 1
        return 0
    fi

    local tmp_dir module base_url
    tmp_dir="$(mktemp -d /tmp/hy2-panel.XXXXXX)" || {
        err "Failed to create temporary directory."
        sleep 2
        return 1
    }
    mkdir -p "${tmp_dir}/lib/hy2" || {
        rm -rf "${tmp_dir}"
        err "Failed to create temporary module directory."
        sleep 2
        return 1
    }

    base_url="${PANEL_UPDATE_BASE_URL:-https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main}"
    msg "Downloading latest panel and modules..."
    if ! download_panel_file "${base_url}/hy2.sh" "${tmp_dir}/hy2.sh"; then
        rm -rf "${tmp_dir}"
        err "Failed to download launcher."
        sleep 2
        return 1
    fi
    for module in $(panel_module_list); do
        if ! download_panel_file "${base_url}/lib/hy2/${module}.sh" "${tmp_dir}/lib/hy2/${module}.sh"; then
            rm -rf "${tmp_dir}"
            err "Failed to download module: ${module}"
            sleep 2
            return 1
        fi
    done

    if ! verify_downloaded_panel_bundle "${tmp_dir}"; then
        rm -rf "${tmp_dir}"
        err "Downloaded bundle validation failed; local panel was not changed."
        sleep 2
        return 1
    fi

    if ! install_panel_bundle_from_dir "${tmp_dir}"; then
        rm -rf "${tmp_dir}"
        err "Failed to install panel files; check permissions."
        sleep 2
        return 1
    fi
    rm -rf "${tmp_dir}"

    ok "Panel launcher and modules have been updated. Run hy2 again to use the new version."
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

HY2_MODULE_CORE_LOADED=1
fi
