# shellcheck shell=bash
# 职责: 终端消息与基础界面输出

msg() { echo -e "${_blue}[信息]${_plain} $1"; }

ok() { echo -e "${_green}[成功]${_plain} $1"; }

err() { echo -e "${_red}[错误]${_plain} $1"; }

print_line() { echo -e "${_blue}=====================================================${_plain}"; }

print_sub_line() { echo -e "${_blue}-----------------------------------------------------${_plain}"; }

wait_return() { read -n 1 -s -r -p "按任意键返回主菜单..."; }
