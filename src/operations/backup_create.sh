# shellcheck shell=bash
# 职责: 创建 Hysteria2 手动配置备份

create_manual_backup() {
    local ts backup_dir

    if [[ ! -f "${HY2_CONF_FILE}" ]]; then
        err "当前没有可备份的 config.yaml，请先完成节点配置。"
        return 1
    fi

    if ! mkdir -p "${HY2_BACKUP_DIR}"; then
        err "创建备份根目录失败: ${HY2_BACKUP_DIR}"
        return 1
    fi

    ts="$(date '+%Y%m%d-%H%M%S')"
    if ! backup_dir="$(mktemp -d "${HY2_BACKUP_DIR}/manual-${ts}.XXXXXX")"; then
        err "创建备份目录失败: ${backup_dir}"
        return 1
    fi

    if ! cp -p -- "${HY2_CONF_FILE}" "${backup_dir}/config.yaml"; then
        rm -rf -- "${backup_dir}"
        err "备份 config.yaml 失败。"
        return 1
    fi
    if [[ -f "${HY2_META_FILE}" ]] && ! cp -p -- "${HY2_META_FILE}" "${backup_dir}/meta.info"; then
        rm -rf -- "${backup_dir}"
        err "备份 meta.info 失败。"
        return 1
    fi

    if grep -q '^tls:' "${HY2_CONF_FILE}"; then
        if [[ ! -f "${HY2_CONF_DIR}/server.crt" || ! -f "${HY2_CONF_DIR}/server.key" ]]; then
            rm -rf -- "${backup_dir}"
            err "当前为自签模式，但证书或私钥缺失，已取消备份。"
            return 1
        fi
        if ! cp -p -- "${HY2_CONF_DIR}/server.crt" "${backup_dir}/server.crt" || \
            ! cp -p -- "${HY2_CONF_DIR}/server.key" "${backup_dir}/server.key"; then
            rm -rf -- "${backup_dir}"
            err "备份自签证书文件失败。"
            return 1
        fi
    fi

    ok "手动备份完成: ${backup_dir}"
    return 0
}
