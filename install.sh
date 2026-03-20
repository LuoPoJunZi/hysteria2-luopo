#!/bin/bash
# ==========================================
# 项目: Hysteria2-LuoPo 安装与更新引导脚本
# 描述: 下载并部署管理面板到系统级命令
# ==========================================

_red="\033[0;31m"
_green="\033[0;32m"
_yellow="\033[0;33m"
_plain="\033[0m"

# 你的 GitHub 仓库 Raw 地址前缀 (开发时可以先写死，后期改为 master/main 分支)
# 格式类似: https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main
GITHUB_RAW_URL="https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main"

echo -e "${_green}=====================================================${_plain}"
echo -e "       欢迎使用 Hysteria2-LuoPo 一键部署脚本"
echo -e "${_green}=====================================================${_plain}"

# 1. 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${_red}[错误] 请使用 root 用户运行此脚本！${_plain}"
    exit 1
fi

# 2. 安装基础依赖
echo -e "${_yellow}[信息] 正在检查基础依赖 (curl, wget, openssl)...${_plain}"
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget openssl >/dev/null 2>&1

# 3. 下载并覆盖核心面板脚本
echo -e "${_yellow}[信息] 正在拉取最新的 Hysteria2-LuoPo 管理面板...${_plain}"
curl -s -L -o /usr/local/bin/hy2 "${GITHUB_RAW_URL}/hy2.sh"

if [[ -f "/usr/local/bin/hy2" ]]; then
    chmod +x /usr/local/bin/hy2
    echo -e "${_green}[成功] 面板安装完成！${_plain}"
    echo -e "-----------------------------------------------------"
    echo -e "👉 以后只需在终端输入 ${_green}hy2${_plain} 即可唤出管理面板！"
    echo -e "-----------------------------------------------------"
    sleep 2
    # 首次自动运行面板
    hy2
else
    echo -e "${_red}[错误] 下载面板失败，请检查网络或 GitHub Raw 链接是否正确。${_plain}"
    exit 1
fi