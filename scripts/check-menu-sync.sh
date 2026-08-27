#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

fail() {
    echo "[ERROR] $1"
    exit 1
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if ! grep -Fq -- "${pattern}" "${file}"; then
        fail "${label} (missing: ${pattern})"
    fi
}

assert_contains "hy2.sh" "=> 请选择操作 [0-12]:" "hy2.sh menu range mismatch"
assert_contains "hy2.sh" "快捷启动: hy2" "hy2.sh quick launch label mismatch"
assert_contains "hy2.sh" "内核版本:" "hy2.sh status label mismatch"
assert_contains "hy2.sh" "print_sub_line" "hy2.sh status separator mismatch"
assert_contains "hy2.sh" "节点核心管理" "hy2.sh node section label mismatch"
assert_contains "hy2.sh" "服务运行控制" "hy2.sh service section label mismatch"
assert_contains "hy2.sh" "(7)  查看常用指令速查" "hy2.sh menu item 7 spacing mismatch"
assert_contains "hy2.sh" "(8)  查看 Sing-box 完整模板" "hy2.sh menu item 8 spacing mismatch"
assert_contains "hy2.sh" "(9)  一键环境诊断" "hy2.sh menu item 9 spacing mismatch"
assert_contains "hy2.sh" "(10) 查看最近诊断报告" "hy2.sh menu item 10 missing"
assert_contains "hy2.sh" "(11) 配置备份与恢复" "hy2.sh menu item 11 missing"
assert_contains "hy2.sh" "(12) 更新管理面板脚本" "hy2.sh menu item 12 missing"
assert_contains "hy2.sh" "(0)  退出面板" "hy2.sh menu item 0 spacing mismatch"

assert_contains "README.md" "➡️ 请选择操作 [0-12]:" "README menu range mismatch"
assert_contains "README.md" "快捷启动: hy2" "README quick launch label mismatch"
assert_contains "README.md" "内核版本: v2.12.2    服务状态: 运行中" "README status label mismatch"
assert_contains "README.md" "-----------------------------------------------------" "README status separator mismatch"
assert_contains "README.md" "节点核心管理" "README node section label mismatch"
assert_contains "README.md" "服务运行控制" "README service section label mismatch"
assert_contains "README.md" "(7)  查看常用指令速查" "README menu item 7 spacing mismatch"
assert_contains "README.md" "(8)  查看 Sing-box 完整模板" "README menu item 8 spacing mismatch"
assert_contains "README.md" "(9)  一键环境诊断" "README menu item 9 spacing mismatch"
assert_contains "README.md" "(10) 查看最近诊断报告" "README menu item 10 missing"
assert_contains "README.md" "(11) 配置备份与恢复" "README menu item 11 missing"
assert_contains "README.md" "(12) 更新管理面板脚本" "README menu item 12 missing"
assert_contains "README.md" "(0)  退出面板" "README menu item 0 spacing mismatch"

echo "[OK] Menu and README preview are in sync."
