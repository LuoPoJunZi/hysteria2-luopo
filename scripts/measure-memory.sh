#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_UNDER_TEST="${1:-${ROOT_DIR}/hy2.sh}"
BASELINE_SCRIPT="${2:-}"
RUN_SECONDS="${RUN_SECONDS:-3}"

fail() {
    echo "[ERROR] $1"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

measure_max_rss_kb() {
    local script="$1"
    local lib_dir="$2"
    local output rss
    output="$(
        {
            HY2_LIB_ONLY=1 HY2_LIB_DIR="${lib_dir}" /usr/bin/time -v timeout "${RUN_SECONDS}" \
                bash -c '
                    clear() { :; }
                    systemctl() { return 1; }
                    journalctl() { :; }
                    # shellcheck source=/dev/null
                    source "$1"
                    main_menu
                ' bash "${script}" < <(tail -f /dev/null)
        } 2>&1 || true
    )"
    rss="$(printf '%s\n' "${output}" | awk -F: '/Maximum resident set size/ { gsub(/^[ \t]+/, "", $2); print $2; exit }')"
    [[ -n "${rss}" ]] || {
        printf '%s\n' "${output}" >&2
        fail "Could not parse maximum RSS for ${script}"
    }
    printf '%s' "${rss}"
}

require_cmd bash
require_cmd timeout
require_cmd tail
require_cmd awk
[[ -x /usr/bin/time ]] || fail "Missing command: /usr/bin/time"
[[ -f "${SCRIPT_UNDER_TEST}" ]] || fail "Script not found: ${SCRIPT_UNDER_TEST}"

current_rss="$(measure_max_rss_kb "${SCRIPT_UNDER_TEST}" "${ROOT_DIR}/lib/hy2")"
echo "current_script=${SCRIPT_UNDER_TEST}"
echo "current_max_rss_kb=${current_rss}"

if [[ -n "${BASELINE_SCRIPT}" ]]; then
    [[ -f "${BASELINE_SCRIPT}" ]] || fail "Baseline script not found: ${BASELINE_SCRIPT}"
    baseline_rss="$(measure_max_rss_kb "${BASELINE_SCRIPT}" "${ROOT_DIR}/lib/hy2")"
    echo "baseline_script=${BASELINE_SCRIPT}"
    echo "baseline_max_rss_kb=${baseline_rss}"
    if (( current_rss < baseline_rss )); then
        echo "result=lower"
    else
        echo "result=not-lower"
    fi
fi
