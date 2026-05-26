# shellcheck shell=bash
if [[ "${HY2_MODULE_BACKUP_LOADED:-0}" != "1" ]]; then
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

HY2_MODULE_BACKUP_LOADED=1
fi
