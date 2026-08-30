# shellcheck shell=bash
# 职责: Sing-box Hysteria2 出站与证书公钥固定字段

render_singbox_public_key_field() {
    local insecure="$1"
    local public_key_sha="${2:-}"
    local indent="$3"

    case "${insecure}" in
        true)
            is_valid_certificate_public_key_sha256 "${public_key_sha}" || return 1
            ;;
        false) ;;
        *) return 1 ;;
    esac
    if [[ -n "${public_key_sha}" ]]; then
        is_valid_certificate_public_key_sha256 "${public_key_sha}" || return 1
        printf ',\n%s"certificate_public_key_sha256": ["%s"]' "${indent}" "${public_key_sha}"
    fi
}

render_singbox_outbound_snippet() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"
    local public_key_sha="${8:-}"
    local public_key_field

    public_key_field="$(render_singbox_public_key_field "${insecure}" "${public_key_sha}" "    ")" || return 1

    cat << EOF
{
  "type": "hysteria2",
  "tag": "proxy",
  "server": "${json_ip}",
  "server_port": ${port},
  "up_mbps": ${up_mbps},
  "down_mbps": ${down_mbps},
  "password": "${json_password}",
  "tls": {
    "enabled": true,
    "server_name": "${json_sni}",
    "insecure": ${insecure}${public_key_field}
  }
}
EOF
}

render_singbox_outbounds_section() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"
    local public_key_field="$8"

    cat << EOF
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "${json_ip}",
      "server_port": ${port},
      "up_mbps": ${up_mbps},
      "down_mbps": ${down_mbps},
      "password": "${json_password}",
      "tls": {
        "enabled": true,
        "server_name": "${json_sni}",
        "insecure": ${insecure}${public_key_field}
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
EOF
}
