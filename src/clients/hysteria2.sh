# shellcheck shell=bash
# 职责: Hysteria2 分享链接

render_hysteria2_share_url() {
    local ip="$1"
    local port="$2"
    local password="$3"
    local sni="$4"
    local insecure="$5"
    local cert_sha="${6:-}"
    local query

    case "${insecure}" in
        true) ;;
        false) ;;
        *) return 1 ;;
    esac

    if [[ -n "${cert_sha}" ]]; then
        cert_sha="$(normalize_certificate_sha256 "${cert_sha}")" || return 1
    fi
    if [[ "${insecure}" == "true" && -z "${cert_sha}" ]]; then
        return 1
    fi

    query="sni=$(url_encode "${sni}")"
    if [[ "${insecure}" == "true" ]]; then
        query+="&insecure=1"
    fi
    if [[ -n "${cert_sha}" ]]; then
        query+="&pinSHA256=${cert_sha}&pcs=${cert_sha}"
    fi

    printf 'hysteria2://%s@%s:%s/?%s#Hysteria2-LuoPo' \
        "$(url_encode "${password}")" \
        "$(format_host_for_url "${ip}")" \
        "${port}" \
        "${query}"
}
