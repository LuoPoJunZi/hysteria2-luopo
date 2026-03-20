# ⚡ Hysteria2-LuoPo 管理面板

<div align="center">

专为恶劣网络环境打造的极简 Hysteria2 自动化运维脚本。<br>
告别繁琐的 YAML 缩进，告别玄学的连通性问题，实现真正的**“一键导入，秒开 4K”**。

[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Hysteria2](https://img.shields.io/badge/Core-Hysteria%20v2-blueviolet?style=flat-square)](https://v2.hysteria.network/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

</div>

---

## 📖 项目简介

Hysteria2 是一款基于修改版 QUIC 协议的代理工具，以其**暴力发包**和**无视晚高峰丢包**的特性，被誉为拯救“垃圾线路”的最强杀器。

本项目 (`hysteria2-luopo`) 旨在为 Hysteria2 提供一个极简、直观、高内聚的 Linux 终端管理面板。无论你是想用真实的域名 CA 证书，还是想直接 IP 裸连（自签证书），只需敲击几次键盘，脚本就能为你全自动配置好一切，并输出标准化的分享链接。

## ✨ 核心特性

- **🚀 极简部署**：一键拉取核心面板，自动安装最新版 Hysteria2 内核。
- **🛡️ 双模式证书**：
  - **CA 模式**：全自动 ACME 申请真实域名证书，伪装更彻底。
  - **自签模式**：无需域名，自动生成高强度自签名证书，直接 IP 暴力连通。
- **📦 标准化订阅**：告别客户端配置错误，脚本直接输出标准的 `hysteria2://` 分享链接。
- **📱 移动端友好**：原生输出完美的 `Sing-box` (Android/iOS) Outbound JSON 配置片段，复制即用。
- **⚙️ 全局掌控**：支持一键启动/停止/重启服务、实时查看运行日志、完全卸载。

## 🛠️ 安装指南

支持主流的 Linux 发行版 (Debian / Ubuntu / CentOS)。请使用 `root` 用户登录您的 VPS，然后执行以下命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LuoPoJunZi/hysteria2-luopo/main/install.sh)
```

> **注意**：安装成功后，随时在终端输入 `hy2` 即可唤出管理面板。

## 🖥️ 面板预览

```text
=====================================================
        Hysteria2-LuoPo 管理面板 V1.0
=====================================================
  [状态] Core: v2.2.4 | 服务: ● 运行中
=====================================================
  ◈ 节点与核心管理
    (1) 🚀 一键安装/更新 Hysteria2 内核
    (2) ⚙️ 配置 Hysteria2 节点 (CA / 自签)
    (3) 📦 查看客户端配置与分享链接

  ◈ 服务控制
    (4) ▶️ 启动 / ⏹️ 停止 / 🔄 重启 服务
    (5) 📜 查看实时运行日志
    (6) 🗑️ 完全卸载
    (0) 退出面板
=====================================================
➡️ 请选择操作 [0-6]: 
```

## 📱 客户端连接必读

1. **Windows / PC 端**：推荐使用 **[v2rayN](https://github.com/2dust/v2rayN)** 或 **[NekoBoxForPc](https://github.com/MatsuriDayo/nekoray)**。在面板中输入 `3` 获取链接后，直接从剪贴板导入。
2. **Android / iOS 端**：推荐使用 **[Sing-box](https://github.com/SagerNet/sing-box)**。复制面板生成的 JSON 片段，替换掉你配置文件中的 `outbounds` 代理节点即可。
3. **⚠️ 自签证书注意**：如果您在配置时选择了“(2) 自签证书”，请确保在客户端的节点设置中，将 **“允许不安全 (insecure / 跳过证书验证)”** 选项设置为 `true`，否则将无法连接！

## 🤝 贡献与支持

如果你觉得这个项目拯救了你的网络，欢迎点击右上角的 **⭐ Star** 支持一下！
如果你发现了 Bug 或有更好的优化建议，欢迎提交 Issues 或 Pull Requests。

## 📜 开源协议

本项目基于 [MIT License](LICENSE) 协议开源。

