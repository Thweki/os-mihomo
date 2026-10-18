<div align="center">
  <a href="README.md">中文</a> |
  <a href="README.US.md">English</a>
</div>

# os-mihomo

**OPNsense 原生 WebUI 的 mihomo 插件**

![OPNsense](https://img.shields.io/badge/OPNsense-26.7-red)
![FreeBSD](https://img.shields.io/badge/FreeBSD-15.1-999999)
![mihomo](https://img.shields.io/badge/mihomo-1.19.31--vincent-purple)
![plugin](https://img.shields.io/badge/plugin-os--mihomo-blue)
![i18n](https://img.shields.io/badge/i18n-zh__CN-green)

这是一个**独立维护的 OPNsense 插件项目**：把 [mihomo](https://github.com/MetaCubeX/mihomo)（原 Clash Meta）
装进 OPNsense，并在 **OPNsense 自己的 WebGUI 里**提供完整的图形化管理 —— 不是另起一个 HTTP 服务，
也不嵌入任何第三方面板。

插件以**标准 OPNsense 插件包**的形式分发与安装，因此可以被 OPNsense 自带的**插件管理器**
（`系统 → 固件 → 插件`）安装、升级和卸载。

> 包名与上游插件同名（`os-mihomo`，同一个插件位），所以它能直接替换/升级上游版本；
> 但代码是重新实现的 —— 页面全部是 OPNsense 原生 MVC，而不是原来的 legacy `.php` 页面。

---

## 1. 设计原则

| 原则 | 做法 |
|---|---|
| **原生渲染** | 页面由 OPNsense 自身渲染：Phalcon + Volt + Bootstrap 3 + opnsense 主题。入口 `/ui/mihomo/*`，接口 `/api/mihomo/*` |
| **浏览器不碰控制器** | mihomo 的 RESTful 控制器（`:9090`）只监听回环，由**服务端 PHP** 带密钥代理；浏览器看不到也用不到那个端口 |
| **零第三方前端** | 没有 iframe、没有 zashboard/yacd/metacubexd，不引外部 JS/CSS 资源 |
| **特权操作可审计** | 写配置、读/清日志、跑订阅等特权动作统一走 **configd**（root），而不是 PHP 里 `exec` 拼命令 |
| **改配置前先验证** | 原始 YAML 落盘前先 `mihomo -t` 校验，并保留带时间戳的备份；补丁器只改必要的那一行 |
| **服务默认不自启** | 装完不 enable；仪表盘在检测到"占位节点 / TUN 自动接管路由 / DNS 劫持"等风险时显示红色体检横幅 |

## 2. 功能

菜单：`VPN → Proxy Suite → Mihomo / Settings / Subscription / Log File`

| 页面 | 地址 | 能力 |
|---|---|---|
| **Mihomo**（概览） | `/ui/mihomo` | 服务状态与启停、开机自启开关、**安全体检横幅**、实时速率曲线、累计流量、内存/内核版本、代理分组与节点切换/延迟测试、运行模式切换、活动连接表格（可单条断开/全部断开） |
| **Settings**（设置） | `/ui/mihomo/settings` | 原生表单（服务 / 控制器 / TUN / DNS / 订阅）+ 原始 YAML 编辑器（写盘前 `mihomo -t` 校验、自动备份、"仅改一行"的最小化补丁）+ 从当前配置文件导入 |
| **Subscription**（订阅） | `/ui/mihomo/subscription` | 订阅地址与密钥、一键更新（默认**不**自动重启服务，避免刚换订阅就把网络打断）、实时订阅日志 |
| **Log File**（日志） | `/ui/mihomo/log` | 内核日志 / 订阅日志：可选行数、下载、清空（经 configd 读取，无需放宽文件权限） |

诊断接口：`/api/mihomo/{service,settings,dashboard,subscription,log}/*`
旧地址 `/mihomo.php`、`/mihomo_sub.php` 等一律 302 跳到新页面。

## 3. 截图（真实设备，中文界面）

![概览](docs/screenshots/09-overview-zh_CN.png)

![设置](docs/screenshots/08-settings-zh_CN.png)

![订阅](docs/screenshots/04-subscription.png)

![日志](docs/screenshots/05-log.png)

## 4. 安装

三种方式，按你的场景选一种：

| 方式 | 命令 / 入口 | 会改动系统配置吗 | 适用 |
|---|---|---|---|
| **A. 插件管理器** | `系统 → 固件 → 插件 → 安装`（需先配置插件仓库，见 §5） | 会（执行包内 `+POST_INSTALL`，见下方警告） | 新装设备、希望被固件系统统一管理 |
| **B. 单文件包** | `pkg add -f os-mihomo.pkg` | 同上 | 离线分发 |
| **C. 安全部署脚本** | `scripts/deploy.sh`（配合 `tools/remote.ps1`） | **不会**：只写插件自己的文件，不碰防火墙 / 接口 / DNS / 路由 | 正在服务生产网络的设备（本项目交付时走的就是这条） |

```sh
# 方式 C：安全部署（逐文件安装 + php -l/sh -n 校验 + 清理菜单缓存 + 重启 configd）
powershell -File tools/deploy.ps1               # 首次安装（含内核二进制）
powershell -File tools/deploy.ps1               # 之后升级（不动已存在的 config.yaml）
powershell -File tools/webtest.ps1              # 端到端验证：页面 200 / 接口 200 / 未授权 302
```

> [!CAUTION]
> **`pkg add` / 插件管理器安装会执行包内的 `+POST_INSTALL`**，其行为是上游既有的：
> 1. 向 `/conf/config.xml` 添加 `tun_mihomo` 虚拟接口与一条防火墙放行规则；
> 2. 把 Unbound 的查询转发指向 `127.0.0.1:1053`（mihomo 未运行时会导致 DNS 不可用）；
> 3. 把 `/etc/rc.conf.d/mihomo` 写成 `mihomo_enable="YES"`（**开机自启**）；
> 4. 生成随机 `secret` 写回配置。
>
> 随包分发的 `config.yaml` 用的是占位节点 `88.88.88.88`，而 `tun.auto-route` 默认为真 ——
> **在这种状态下开机自启 = 全屋断网**。所以：要么先换好节点/订阅，要么用方式 C（不改任何网络配置、也不自启）。

## 5. 发布插件仓库（让插件管理器管理它）

本项目的构建链路直接产出**标准 OPNsense 插件仓库目录**（按 ABI 分目录，和官方仓库同构）：

```sh
make package          # → dist/os-mihomo.pkg（默认按本机 ABI 构建）
make repo             # → dist/repo/<ABI>/
```

产物结构：

```text
dist/repo/FreeBSD:15:amd64/
├── os-mihomo-1.1.0.pkg        插件包
├── meta.conf / meta           仓库元数据（pkg 2.x）
├── data.pkg / packagesite.pkg 目录数据
└── os-mihomo.conf             客户端仓库配置模板（含 url/注释）
```

把这个目录放到任意静态站点（或本机某个目录），然后在 OPNsense 上写一份仓库配置：

```sh
# /usr/local/etc/pkg/repos/os-mihomo.conf
os-mihomo: {
  url: "https://example.com/mihomo/FreeBSD:15:amd64",   # 或 file:///usr/local/opnsense/_bak/os-mihomo-repo/FreeBSD:15:amd64
  enabled: yes,
  priority: 20
}
```

```sh
pkg update        # 刷新索引
```

之后 `系统 → 固件 → 插件` 里就会出现 **os-mihomo**，可以一键安装 / 升级 / 卸载
（固件系统的安装路径是 `pkg install -y os-mihomo` + `register.php install`）。

<details>
<summary>为什么这样就"可被插件管理器管理"？—— 实测证据</summary>

插件页面（`/ui/core/firmware` → Plugins）的数据源是 `configctl firmware remote` / `firmware local`，
每行 9 个字段：`name|||version|||comment|||flatsize|||locked|||automatic|||license|||repository|||origin`；
只要 `name` 以 `os-` 开头且能从仓库解析到，就会作为插件列出。把本项目仓库接入后实测：

```text
os-mihomo|||1.1.0|||Mihomo proxy integration for OPNsense|||76.8MiB|||0|||0||||||os-mihomo|||opnsense/os-mihomo
os-mihomo|||1.0.4|||Mihomo proxy integration for OPNsense|||76.7MiB|||0|||0||||||opnwall|||opnsense/os-mihomo
        ↑ 本项目（repository=os-mihomo）            ↑ 上游 1.0.4（repository=opnwall）
```

`pkg version -t 1.1.0 1.0.4` → `>`，所以插件管理器会把它视为**上游版本的升级**。
</details>

## 6. 首次使用（务必先读）

1. **先换节点/订阅，再启动服务。** 编辑 `Settings → 配置文件`，或到 `Subscription` 提交订阅；
   概览页的红色横幅会同时列出当前风险（占位节点、TUN 自动接管路由、严格路由、DNS 劫持、控制器对外暴露等）。
2. **确认自启开关符合预期**：`Settings → 服务 → 启用 mihomo`。默认关闭，是否开机自启由你决定。
3. 启动后看概览页：控制器可达 → 代理分组出现 → 可切节点、看连接与实时速率。
4. 稳定运行后把 `设置 → 日志层级` 调成 `error` 或 `silent`，避免长期写日志。

> **关于 DNS**：如果局域网客户端把 OPNsense 的 LAN 地址当 DNS，Unbound 会在请求到达 mihomo 之前先处理。
> 要让 mihomo 接管 DNS，可 NAT 重定向局域网 DNS、由 DHCP 下发外部 DNS，或让 Unbound 转发到
> mihomo 的监听端口（`1053`）。上游的 `+POST_INSTALL` 走的是最后一种，并在 Fake-IP 里加了
> `geosite:cn` 过滤（国内域名返回真实 IP、国外域名走 Fake-IP）。
> **本项目不会替你改这些**：改不改 DNS、要不要 TUN，全部由你在 `Settings` 里明示。

## 7. 目录结构

仓库根目录就是插件树，`src/` 是安装路径镜像：

```text
src/
├── etc/rc.conf.d/mihomo                                  服务自启开关
├── usr/bin/mihomo_sub                                    订阅命令行工具
└── usr/local/
    ├── bin/mihomo  +  etc/mihomo/{config.yaml,GeoIP.dat,GeoSite.dat,sub/}
    ├── etc/rc.d/mihomo                                   服务脚本
    ├── etc/inc/plugins.inc.d/mihomo.inc                  插件对核心的注册点
    ├── opnsense/version/mihomo                           插件版本元数据
    ├── opnsense/service/conf/actions.d/actions_mihomo.conf  configd 动作（14 个）
    ├── opnsense/scripts/mihomo/                          特权脚本（config_apply/env/logtail/…）
    ├── opnsense/mvc/app/
    │   ├── models/OPNsense/Mihomo/       模型、Config(Safety/Subscription 等)、ACL、Menu
    │   ├── controllers/OPNsense/Mihomo/  页面控制器 + Api/* + forms/settings.xml
    │   └── views/OPNsense/Mihomo/        index/settings/subscription/log 四个 Volt 模板
    └── www/mihomo*.php                                   旧地址 → 302 跳转
```

## 8. 中文化

界面已提供简体中文词条（146 条，覆盖四个页面、表单标签、帮助文本、风险详情）。
OPNsense 用**单一 gettext 域**，插件字符串要显示中文只能合并进
`/usr/local/share/locale/<locale>/LC_MESSAGES/OPNsense.mo`，因此本项目提供一套"只增不改"的工具：

```sh
powershell -File tools/i18n.ps1              # 备份 → 合并 → 校验 → 重启 WebGUI
powershell -File tools/i18n.ps1 -Status      # 查看当前是否已应用
powershell -File tools/i18n.ps1 -Rollback    # 还原
```

* `locales/zh_CN.po` 是标准 gettext 词条（可直接 `msgfmt`，也可提交到官方翻译平台）；
* 合并时**不会覆盖**核心已有译文（校验脚本会逐条比对，实测覆盖 0 条）；
* 系统升级可能重置该 `.mo`，重跑一次 `tools/i18n.ps1` 即可。

## 9. 编译

在 FreeBSD / OPNsense 上构建（需要 `pkg`、`tar`、`make`、`xz`、`sha256`、`curl` 或 `fetch`）：

```sh
make package                  # 本机 ABI（用于插件仓库）
make package ABI=universal    # 通用 ABI（只做单文件分发时用）
make repo                     # 顺带生成插件仓库目录 dist/repo/<ABI>/
pkg info -F dist/os-mihomo.pkg
```

内核二进制默认用仓库内的本地资产 `src/usr/local/bin/clash-meta-freebsd-amd64.xz`，
缺失时才从 [Vincent-Loeng/clash-meta](https://github.com/Vincent-Loeng/clash-meta) 下载，
并校验 `packaging/freebsd/binary-source.json` 里记录的 SHA256。

## 10. 插件标识

| 项 | 值 |
|---|---|
| 包名 / 来源 | `os-mihomo` / `opnsense/os-mihomo` |
| 版本 | `1.1.0`（同一插件位，版本高于上游 1.0.4 才能被插件管理器视为升级） |
| ABI / 架构 | `FreeBSD:<major>:amd64` / `freebsd:<major>:x86:64` |
| 注册点 | `models/OPNsense/Mihomo/{ACL,Menu}`、`etc/inc/plugins.inc.d/mihomo.inc`、`version/mihomo`、`actions_mihomo.conf` |
| 依赖 | `jq`、`curl` |

## 11. 卸载

```sh
# 插件管理器：系统 → 固件 → 插件 → 卸载
# 或命令行：
pkg delete os-mihomo
```

包内 `+PRE_DEINSTALL` 会停服务、移除 `tun_mihomo` 接口与那条防火墙规则、撤销 Unbound 转发、清理相关 cron 项；
`+POST_DEINSTALL` 会清菜单缓存、删掉 `actions_mihomo.conf` 并重启 configd，随后删除 `/usr/local/etc/mihomo`。
**卸载前请自行备份 `/usr/local/etc/mihomo/`（配置与订阅凭据都在里面）。**

## 12. 常用命令

```sh
service mihomo start|stop|restart|status|rcvar   # 服务控制
tail -f /var/log/mihomo.log                      # 内核日志
sockstat -4 -l | egrep ':53|:7891|:9090'         # 端口
ifconfig tun_mihomo                              # TUN 接口
pfctl -sr | grep tun_mihomo                      # 运行期规则
configctl mihomo status|config-current|env-get   # 插件的 configd 动作
/usr/local/etc/rc.restart_webgui                 # 改视图/词条后重启 WebGUI
```

订阅自动更新：`系统 → 设置 → 任务`，添加任务时选择命令 `Renew mihomo Subscription`。

## 13. 文档

| 文档 | 内容 |
|---|---|
| [`docs/report.md`](docs/report.md) | 交付报告：需求分析、架构、**真实截图**、安全证明、验证矩阵、回滚步骤、事故记录 |
| [`docs/design.md`](docs/design.md) | 设计说明：MVC 结构、接口契约、configd 动作、YAML 补丁器规则 |
| [`AGENTS.md`](AGENTS.md) / [`TODO.md`](TODO.md) | 协作手册 / 状态看板（含安全红线与验证方法） |

## 14. 致谢

[mihomo](https://github.com/MetaCubeX/mihomo) ·
[Vincent-Loeng/clash-meta](https://github.com/Vincent-Loeng/clash-meta)（FreeBSD 适配内核） ·
[Opnwall/OPNsense-repo](https://github.com/Opnwall/OPNsense-repo)（本项目的运行期资产来源） ·
[OPNsense](https://opnsense.org/)

## 15. 免责声明

> [!CAUTION]
> 非官方插件，OPNsense 团队不提供支持。代理核心与网络配置的作用域很大：
> 在正在服务生产网络的设备上启用 TUN / 自动路由 / DNS 劫持之前，请先确认你理解其后果。
> 使用本插件所产生的一切后果由使用者自行承担。
