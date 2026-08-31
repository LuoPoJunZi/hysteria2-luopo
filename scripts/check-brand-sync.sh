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
    if ! grep -Fq -- "${pattern}" "${file}"; then
        fail "Brand marker missing from ${file}: ${pattern}"
    fi
}

legacy_repo='LuoPoJunZi/hysteria2'"-luopo"
legacy_brand='Hysteria2'"-LuoPo"

if git grep -n -F "${legacy_repo}" -- .; then
    fail "Legacy repository URL is still present"
fi

if git grep -n -F "${legacy_brand}" -- .; then
    fail "Legacy project name is still present"
fi

assert_contains "src/bootstrap.sh" "LuoPoJunZi/hy2ctl/main/hy2.sh"
assert_contains "src/panel/menu.sh" "hy2ctl 管理面板"
assert_contains "src/clients/cheatsheet.sh" "LuoPoJunZi/hy2ctl/main/install.sh"
assert_contains "install.sh" "LuoPoJunZi/hy2ctl/main"
assert_contains "README.md" "github.com/LuoPoJunZi/hy2ctl"

echo "[OK] Project brand and repository URLs are in sync."
