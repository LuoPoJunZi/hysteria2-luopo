#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

fail() {
    echo "[ERROR] $1"
    exit 1
}

version="$(grep -oE 'sh_ver="v[0-9]+\.[0-9]+\.[0-9]+"' src/bootstrap.sh | head -n 1 | sed -E 's/.*"(v[0-9]+\.[0-9]+\.[0-9]+)".*/\1/')"
if [[ -z "${version}" ]]; then
    fail "Cannot extract sh_ver from src/bootstrap.sh"
fi

generated_version="$(grep -oE 'sh_ver="v[0-9]+\.[0-9]+\.[0-9]+"' hy2.sh | head -n 1 | sed -E 's/.*"(v[0-9]+\.[0-9]+\.[0-9]+)".*/\1/')"
if [[ "${generated_version}" != "${version}" ]]; then
    fail "Generated hy2.sh version is out of sync (${generated_version:-missing} != ${version})"
fi

readme_marker="hy2ctl 管理面板 ${version}"

if ! grep -Fq "${readme_marker}" README.md; then
    fail "README preview version is out of sync. Expected marker: ${readme_marker}"
fi

if ! grep -Eq "^## ${version}( - [0-9]{4}-[0-9]{2}-[0-9]{2})?$" CHANGELOG.md; then
    fail "CHANGELOG is missing a section for ${version}"
fi

echo "[OK] Version markers are in sync (${version})."
