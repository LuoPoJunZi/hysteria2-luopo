# shellcheck shell=bash
# 职责: 管理面板启动入口

# 入口运行
if [[ "${HY2_LIB_ONLY:-0}" != "1" ]]; then
    require_root
    preflight_check
    main_menu
fi
