# shellcheck shell=bash
# 职责: Hysteria2 服务管理与文件路径速查展示

show_cheatsheet() {
    clear
    print_line
    echo -e "               ${_green}--- 常用指令速查 ---${_plain}"
    print_line
    echo -e "${_green}[服务器管理]${_plain}"
    echo -e "bash <(curl -fsSL https://raw.githubusercontent.com/LuoPoJunZi/hy2ctl/main/install.sh)"
    echo -e "bash <(curl -fsSL https://get.hy2.sh/)"
    echo -e "systemctl start ${HY2_SERVICE}"
    echo -e "systemctl restart ${HY2_SERVICE}"
    echo -e "systemctl status ${HY2_SERVICE} --no-pager -l"
    echo -e "systemctl stop ${HY2_SERVICE}"
    echo -e "systemctl enable ${HY2_SERVICE}"
    echo -e "journalctl -u ${HY2_SERVICE} --no-pager -n 100 -f"
    print_line
    echo -e "${_green}[自签证书生成]${_plain}"
    echo -e "openssl req -x509 -nodes -newkey ec \\"
    echo -e "  -pkeyopt ec_paramgen_curve:prime256v1 \\"
    echo -e "  -keyout ${HY2_CONF_DIR}/server.key -out ${HY2_CONF_DIR}/server.crt \\"
    echo -e "  -subj \"/CN=bing.com\" -days 36500 \\"
    echo -e "  -addext \"subjectAltName=DNS:bing.com\" \\"
    echo -e "  -addext \"basicConstraints=critical,CA:FALSE\" \\"
    echo -e "  -addext \"extendedKeyUsage=serverAuth\""
    print_line
    echo -e "${_green}[配置文件路径]${_plain}"
    echo -e "服务配置: ${HY2_CONF_FILE}"
    echo -e "元数据  : ${HY2_META_FILE}"
    print_line
    wait_return
}
