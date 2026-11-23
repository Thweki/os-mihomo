# 安装、升级与卸载 os-mihomo

[返回首页](../README.md) · [English](install.en.md)

## 安装前

- 以管理员身份打开 OPNsense，确认系统为 **26.7 系列，FreeBSD 15 amd64**。其他版本和架构需另行验证。
- 在 **系统 → 配置 → 备份** 导出配置。升级或迁移时，还要备份 Mihomo 的 YAML、订阅设置和自启设置。备份含凭据，请妥善保存。[OPNsense 配置备份](https://docs.opnsense.org/manual/backups.html) · [Mihomo 配置文件清单](usage.md#配置文件)
- 已装其他来源的 `os-mihomo` 时，先看[从其他来源迁移](#从其他来源迁移)。

按软件来源选择一种安装方式。

## 通过插件管理器安装

项目的 HTTPS 签名源只提供 `os-mihomo`，跟随 GitHub 最新正式 Release。首次安装或从离线源迁移时，由管理员核对公钥并添加仓库配置。保留原有 OPNsense 软件源。[添加项目签名源](ci-cd.md#use-the-project-feed)

1. 在 **系统 → 固件 → 状态** 检查更新，刷新软件包目录。
2. 打开 **系统 → 固件 → 插件**，需要时勾选 **显示社区插件**，搜索 `os-mihomo`。
3. 确认名称、版本和来源与预期一致，再点击安装。若存在同名来源，先确认要保留哪一个。

[OPNsense 插件管理文档](https://docs.opnsense.org/manual/firmware.html#plugins)

## 从 Release 安装单个包

1. 从[正式 Release](https://github.com/Thweki/os-mihomo/releases/latest) 下载 `os-mihomo.pkg` 和同一版本的 `SHA256SUMS`。一般安装只需这两个文件。CI Actions 产物用于隔离测试。
2. 如果该版本提供 GitHub 构建来源证明，在管理电脑上用 `gh attestation verify os-mihomo.pkg --repo Thweki/os-mihomo` 核对来源，确认对应所选发布标签。将这两个文件传到 OPNsense 上同一目录后，从控制台或 SSH 进入该目录校验包。校验失败就停止。[来源证明与校验说明](ci-cd.md#reproduce-and-verify)

   ```sh
   expected=$(awk '$2 == "os-mihomo.pkg" { print $1 }' SHA256SUMS)
   [ "${#expected}" -eq 64 ] && sha256 -c "$expected" os-mihomo.pkg
   ```

3. `curl` 和 `jq` 是包依赖。如有缺失，先从当前 OPNsense 官方软件源补齐，再由管理员运行安装命令。

   ```sh
   pkg add ./os-mihomo.pkg
   ```

   遇到平台、依赖或版本冲突时，先核对系统和来源。保持 OPNsense 官方源及签名校验启用，使用匹配的包解决冲突。[FreeBSD pkg add 文档](https://man.freebsd.org/cgi/man.cgi?query=pkg-add&sektion=8)

## 安装后检查

1. 在 **系统 → 固件** 检查 `os-mihomo` 已登记，刷新 WebGUI，打开 **VPN → Proxy Suite → Mihomo**。菜单缺失时先核对安装状态和账户权限。
2. 如果菜单能打开但后端动作在安装或升级后不可用，等其他配置任务完成后，由管理员在维护窗口运行 `service configd restart`，再刷新页面重试。此操作重新加载 OPNsense 后端动作。
3. 全新安装时，Mihomo 应处于停止状态，开机自启关闭。包会初始化缺失的配置，保留已有配置和自启状态，安装钩子也不会写入防火墙、接口、网关、路由或 DNS。准备好有效配置后再启动。[首次配置](usage.md#首次配置)

## 升级与卸载

- **升级**时备份 OPNsense 和 Mihomo 配置，阅读版本说明，在维护窗口沿原受信渠道安装目标版本。签名源用户从固件管理器升级，单包用户重新验证 Release 包。升级后检查服务状态；需要载入新内核或配置时，确认影响后再从 WebGUI 重启 Mihomo。
- **卸载**前先解除指向 Mihomo 的客户端转发、网关或 DNS 依赖，确认客户端恢复预期的上网与解析路径，然后停用开机自启、停止服务。最后从 **系统 → 固件 → 插件** 卸载；手动包已登记但插件页无移除入口时，可由管理员使用 `pkg delete os-mihomo`。卸载钩子保留用户配置和网络设置。

### 从其他来源迁移

同名包可能有不同的安装和卸载脚本。先确认原来源和版本，查阅旧包的卸载行为，备份系统配置及 Mihomo 文件，记录目前有哪些网络策略依赖 Mihomo。安排维护窗口，按原发布方的步骤卸载或迁移，再安装本项目的包。尤其要检查旧钩子是否会移除接口、网关、防火墙规则或 DNS 设置。
