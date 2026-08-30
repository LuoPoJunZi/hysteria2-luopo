# shellcheck shell=bash
# 职责: 证书生成与校验值计算

normalize_certificate_sha256() {
    local fingerprint="$1"
    fingerprint="${fingerprint#*=}"
    fingerprint="${fingerprint//:/}"
    fingerprint="${fingerprint//[[:space:]]/}"
    fingerprint="${fingerprint,,}"
    [[ "${fingerprint}" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "${fingerprint}"
}

get_certificate_sha256() {
    local cert_file="$1"
    local fingerprint
    [[ -f "${cert_file}" ]] || return 1
    fingerprint="$(openssl x509 -in "${cert_file}" -noout -fingerprint -sha256 2>/dev/null)" || return 1
    normalize_certificate_sha256 "${fingerprint}"
}

is_valid_certificate_public_key_sha256() {
    local fingerprint="$1"
    [[ "${fingerprint}" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

get_certificate_public_key_sha256() {
    local cert_file="$1"
    local fingerprint
    [[ -f "${cert_file}" ]] || return 1
    fingerprint="$(
        set -o pipefail
        openssl x509 -in "${cert_file}" -pubkey -noout 2>/dev/null |
            openssl pkey -pubin -outform der 2>/dev/null |
            openssl dgst -sha256 -binary 2>/dev/null |
            openssl enc -base64 -A 2>/dev/null
    )" || return 1
    is_valid_certificate_public_key_sha256 "${fingerprint}" || return 1
    printf '%s' "${fingerprint}"
}

generate_self_signed_certificate() {
    local sni="$1"
    local cert_file="${HY2_CONF_DIR}/server.crt"
    local key_file="${HY2_CONF_DIR}/server.key"

    if openssl req -x509 -nodes -newkey ec \
        -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "${key_file}" -out "${cert_file}" \
        -subj "/CN=${sni}" -days 36500 \
        -addext "subjectAltName=DNS:${sni}" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1; then
        return 0
    fi

    openssl req -x509 -nodes -newkey ec \
        -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "${key_file}" -out "${cert_file}" \
        -subj "/CN=${sni}" -days 36500 >/dev/null 2>&1
}
