# shellcheck shell=bash
if [[ "${HY2_MODULE_CLIENT_LOADED:-0}" != "1" ]]; then
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
    echo -e "          ${_green}--- Sing-box 完整模板 (Android/iOS) ---${_plain}"
    print_line
    echo -e "{
  \"dns\": {
    \"servers\": [
      {
        \"tag\": \"cf\",
        \"address\": \"https://1.1.1.1/dns-query\"
      },
      {
        \"tag\": \"local\",
        \"address\": \"223.5.5.5\",
        \"detour\": \"direct\"
      },
      {
        \"tag\": \"block\",
        \"address\": \"rcode://success\"
      }
    ],
    \"rules\": [
      {
        \"geosite\": \"category-ads-all\",
        \"server\": \"block\",
        \"disable_cache\": true
      },
      {
        \"outbound\": \"any\",
        \"server\": \"local\"
      },
      {
        \"geosite\": \"cn\",
        \"server\": \"local\"
      }
    ],
    \"strategy\": \"ipv4_only\"
  },
  \"inbounds\": [
    {
      \"type\": \"tun\",
      \"inet4_address\": \"172.19.0.1/30\",
      \"auto_route\": true,
      \"strict_route\": false,
      \"sniff\": true
    }
  ],
  \"outbounds\": [
    {
      \"type\": \"hysteria2\",
      \"tag\": \"proxy\",
      \"server\": \"${json_ip}\",
      \"server_port\": ${port},
      \"up_mbps\": ${up_mbps},
      \"down_mbps\": ${down_mbps},
      \"password\": \"${json_password}\",
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${json_sni}\",
        \"insecure\": ${insecure}
      }
    },
    {
      \"type\": \"direct\",
      \"tag\": \"direct\"
    },
    {
      \"type\": \"block\",
      \"tag\": \"block\"
    },
    {
      \"type\": \"dns\",
      \"tag\": \"dns-out\"
    }
  ],
  \"route\": {
    \"rules\": [
      {
        \"protocol\": \"dns\",
        \"outbound\": \"dns-out\"
      },
      {
        \"geosite\": \"cn\",
        \"geoip\": [
          \"private\",
          \"cn\"
        ],
        \"outbound\": \"direct\"
      },
      {
        \"geosite\": \"category-ads-all\",
        \"outbound\": \"block\"
      }
    ],
    \"auto_detect_interface\": true
  }
}"
    print_line
    wait_return
}

HY2_MODULE_CLIENT_LOADED=1
fi
