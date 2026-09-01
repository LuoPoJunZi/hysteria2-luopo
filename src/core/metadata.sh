# shellcheck shell=bash
# 职责: 节点元数据安全读写

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
    port="$((10#${port}))"
    if [[ "${insecure}" != "true" && "${insecure}" != "false" ]]; then
        return 1
    fi
    [[ -z "${up_mbps}" ]] && up_mbps="${DEFAULT_UP_MBPS}"
    [[ -z "${down_mbps}" ]] && down_mbps="${DEFAULT_DOWN_MBPS}"
    if ! is_positive_integer "${up_mbps}" || ! is_positive_integer "${down_mbps}"; then
        return 1
    fi
    up_mbps="$((10#${up_mbps}))"
    down_mbps="$((10#${down_mbps}))"
    return 0
}

require_meta_info() {
    if [[ ! -f "${HY2_META_FILE}" ]]; then
        err "未找到节点元数据，请先执行 (1) 配置 Hysteria2 节点！"
        sleep 2
        return 1
    fi
    if ! read_meta_info; then
        err "节点元数据损坏或缺失，请重新执行 (1) 配置节点。"
        sleep 2
        return 1
    fi
    return 0
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
