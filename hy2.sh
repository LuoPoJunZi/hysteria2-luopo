#!/bin/bash
# ==========================================
# 项目: Hysteria2-LuoPo 核心管理面板
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
        # 调用官方卸载脚本的变体或手动删除
        rm -rf /usr/local/bin/hysteria
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

# --- 3. 主菜单系统 ---
main_menu() {
    while true; do
        clear
        print_line
        echo -e "        ${_green}Hysteria2-LuoPo 管理面板 V1.0${_plain}"
        print_line
        
        # 状态检测
        local status="${_red}○ 未运行${_plain}"
        local core_version="未安装"
        if command -v hysteria &> /dev/null; then
            core_version=$(hysteria version | awk '{print $3}')
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
            2) echo "配置节点功能开发中..."; sleep 2 ;; # 下一步我们将填充这里
            3) echo "查看订阅功能开发中..."; sleep 2 ;; # 下一步我们将填充这里
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