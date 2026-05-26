#!/bin/bash
set -euo pipefail

_red="\033[0;31m"
_green="\033[0;32m"
_yellow="\033[0;33m"
_plain="\033[0m"

GITHUB_RAW_URL="${GITHUB_RAW_URL:-https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main}"
TARGET_BIN="${TARGET_BIN:-/usr/local/bin/hy2}"
TARGET_LIB_DIR="${TARGET_LIB_DIR:-/usr/local/lib/hy2-luopo}"
PANEL_MODULES="common core config client diagnostics backup"

msg() { echo -e "${_yellow}[INFO]${_plain} $1"; }
ok() { echo -e "${_green}[OK]${_plain} $1"; }
err() { echo -e "${_red}[ERROR]${_plain} $1"; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        err "Please run this installer as root."
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "Missing command: ${cmd}"
        return 1
    fi
    return 0
}

detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get"
        return 0
    fi
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"
        return 0
    fi
    if command -v yum >/dev/null 2>&1; then
        echo "yum"
        return 0
    fi
    return 1
}

install_dependencies() {
    local pm="$1"
    msg "Checking base dependencies (curl, wget, openssl)..."
    case "${pm}" in
        apt-get)
            apt-get update -y >/dev/null 2>&1 || return 1
            apt-get install -y curl wget openssl >/dev/null 2>&1 || return 1
            ;;
        dnf|yum)
            "${pm}" install -y curl wget openssl >/dev/null 2>&1 || return 1
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

preflight_check() {
    local missing=0
    local cmd
    for cmd in grep head mktemp chmod mv cp mkdir rm dirname; do
        if ! require_cmd "${cmd}"; then
            missing=1
        fi
    done
    if [[ "${missing}" -ne 0 ]]; then
        err "Installer runtime dependencies are incomplete."
        exit 1
    fi
}

download_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 2 --connect-timeout 8 -o "${output}" "${url}" >/dev/null 2>&1 && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qO "${output}" "${url}" >/dev/null 2>&1 && return 0
    fi
    return 1
}

verify_downloaded_panel() {
    local bundle_dir="$1"
    local module
    local launcher="${bundle_dir}/hy2.sh"
    [[ -s "${launcher}" ]] || return 1
    head -n 1 "${launcher}" | grep -q '^#!/bin/bash' || return 1
    grep -q 'main_menu' "${launcher}" || return 1
    grep -q 'load_module' "${launcher}" || return 1
    for module in ${PANEL_MODULES}; do
        [[ -s "${bundle_dir}/lib/hy2/${module}.sh" ]] || return 1
        grep -q "HY2_MODULE_${module^^}_LOADED" "${bundle_dir}/lib/hy2/${module}.sh" || return 1
    done
    return 0
}

download_panel_bundle() {
    local bundle_dir="$1"
    local module
    mkdir -p "${bundle_dir}/lib/hy2" || return 1
    download_file "${GITHUB_RAW_URL}/hy2.sh" "${bundle_dir}/hy2.sh" || return 1
    for module in ${PANEL_MODULES}; do
        download_file "${GITHUB_RAW_URL}/lib/hy2/${module}.sh" "${bundle_dir}/lib/hy2/${module}.sh" || return 1
    done
    verify_downloaded_panel "${bundle_dir}"
}

install_panel_bundle() {
    local bundle_dir="$1"
    local target_bin_dir target_lib_parent new_lib old_lib tmp_bin module
    target_bin_dir="$(dirname "${TARGET_BIN}")"
    target_lib_parent="$(dirname "${TARGET_LIB_DIR}")"
    mkdir -p "${target_bin_dir}" "${target_lib_parent}" || return 1

    new_lib="$(mktemp -d "${TARGET_LIB_DIR}.new.XXXXXX")" || return 1
    for module in ${PANEL_MODULES}; do
        cp -f "${bundle_dir}/lib/hy2/${module}.sh" "${new_lib}/${module}.sh" || {
            rm -rf "${new_lib}"
            return 1
        }
    done
    chmod 755 "${new_lib}" >/dev/null 2>&1 || true
    chmod 644 "${new_lib}"/*.sh >/dev/null 2>&1 || true

    tmp_bin="$(mktemp "${target_bin_dir}/.hy2.XXXXXX")" || {
        rm -rf "${new_lib}"
        return 1
    }
    cp -f "${bundle_dir}/hy2.sh" "${tmp_bin}" || {
        rm -rf "${new_lib}" "${tmp_bin}"
        return 1
    }
    chmod +x "${tmp_bin}" || {
        rm -rf "${new_lib}" "${tmp_bin}"
        return 1
    }

    old_lib=""
    if [[ -d "${TARGET_LIB_DIR}" ]]; then
        old_lib="${TARGET_LIB_DIR}.bak.$$"
        mv "${TARGET_LIB_DIR}" "${old_lib}" || {
            rm -rf "${new_lib}" "${tmp_bin}"
            return 1
        }
    fi
    if ! mv "${new_lib}" "${TARGET_LIB_DIR}"; then
        [[ -n "${old_lib}" && -d "${old_lib}" ]] && mv "${old_lib}" "${TARGET_LIB_DIR}" >/dev/null 2>&1 || true
        rm -rf "${new_lib}" "${tmp_bin}"
        return 1
    fi
    if ! mv -f "${tmp_bin}" "${TARGET_BIN}"; then
        rm -f "${tmp_bin}"
        rm -rf "${TARGET_LIB_DIR}"
        [[ -n "${old_lib}" && -d "${old_lib}" ]] && mv "${old_lib}" "${TARGET_LIB_DIR}" >/dev/null 2>&1 || true
        return 1
    fi
    [[ -n "${old_lib}" ]] && rm -rf "${old_lib}"
    return 0
}

cleanup() {
    if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

echo -e "${_green}=====================================================${_plain}"
echo -e "       Hysteria2-LuoPo installer"
echo -e "${_green}=====================================================${_plain}"

require_root
preflight_check

PKG_MANAGER="$(detect_pkg_manager || true)"
if [[ -z "${PKG_MANAGER}" ]]; then
    err "No supported package manager detected (apt-get/dnf/yum)."
    exit 1
fi
if ! install_dependencies "${PKG_MANAGER}"; then
    err "Failed to install base dependencies. Check network or package sources."
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/hy2-install.XXXXXX)" || {
    err "Failed to create temporary directory."
    exit 1
}

msg "Downloading Hysteria2-LuoPo launcher and modules..."
if ! download_panel_bundle "${TMP_DIR}"; then
    err "Download or validation failed. Local installation was not changed."
    exit 1
fi

if ! install_panel_bundle "${TMP_DIR}"; then
    err "Failed to install panel files. Check permissions."
    exit 1
fi

ok "Panel installed."
echo -e "Command: ${_green}hy2${_plain}"
echo -e "Modules: ${_green}${TARGET_LIB_DIR}${_plain}"
sleep 2
"${TARGET_BIN}"
