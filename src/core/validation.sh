# shellcheck shell=bash
# 职责: 用户输入格式校验

is_valid_port() {
    local p="$1"
    [[ "${p}" =~ ^[0-9]{1,5}$ ]] && (( 10#${p} >= 1 && 10#${p} <= 65535 ))
}

is_positive_integer() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]{1,9}$ ]] && (( 10#${value} >= 1 ))
}

is_valid_domain() {
    local d="$1"
    [[ "${d}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

is_valid_url() {
    local u="$1"
    [[ "${u}" =~ ^https?://[^[:space:]]+$ ]]
}

is_valid_email() {
    local e="$1"
    [[ "${e}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}
