# shellcheck shell=bash
# 职责: 客户端导出前安全校验与多格式配置输出

ensure_client_export_material() {
    local cert_sha="$1"
    local cert_public_key_sha="$2"

    if [[ "${insecure}" == "true" && ( -z "${cert_sha}" || -z "${cert_public_key_sha}" ) ]]; then
        err "自签证书校验值读取失败，无法安全生成客户端配置。"
        echo -e "  请通过主菜单 (2) 重新配置自签证书后再导出。"
        wait_return
        return 1
    fi
}

print_client_exports() {
    local cert_sha="$1"
    local cert_public_key_sha="$2"
    local hy2_url json_ip json_password json_sni

    if ! hy2_url="$(render_hysteria2_share_url "${ip}" "${port}" "${password}" "${sni}" "${insecure}" "${cert_sha}")"; then
        err "生成 Hysteria2 分享链接失败，请重新配置节点。"
        wait_return
        return 1
    fi

    json_ip="$(json_escape "${ip}")"
    json_password="$(json_escape "${password}")"
    json_sni="$(json_escape "${sni}")"
    echo -e "${_green}[Link] 一键导入链接 (推荐 V2rayN / NekoBox / Clash):${_plain}"
    echo -e "${hy2_url}"
    print_line

    echo -e "${_green}[JSON] Sing-box 1.13+ (Android/iOS) 专属 Outbound 模块:${_plain}"
    if ! render_singbox_outbound_snippet "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}" "${cert_public_key_sha}"; then
        err "生成 Sing-box Outbound 失败，请重新配置节点。"
        wait_return
        return 1
    fi
    print_line
    echo -e "${_green}[YAML] v2rayN / nekoray 自定义配置片段:${_plain}"
    render_v2rayn_yaml_snippet "${ip}" "${port}" "${password}" "${up_mbps}" "${down_mbps}" "${sni}" "${insecure}" "${cert_sha}"
}
