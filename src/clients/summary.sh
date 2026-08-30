# shellcheck shell=bash
# 职责: 客户端节点参数与证书指纹摘要展示

print_client_summary() {
    local cert_sha="$1"
    local cert_public_key_sha="$2"

    clear
    print_line
    echo -e "               ${_green}--- Hysteria2 客户端配置 ---${_plain}"
    print_line
    echo -e "  [*] 服务器 IP : ${_yellow}${ip}${_plain}"
    echo -e "  [*] 端口      : ${_yellow}${port}${_plain}"
    echo -e "  [*] 密码      : ${_yellow}${password}${_plain}"
    echo -e "  [*] SNI伪装   : ${_yellow}${sni}${_plain}"
    echo -e "  [*] 跳过证书  : ${_yellow}${insecure}${_plain} (自签必须为true)"
    if [[ "${insecure}" == "true" ]]; then
        if [[ -n "${cert_sha}" ]]; then
            echo -e "  [*] 证书指纹  : ${_yellow}${cert_sha}${_plain}"
        else
            echo -e "  [!] 证书指纹  : ${_red}读取失败，已禁止导出客户端链接${_plain}"
        fi
        if [[ -n "${cert_public_key_sha}" ]]; then
            echo -e "  [*] 公钥指纹  : ${_yellow}${cert_public_key_sha}${_plain} (Sing-box)"
        else
            echo -e "  [!] 公钥指纹  : ${_red}读取失败，已禁止导出 Sing-box 配置${_plain}"
        fi
    fi
    echo -e "  [*] 上行带宽  : ${_yellow}${up_mbps}${_plain} Mbps"
    echo -e "  [*] 下行带宽  : ${_yellow}${down_mbps}${_plain} Mbps"
    print_line
}
