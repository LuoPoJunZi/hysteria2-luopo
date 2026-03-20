#!/bin/bash
# ==========================================
# 项目: Hysteria2-LuoPo 核心管理面板 V1.0
# 描述: 专为恶劣网络环境打造的极简 Hysteria2 运维脚本
# ==========================================

# --- 1. 全局变量与颜色输出 ---
_red="\033[0;31m"
_green="\033[0;32m"
_yellow="\033[0;33m"
_blue="\033[0;36m"
_plain="\033[0m"

HY2_CONF_DIR="/etc/hysteria"
HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
HY2_META_FILE="${HY2_CONF_DIR}/meta.info"

msg() { echo -e "${_blue}[信息]${_plain} $1"; }
ok() { echo -e "${_green}[成功]${_plain} $1"; }
err() { echo -e "${_red}[错误]${_plain} $1"; }
print_line() { echo -e "${_blue}=====================================================${_plain}"; }

# --- 2. 核心控制模块: 安装与卸载 ---
install_hy2_core() {
    if command -v hysteria &> /dev/null; then
        msg "Hysteria2 内核已安装，正在尝试更新..."
    else
        msg "正在调用官方脚本安装 Hysteria2 内核..."
    fi
    
    # 调用官方一键脚本
    bash <(curl -fsSL https://get.hy2.sh/)
    
    # 设置开机自启
    systemctl enable hysteria-server.service >/dev/null 2>&1
    ok "Hysteria2 内核部署/更新完成！"
}

uninstall_hy2() {
    print_line
    echo -e "${_red}警告: 这将彻底卸载 Hysteria2 及所有节点配置！${_plain}"
    read -p "确定要继续吗？(y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop hysteria-server.service >/dev/null 2>&1
        systemctl disable hysteria-server.service >/dev/null 2>&1
        
        # 清理文件
        rm -f /usr/local/bin/hysteria
        rm -rf /etc/hysteria
        rm -f /etc/systemd/system/hysteria-server.service
        systemctl daemon-reload
        ok "Hysteria2 已彻底卸载！"
        
        # 自我删除
        rm -f /usr/local/bin/hy2
        exit 0
    else
        msg "已取消卸载。"
    fi
}

# --- 3. 核心控制模块: 节点配置与生成 ---
config_hy2() {
    clear
    print_line
    echo -e "               ${_green}◈ Hysteria2 节点配置 ◈${_plain}"
    print_line
    
    # 基础参数收集
    read -p "➡️ 请设置监听端口 (默认 443): " port
    [[ -z "${port}" ]] && port=443
    
    local default_pwd=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
    read -p "➡️ 请设置认证密码 (默认随机: ${default_pwd}): " password
    [[ -z "${password}" ]] && password="${default_pwd}"

    read -p "➡️ 请设置伪装网址 (默认 https://bing.com): " masquerade_url
    [[ -z "${masquerade_url}" ]] && masquerade_url="https://bing.com"

    # 证书模式选择
    echo -e "\n请选择证书模式："
    echo -e "  (1) CA 域名证书 (推荐，需要提前将域名解析到本 VPS)"
    echo -e "  (2) 自签证书 (无需域名，直接使用 IP 连通)"
    read -p "➡️ 请选择 [1-2]: " cert_type

    mkdir -p ${HY2_CONF_DIR}

    if [[ "${cert_type}" == "1" ]]; then
        read -p "🌐 请输入已解析到本机的域名: " domain
        read -p "📧 请输入邮箱 (用于自动申请证书，随意填): " email
        [[ -z "${email}" ]] && email="admin@${domain}"
        
        # 写入 CA 模式配置 (严格遵循 YAML 缩进)
        cat << EOF > ${HY2_CONF_FILE}
listen: :${port}
acme:
  domains:
    - ${domain}
  email: ${email}
auth:
  type: password
  password: ${password}
masquerade:
  type: proxy
  proxy:
    url: ${masquerade_url}
    rewriteHost: true
EOF
        local sni="${domain}"
        local insecure="false"

    else
        msg "正在生成高强度自签名证书..."
        read -p "🌐 请输入用于伪装的 SNI 域名 (默认 bing.com): " sni
        [[ -z "${sni}" ]] && sni="bing.com"
        
        # 自动执行自签证书生成逻辑
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout ${HY2_CONF_DIR}/server.key -out ${HY2_CONF_DIR}/server.crt \
        -subj "/CN=${sni}" -days 36500 >/dev/null 2>&1
        
        chown hysteria ${HY2_CONF_DIR}/server.key ${HY2_CONF_DIR}/server.crt
        
        # 写入 TLS 自签模式配置
        cat << EOF > ${HY2_CONF_FILE}
listen: :${port}
tls:
  cert: ${HY2_CONF_DIR}/server.crt
  key: ${HY2_CONF_DIR}/server.key
auth:
  type: password
  password: ${password}
masquerade:
  type: proxy
  proxy:
    url: ${masquerade_url}
    rewriteHost: true
EOF
        local insecure="true"
    fi

    # 🚀 物理隔离：将客户端必须的参数写入元数据文件
    SERVER_IP=$(curl -s4 https://api.ipify.org || curl -s6 https://api64.ipify.org)
    echo -e "ip=${SERVER_IP}\nport=${port}\npassword=${password}\nsni=${sni}\ninsecure=${insecure}" > ${HY2_META_FILE}

    msg "正在重启 Hysteria2 服务以应用新配置..."
    systemctl restart hysteria-server.service
    sleep 2
    if systemctl is-active --quiet hysteria-server.service; then
        ok "Hysteria2 节点配置并启动成功！"
    else
        err "启动失败！可能是 443 端口被占用，或 CA 证书申请失败(域名未解析)。请使用菜单 (5) 查看日志。"
    fi
    sleep 2
}

# --- 4. 客户端订阅与展示模块 ---
show_info() {
    if [[ ! -f ${HY2_META_FILE} ]]; then
        err "未找到节点元数据，请先执行 (2) 配置 Hysteria2 节点！"
        sleep 2
        return
    fi
    
    # 直接读取绝对正确的硬编码数据，杜绝一切猜测！
    source ${HY2_META_FILE}

    clear
    print_line
    echo -e "               ${_green}◈ Hysteria2 客户端配置 ◈${_plain}"
    print_line
    echo -e "  🌐 服务器 IP : ${_yellow}${ip}${_plain}"
    echo -e "  🚪 端口      : ${_yellow}${port}${_plain}"
    echo -e "  🔑 密码      : ${_yellow}${password}${_plain}"
    echo -e "  🎭 SNI伪装   : ${_yellow}${sni}${_plain}"
    echo -e "  🔓 跳过证书  : ${_yellow}${insecure}${_plain} (自签必须为true)"
    print_line

    # 1. 生成极简标准 URL (通用分享链接)
    local hy2_url="hysteria2://${password}@${ip}:${port}/?sni=${sni}&insecure=${insecure}#Hysteria2-LuoPo"
    echo -e "${_green}📦 一键导入链接 (推荐 V2rayN / NekoBox / Clash):${_plain}"
    echo -e "${hy2_url}"
    print_line
    
    # 2. 生成 Sing-box 原生 JSON (手机端必备)
    echo -e "${_green}📱 Sing-box (Android/iOS) 专属 Outbound 模块:${_plain}"
    echo -e "{
  \"type\": \"hysteria2\",
  \"tag\": \"proxy\",
  \"server\": \"${ip}\",
  \"server_port\": ${port},
  \"up_mbps\": 50,
  \"down_mbps\": 200,
  \"password\": \"${password}\",
  \"tls\": {
    \"enabled\": true,
    \"server_name\": \"${sni}\",
    \"insecure\": ${insecure}
  }
}"
    print_line
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# --- 5. 主菜单系统 ---
main_menu() {
    while true; do
        clear
        print_line
        echo -e "        ${_green}Hysteria2-LuoPo 管理面板 V1.0${_plain}"
        print_line
        
        local core_version="未安装"
        if command -v hysteria &> /dev/null; then
            # 🚀 颜值修复：精准抓取 v2.x.x，无情过滤掉 Hysteria 官方的字符画和乱码
            core_version=$(hysteria version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
            [[ -z "$core_version" ]] && core_version="未知版本"
            
            if systemctl is-active --quiet hysteria-server.service; then
                status="${_green}● 运行中${_plain}"
            fi
        fi
        
        
        echo -e "  [状态] Core: ${core_version} | 服务: ${status}"
        print_line
        echo -e "  ◈ 节点与核心管理"
        echo -e "    (1) 🚀 一键安装/更新 Hysteria2 内核"
        echo -e "    (2) ⚙️ 配置 Hysteria2 节点 (CA / 自签)"
        echo -e "    (3) 📦 查看客户端配置与分享链接"
        echo -e ""
        echo -e "  ◈ 服务控制"
        echo -e "    (4) ▶️ 启动 / ⏹️ 停止 / 🔄 重启 服务"
        echo -e "    (5) 📜 查看实时运行日志"
        echo -e "    (6) 🗑️ 完全卸载"
        echo -e "    (0) 退出面板"
        print_line
        
        read -p "➡️ 请选择操作 [0-6]: " menu_num
        
        case "${menu_num}" in
            1) install_hy2_core; sleep 2 ;;
            2) config_hy2 ;;
            3) show_info ;;
            4) 
                systemctl restart hysteria-server.service
                ok "服务已重启！"; sleep 1 
                ;;
            5) journalctl -u hysteria-server.service -f ;;
            6) uninstall_hy2 ;;
            0) exit 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}

# 入口运行
main_menu