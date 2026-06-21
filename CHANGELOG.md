# Changelog

## v1.4.6 - 2026-06-21

- 根据 v2rayN 7.22.7 的 allowInsecure 变更提醒，增加自签模式导出时的 v2rayN / Xray 风险提示。
- README 补充 v2rayN 自签模式建议：长期优先使用 CA 域名证书，自签模式优先使用 Sing-box 完整模板。
- 补充回归测试，确保 v2rayN 自签风险提示持续输出。

## v1.4.5 - 2026-06-10

- 修复 Sing-box Android 启动时报 `dns/udp[local]: detour to an empty direct outbound makes no sense` 的问题。
- 移除完整模板中本地 DNS server 的 `detour: direct` 写法。
- 远程 DNS 和远程规则集下载改为走 `proxy`，并设置 `route.default_domain_resolver`，降低安卓端 DNS 解析失败风险。
- 补充回归测试，防止完整模板再次把本地 DNS detour 到 direct outbound。

## v1.4.4 - 2026-06-06

- 更新菜单 `(8)` Sing-box 完整模板，兼容 sing-box 1.12+ / 1.14+ 新配置格式。
- 移除完整模板中的旧 `geosite`、`geoip`、`inet4_address` 和 DNS outbound 写法，改用 `rule_set` 与 route action。
- 补充回归测试，防止完整模板重新出现已移除的旧字段。

## v1.4.3 - 2026-06-05

- 重新发布恢复后的单文件主线，避免用户继续下载到已撤销 PR #2 的发布产物。
- 面板自更新增加旧脚本备份、下载版本校验和写入失败恢复。
- 发布流程增加产物校验，阻止本地记忆文件、临时检查目录和已撤销模块化文件进入 Release 包。

## v1.4.2 - 2026-05-28

- 主菜单新增 `(12) 更新管理面板脚本`，可直接更新 `/usr/local/bin/hy2`。
- 常用指令速查补充面板脚本更新命令，避免和 Hysteria2 内核更新混淆。
- 同步 README 菜单预览和菜单一致性检查到 `[0-12]`。

## v1.4.1 - 2026-05-24

- 发布页标题改为纯版本号，不再在版本号前追加 `Hysteria2-LuoPo`。
- 发布说明改为从当前版本的 `CHANGELOG.md` 小节生成，只展示“主要变化”。
- 发布前验证保持分阶段执行，便于快速定位 Actions 失败环节。
- 修复菜单同步检查中横线分隔符被 `grep` 误解析为选项的问题。

## v1.4.0 - 2026-04-20

- Added `bats` unit tests under `tests/unit` for core helper behavior.
- Extended `scripts/verify.sh` to run `bats tests/unit`.
- Upgraded CI lint workflow to verify on both Ubuntu and Debian container environments.
- Synced release verification dependencies with new bats-based test suite.
- Added interactive config flow replay test (`tests/e2e/config-flow.sh`) and wired it into `verify`.
- Enhanced diagnostics output with severity summary (`FAIL/WARN/建议项`) for faster triage.
- Moved release verification before release-skipping logic so Auto Release reflects script health even when no new tag is published.
- Included self-signed certificate files in automatic rollback backups.
- Hardened manual restore to stop on missing or failed critical config restoration.
- Added `.gitattributes` to keep scripts and workflows on LF line endings.

## v1.3.0 - 2026-04-05

- Added non-privileged smoke E2E checks and wired them into `verify`, lint, and release workflows.
- Added a library-only entry mode (`HY2_LIB_ONLY=1`) to make `hy2.sh` testable without entering the interactive menu.
- Hardened config/meta writes with atomic file replacement and explicit write-failure handling.
- Improved startup failure diagnosis with categorized hints (permission denied, port in use, ACME failure, parse error).
- Upgraded one-click diagnostics output to structured `结论 + 建议 + 命令` format with de-duplication.

## v1.2.1 - 2026-04-04

- Fixed Linux permission issue where `hysteria-server` could not read `/etc/hysteria/config.yaml`.
- Applied dynamic permission strategy based on real systemd service user.
- Added safer rollback behavior and better startup failure diagnostics.
- Synced menu consistency checks with the latest plain-text menu labels.

## v1.2.0 - 2026-04-04

- Added one-click environment diagnostics and report export/review.
- Added manual backup and restore menu.
- Added full Sing-box profile template output.
- Added self-signed SNI preset domain options.
- Standardized script structure, installer checks, and release quality gates.
