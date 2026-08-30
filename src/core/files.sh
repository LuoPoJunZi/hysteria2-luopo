# shellcheck shell=bash
# 职责: 原子写入与自动配置快照

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
    local name source_file backup_file absent_marker

    mkdir -p "${HY2_BACKUP_DIR}" || return 1

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        backup_file="${HY2_BACKUP_DIR}/${name}.bak"
        absent_marker="${backup_file}.absent"
        rm -f -- "${backup_file}" "${absent_marker}" || return 1
    done

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        source_file="${HY2_CONF_DIR}/${name}"
        backup_file="${HY2_BACKUP_DIR}/${name}.bak"
        absent_marker="${backup_file}.absent"
        if [[ -e "${source_file}" ]]; then
            cp -p -- "${source_file}" "${backup_file}" || return 1
        else
            : > "${absent_marker}" || return 1
        fi
    done
    return 0
}

restore_runtime_files() {
    local name target_file backup_file absent_marker
    local restore_failed=0

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        target_file="${HY2_CONF_DIR}/${name}"
        backup_file="${HY2_BACKUP_DIR}/${name}.bak"
        absent_marker="${backup_file}.absent"
        if [[ -f "${backup_file}" ]]; then
            cp -p -- "${backup_file}" "${target_file}" || restore_failed=1
        elif [[ -f "${absent_marker}" ]]; then
            rm -f -- "${target_file}" || restore_failed=1
        else
            restore_failed=1
        fi
    done

    if [[ "${restore_failed}" -ne 0 ]]; then
        return 1
    fi

    set_config_dir_permissions
    if [[ -f "${HY2_CONF_FILE}" ]]; then
        set_server_config_permissions
    fi
    if [[ -f "${HY2_META_FILE}" ]]; then
        chmod 600 "${HY2_META_FILE}" >/dev/null 2>&1 || true
    fi
    if [[ -f "${HY2_CONF_DIR}/server.key" && -f "${HY2_CONF_DIR}/server.crt" ]]; then
        set_tls_file_permissions
    fi
    return 0
}
