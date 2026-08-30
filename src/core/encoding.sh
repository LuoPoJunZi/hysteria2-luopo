# shellcheck shell=bash
# 职责: YAML、URL、JSON 与主机地址编码

yaml_single_quote() {
    local raw="$1"
    local escaped="${raw//\'/\'\'}"
    printf "'%s'" "${escaped}"
}

url_encode() {
    local raw="$1"
    local LC_ALL=C
    local length="${#raw}"
    local i char out=""
    for (( i = 0; i < length; i++ )); do
        char="${raw:i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_-]) out+="${char}" ;;
            *) printf -v out '%s%%%02X' "${out}" "'${char}" ;;
        esac
    done
    printf '%s' "${out}"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "${s}"
}

format_host_for_url() {
    local host="$1"
    if [[ "${host}" == *:* ]]; then
        printf '[%s]' "${host}"
        return
    fi
    printf '%s' "${host}"
}
