# shellcheck shell=bash
# 职责: 管理面板启动入口

# 入口运行
if [[ "${HY2_LIB_ONLY:-0}" != "1" ]]; then
    require_root
    preflight_check
    case "${1:-}" in
        --install-core) install_hy2_core ;;
        "") main_menu ;;
        *)
            err "未知参数: $1"
            exit 1
            ;;
    esac
fi
