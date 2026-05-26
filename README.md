# ⚡ Hysteria2-LuoPo 管理面板

<div align="center">

一个面向 VPS 的 Hysteria2 一键运维脚本。<br>
目标：**让新手 5 分钟部署成功**，也让开发者可以**低成本二次开发**。

[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Hysteria2](https://img.shields.io/badge/Core-Hysteria%20v2-blueviolet?style=flat-square)](https://v2.hysteria.network/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

</div>

---

## 1. 这是什么？适合谁用？

`hysteria2-luopo` 是一个纯 Bash 的终端管理面板，帮你把 Hysteria2 的常见操作做成菜单化流程：

- 安装/更新内核
- 生成配置（CA/自签）
- 导出客户端配置
- 诊断与日志排障
- 备份与恢复

适合人群：

- 新手：不熟悉 YAML 与 systemd，希望“能跑起来优先”
- 运维：希望快速重复部署，减少手工失误
- 开发者：需要在现有脚本基础上继续扩展功能

---

## 2. 项目能力总览

- 一键安装面板与 Hysteria2 内核
- 双证书模式：CA / 自签
- 自签 SNI 预设域名（含手动输入）
- 带宽参数可配（`up_mbps` / `down_mbps`）
- 客户端配置导出：
  - `hysteria2://` 分享链接
  - Sing-box Outbound JSON
  - v2rayN / NekoRay YAML 片段
  - 完整 Sing-box 模板
- 一键环境诊断（并导出日志）
- 最近诊断报告回看
- 手动备份与一键恢复
- 启动失败自动回滚（降低改坏配置风险）

---

## 3. 仓库结构（接手开发先看这里）

```text
.
├── hy2.sh                          # 轻量启动器（主菜单 + 按需加载模块）
├── install.sh                      # 安装入口脚本（远程拉取启动器与模块）
├── lib/
│   └── hy2/                        # 面板运行模块（common/core/config/client/diagnostics/backup）
├── scripts/
│   ├── verify.sh                   # 本地/CI 一键检查入口
│   ├── check-menu-sync.sh          # 菜单与 README 一致性检查
│   ├── check-version-sync.sh       # 版本号与 README 标识一致性检查
│   ├── smoke-e2e.sh                # 无特权端到端冒烟测试
│   └── measure-memory.sh           # Linux 下测量 hy2 主菜单 RSS
├── tests/
│   ├── e2e/
│   │   └── config-flow.sh          # 交互配置流程回放测试
│   └── unit/
│       └── hy2_core.bats           # 核心函数回归测试（bats）
└── .github/workflows/
    ├── lint.yml                    # Ubuntu + Debian 验证矩阵
    └── release.yml                 # 自动发布流程
```

---

## 4. 快速开始（新手照着做）

### 4.1 登录 VPS（root）

```bash
ssh root@你的服务器IP
```

### 4.2 一键安装

```bash
bash <(curl -fsSL hy2.evzzz.com)
```
备用
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main/install.sh)
```

### 4.3 打开面板

```bash
hy2
```

### 4.4 推荐最短流程

1. 菜单 `1`：安装/更新内核
2. 菜单 `2`：配置节点（新手建议先选自签）
3. 菜单 `3`：复制客户端配置
4. 菜单 `9`：执行一键诊断

---

## 5. 菜单说明（逐项解释）

```text
=====================================================
  Hysteria2-LuoPo 管理面板 V1.4 |  快捷启动: hy2
=====================================================
  内核版本: v2.8.1    服务状态: 运行中
-----------------------------------------------------
  节点核心管理
    (1)  一键安装/更新 Hysteria2 内核
    (2)  配置 Hysteria2 节点 (CA / 自签)
    (3)  查看客户端配置与分享链接

  服务运行控制
    (4)  启动 / 停止 / 重启 / 状态
    (5)  查看实时运行日志
    (6)  完全卸载清理
    (7)  查看常用指令速查
    (8)  查看 Sing-box 完整模板
    (9)  一键环境诊断
    (10) 查看最近诊断报告
    (11) 配置备份与恢复
    (12) 更新管理面板脚本
    (0)  退出面板
=====================================================
➡️ 请选择操作 [0-12]:
```

- `1`：安装或更新 Hysteria2 二进制与 systemd 服务
- `2`：生成并写入 `/etc/hysteria/config.yaml`，自动重启服务
- `3`：展示连接参数与客户端片段
- `4`：服务启停和状态查看
- `5`：跟踪服务日志（实时）
- `6`：卸载清理（高风险操作）
- `7`：排障常用命令速查
- `8`：完整 Sing-box 模板输出
- `9`：环境健康检查 + 报告导出
- `10`：查看最近一次诊断报告
- `11`：手动备份/恢复配置
- `12`：更新 `/usr/local/bin/hy2` 管理面板脚本

---

## 6. CA 与自签怎么选？

### CA 模式（选项 1）

适合：有域名、希望证书链标准化。  
要求：域名已解析到 VPS，80/443 网络环境允许证书申请流程。

### 自签模式（选项 2）

适合：没有域名，想快速用 IP 连通。  
要求：客户端必须开启 `insecure=true`。

自签模式支持 SNI 预设：

- `bing.com`
- `www.cloudflare.com`
- `www.apple.com`
- `www.microsoft.com`
- `www.amazon.com`
- 或手动输入

---

## 7. 客户端接入指南

### 7.1 Windows（v2rayN / NekoRay）

- 在面板菜单 `3` 复制 `hysteria2://` 链接导入
- 或复制 YAML 片段做手动配置

### 7.2 Android / iOS（Sing-box）

- 菜单 `3` 复制 Outbound 片段
- 菜单 `8` 复制完整模板（适合新建配置）

### 7.3 自签模式注意

必须确保客户端配置中：

- `insecure: true`

---

## 8. 常见问题与排障

### 8.1 服务起不来

先做：

1. 菜单 `9` 一键诊断
2. 菜单 `10` 查看最近诊断报告
3. 菜单 `5` 查看实时日志

菜单 `9` 会在结果末尾给出结构化排障建议：`结论 + 建议 + 命令`，可直接按命令执行。

### 8.2 常见错误：`config.yaml: permission denied`

脚本已做动态权限修复（按 systemd 实际运行用户设置目录与文件权限）。  
如果仍有异常，可手动检查：

```bash
systemctl show -p User,Group hysteria-server.service
namei -l /etc/hysteria/config.yaml
```

### 8.3 配置改坏了怎么办

- 菜单 `11` -> 恢复最近手动备份
- 或重新走菜单 `2` 生成新配置

---

## 9. 诊断与报告文件

诊断菜单会导出：

- `/tmp/hy2-diagnose-YYYYMMDD-HHMMSS.log`
- `/tmp/hy2-diagnose-latest.log`（最近一次快捷路径）

建议提 Issue 时附上：

- 诊断报告
- 最近 20 行 `journalctl` 日志
- 你选择的证书模式（CA/自签）

---

## 10. 二次开发接手指南（重点）

### 10.1 开发前准备

```bash
git clone https://github.com/LuoPoJunZi/hysteria2-luopo.git
cd hysteria2-luopo
```

### 10.2 本地检查（每次改动后执行）

```bash
chmod +x scripts/verify.sh
./scripts/verify.sh
```

`verify.sh` 会执行：

- `bash -n` 语法检查
- `shellcheck` 静态检查（error 级）
- 菜单与 README 预览一致性检查
- 版本号与 README 标识一致性检查
- 无特权端到端冒烟测试（配置生成/元数据解析/SNI 选择/分享片段/重启失败回滚）
- `bats` 核心函数回归测试（`tests/unit`）
- 交互配置流程回放测试（`tests/e2e/config-flow.sh`）

### 10.3 新增菜单功能的标准步骤

1. 在 `lib/hy2/` 对应模块中新增功能函数（例如 `show_xxx`）
2. 在 `hy2.sh` 的 `main_menu` 文案里增加菜单项
3. 在 `case` 分支里接入调用
4. 同步更新 `README.md` 菜单预览
5. 运行 `./scripts/verify.sh`

### 10.4 推荐编码约定

- 新功能优先封装到对应模块，避免把逻辑直接写进 `main_menu`
- 大段模板、诊断和配置流程保持按需加载，避免增加主菜单常驻内存
- 对外部命令（`systemctl/curl/openssl`）尽量做返回码判断
- 配置写入后统一做权限收敛
- 影响服务可用性的改动，优先考虑回滚路径
- Shell、Bats、YAML 和 Markdown 文件通过 `.gitattributes` 固定 LF 换行，避免 Windows 编辑后影响 Linux 执行

### 10.5 发布流程说明

- 版本来源：`hy2.sh` 中 `sh_ver`
- push 到 `main` 后触发：
  - `Lint`（质量检查）
  - `Auto Release`（自动打包发布）

---

## 11. 贡献建议

欢迎 PR 方向：

- 更多客户端配置模板
- 更细粒度诊断项
- 多语言文案
- 更完善的单元化脚本测试

---

## 12. 致谢与来源

本项目实践内容参考了作者博客教程：

- https://blog.luopojunzi.com/p/hysteria/

---

## 13. 开源协议

本项目基于 [MIT License](LICENSE) 协议开源。
