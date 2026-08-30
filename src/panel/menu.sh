# shellcheck shell=bash
# 职责: 主菜单渲染与操作分派

main_menu() {
    while true; do
        clear
        print_line
        echo -e "  ${_green}Hysteria2-LuoPo 管理面板 ${sh_ver} |  快捷启动: hy2${_plain}"
        print_line

        local status="${_red}未运行${_plain}"
        local core_version="未安装"
        if command -v hysteria &> /dev/null; then
            core_version="$(get_hy2_core_version 2>/dev/null || true)"
            [[ -z "$core_version" ]] && core_version="未知版本"

            if systemctl is-active --quiet "${HY2_SERVICE}"; then
                status="${_green}运行中${_plain}"
            fi
        fi

        echo -e "  内核版本: ${core_version}    服务状态: ${status}"
        print_sub_line
        echo -e "  节点核心管理"
        echo -e "    (1)  一键安装/更新 Hysteria2 内核"
        echo -e "    (2)  配置 Hysteria2 节点 (CA / 自签)"
        echo -e "    (3)  查看客户端配置与分享链接"
        echo -e ""
        echo -e "  服务运行控制"
        echo -e "    (4)  启动 / 停止 / 重启 / 状态"
        echo -e "    (5)  查看实时运行日志"
        echo -e "    (6)  完全卸载清理"
        echo -e "    (7)  查看常用指令速查"
        echo -e "    (8)  查看 Sing-box 完整模板"
        echo -e "    (9)  一键环境诊断"
        echo -e "    (10) 查看最近诊断报告"
        echo -e "    (11) 配置备份与恢复"
        echo -e "    (12) 更新管理面板脚本"
        echo -e "    (0)  退出面板"
        print_line

        read -r -p " => 请选择操作 [0-12]: " menu_num

        case "${menu_num}" in
            1) install_hy2_core; sleep 2 ;;
            2) config_hy2 ;;
            3) show_info ;;
            4)
                if ensure_hy2_core_installed; then
                    service_control_menu
                else
                    sleep 2
                fi
                ;;
            5)
                if ensure_hy2_core_installed; then
                    journalctl -u "${HY2_SERVICE}" --no-pager -n 100 -f
                else
                    sleep 2
                fi
                ;;
            6) uninstall_hy2 ;;
            7) show_cheatsheet ;;
            8) show_singbox_template ;;
            9) show_diagnostics ;;
            10) show_latest_diagnostics_report ;;
            11) show_backup_restore_menu ;;
            12) update_panel_script ;;
            0) exit 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}
