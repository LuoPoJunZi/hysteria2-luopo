# shellcheck shell=bash
if [[ "${HY2_MODULE_DIAGNOSTICS_LOADED:-0}" != "1" ]]; then
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

HY2_MODULE_DIAGNOSTICS_LOADED=1
fi
