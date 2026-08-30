# shellcheck shell=bash
# 职责: Sing-box DNS 配置分段

render_singbox_dns_section() {
    cat << 'EOF'
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "cf",
        "server": "1.1.1.1",
        "detour": "proxy"
      },
      {
        "type": "udp",
        "tag": "local",
        "server": "223.5.5.5"
      }
    ],
    "rules": [
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      },
      {
        "rule_set": "geosite-cn",
        "action": "route",
        "server": "local"
      }
    ],
    "final": "cf",
    "strategy": "ipv4_only"
  },
EOF
}
