#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

check_cmd() {
    local name="$1"
    if ! command -v "${name}" >/dev/null 2>&1; then
        echo "[ERROR] Missing command: ${name}"
        return 1
    fi
}

run_syntax_checks() {
    echo "[INFO] Running bash syntax checks..."
    check_cmd bash
    local file
    for file in hy2.sh install.sh lib/hy2/*.sh scripts/*.sh tests/e2e/*.sh; do
        bash -n "${file}"
    done
}

run_shellcheck() {
    echo "[INFO] Running shellcheck..."
    check_cmd shellcheck
    shellcheck -S error -x hy2.sh install.sh lib/hy2/*.sh scripts/*.sh tests/e2e/*.sh
}

run_menu_sync_check() {
    echo "[INFO] Checking menu/README consistency..."
    check_cmd bash
    check_cmd grep
    bash scripts/check-menu-sync.sh
}

run_version_sync_check() {
    echo "[INFO] Checking version marker consistency..."
    check_cmd bash
    check_cmd grep
    bash scripts/check-version-sync.sh
}

run_smoke_e2e_checks() {
    echo "[INFO] Running smoke E2E checks..."
    bash scripts/smoke-e2e.sh
}

run_bats_tests() {
    echo "[INFO] Running bats tests..."
    check_cmd bats
    bats tests/unit
}

run_config_flow_replay() {
    echo "[INFO] Running config flow replay tests..."
    bash tests/e2e/config-flow.sh
}

run_all() {
    run_syntax_checks
    run_shellcheck
    run_menu_sync_check
    run_version_sync_check
    run_smoke_e2e_checks
    run_bats_tests
    run_config_flow_replay
}

case "${1:-all}" in
    syntax) run_syntax_checks ;;
    shellcheck) run_shellcheck ;;
    menu-sync) run_menu_sync_check ;;
    version-sync) run_version_sync_check ;;
    smoke-e2e) run_smoke_e2e_checks ;;
    bats) run_bats_tests ;;
    config-flow) run_config_flow_replay ;;
    all) run_all ;;
    *)
        echo "[ERROR] Unknown verify target: $1"
        echo "Usage: $0 [syntax|shellcheck|menu-sync|version-sync|smoke-e2e|bats|config-flow|all]"
        exit 1
        ;;
esac

echo "[OK] All checks passed."
