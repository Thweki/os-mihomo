# os-mihomo WebUI 二次开发 — 交付报告

> **一句话**：把上游 `Opnwall/OPNsense-repo:src/os-mihomo`（1.0.4，纯 legacy 过程式页面）的 WebUI
> **重写为 OPNsense 原生 MVC 界面**并实机安装到 `192.168.1.1`，
> 全程未触碰防火墙 / NAT / 路由 / DNS 配置，服务保持未启用状态。
>
> - 目标设备：OPNsense 26.7.7 (amd64) / FreeBSD 15.1-RELEASE-p4 / PHP 8.5.11
> - 本次版本：`os-mihomo 1.1.0`（上游基线 1.0.4）
> - 仓库：本目录（根目录即插件树，3 次提交，可逐级回滚）
> - 全部截图均为 **在真实设备上通过浏览器实测** 所得（见 `docs/screenshots/`）

---

## 目录

1. [交付内容速览](#1-交付内容速览)
2. [上游 WebUI 的问题（附证据）](#2-上游-webui-的问题附证据)
3. [目标架构](#3-目标架构)
4. [实现清单](#4-实现清单)
5. [界面实测（真实截图）](#5-界面实测真实截图)
6. [与 OPNsense 原生风格的一致性](#6-与-opnsense-原生风格的一致性)
7. [安全边界与「零网络改动」证明](#7-安全边界与零网络改动证明)
8. [验证矩阵](#8-验证矩阵)
9. [部署 / 回滚 / 日常运维](#9-部署--回滚--日常运维)
10. [事故记录](#10-事故记录)
11. [已知限制与后续建议](#11-已知限制与后续建议)
13. [P8 收尾：打包 / 回滚演练 / 中文化](#13-p8-收尾打包--回滚演练--中文化)
14. [附录：命令速查](#14-附录命令速查)

---

## 1. 交付内容速览

| 项目 | 内容 |
|---|---|
| 页面 | `VPN → Proxy Suite →` **Mihomo / Settings / Subscription / Log File**（4 个原生 MVC 页面） |
| 路由 | `/ui/mihomo`、`/ui/mihomo/settings`、`/ui/mihomo/subscription`、`/ui/mihomo/log` |
| 接口 | `/api/mihomo/{service,settings,dashboard,subscription,log}/*`（共 20 个端点） |
| 仪表盘 | 服务状态、实时速率曲线、累计流量、内存/版本、**代理分组与节点切换/测速**、**活动连接表**（可关闭单条/全部）、运行模式切换 |
| 设置 | 原生表单（服务/控制器/TUN/DNS/订阅）+ 原始 YAML 编辑器（写盘前 `mihomo -t` 校验 + 自动备份） |
| 订阅 | 订阅地址/密钥、一键更新、**默认不自动重启服务**（安全默认）、实时日志 |
| 日志 | 内核日志 / 订阅日志双来源，支持行数、刷新、下载、清空（经 configd 读 root 文件，无需放宽权限） |
| 兼容 | 旧地址 `/mihomo.php` → 302 `/ui/mihomo`（保留 ACL 保护） |
| 安全体检 | 启动前显式列出 TUN 接管、占位节点、控制器暴露、DNS 劫持等风险 |
| 服务控件 | 页面标题栏原生 start/stop/restart 按钮（`updateServiceControlUI`） |
| 内核资产 | 沿用上游 mihomo 内核（1.19.31-vincent）、rc.d、订阅脚本、configd 动作 |
| 安装包 | `os-mihomo-1.1.0.pkg`（25.7 MiB，sha256 `2faa09a9…`），native ABI，已是**标准 OPNsense 插件包**格式，可被自带插件管理器管理 |
| 中文化 | 146 条 zh_CN 词条，四个页面 + 表单标签 + 帮助 + 风险详情全中文 |

---

## 2. 上游 WebUI 的问题（附证据）

上游 1.0.4 的 WebUI 是 4 个过程式页面（`/usr/local/www/mihomo*.php`），实测存在以下问题。
下表右列均为本次在设备上**实测/读源码**得到的结论。

| # | 问题 | 证据 |
|---|---|---|
| 1 | 不属于 MVC，无控制器/视图/模型 | 上游源码只有 `www/*.php`，无 `controllers` / `views`；菜单直接指 `/mihomo.php` |
| 2 | 不用框架的服务控件 | 页面用 `fetch('/mihomo.php?ajax=status')` + `setInterval(2000)` 自建轮询，而不是 `updateServiceControlUI()` |
| 3 | 自建 CSRF，与框架机制并存 | 每个页面各自维护 `$_SESSION[..._csrf_token]` |
| 4 | 自实现 i18n，靠正则解析 `/conf/config.xml` 猜语言 | `proxy_lang()` 正则读 config.xml，忽略 `lang._()` / gettext |
| 5 | **「WebUI」实际依赖另起 HTTP 服务** | 上游 README：「默认配置会开启 Clash API，可通过 `http://LAN_IP:9090/ui` 访问仪表盘」；`config.yaml` 里的 `external-ui-url` 还会在运行时从 GitHub 拉取第三方面板 zashboard |
| 6 | 控制器对外暴露 | `external-controller: 0.0.0.0:9090`，且 `secret` 是随包占位值 `CHANGE_ME` |
| 7 | 启动无任何风险提示 | 默认 `tun.auto-route: true` + 占位节点 `88.88.88.88`，启动即接管全局路由，界面不提示 |
| 8 | 订阅更新会无条件重启服务 | `sub.sh` 结尾 `MIHOMO_SERVICE_CMD="service mihomo restart"`，即使新配置有问题也会触发重启 |

> **一处重要更正（记录在案）**：本次实现过程中实测发现，**本机 WebGUI 的 PHP 其实是以 root 运行的**
> —— lighttpd（root）通过 `mod_fastcgi` 拉起 `php-cgi`（`ps` 显示 10 个 `php-cgi` 全部是 root；
> `php-fpm.d/www.conf` 里的 `user = www` 并不服务于 WebGUI）。
> 因此上游页面里那些 `exec()` / `fopen()` / `is_writable()` 判断**是可行的**，
> 上游并不存在"保存配置必然失败/日志必然空白"的问题（这一点在初稿中判断有误，已更正）。
>
> 既然如此，为什么本次仍把特权写入统一改走 **configd**？三个理由：
> 1. **可审计**：每个动作都会进 syslog，谁在什么时候改了配置一查便知；
> 2. **少一处 RCE 面**：PHP 里不再拼接执行 shell 命令，也不在 Web 进程里做文件属主判断；
> 3. **可测试**：这些脚本能脱离 Web 环境单独以 root 运行并做回归（本次就是这么做的）。

---

## 3. 目标架构

```
   浏览器（已登录的 OPNsense WebGUI 会话，受 ACL 保护）
        │
        │  /ui/mihomo/*        Volt 视图（Bootstrap 3 + opnsense 主题）
        │  /api/mihomo/*       OPNsense MVC API（自动 CSRF / ACL / 审计）
        ▼
   php-fpm (用户 www) ── 只读直读 config.yaml（0644）
        │
        ├── configd (root) ◄── 特权动作
        │      └── /usr/local/opnsense/scripts/mihomo/{config_apply,env,logtail,logclear,service_enable,subscription_run}
        │
        └── loopback HTTP 127.0.0.1:9090 ◄── mihomo external controller
               GET  /version /configs /proxies /connections
               PUT  /proxies/{name}        选节点
               GET  /proxies/{name}/delay  测延迟
               PATCH /configs              切模式
               DELETE /connections[/{id}]  断连接
```

**三条硬约束**（也是验收标准）：

1. 所有页面由 **OPNsense 自身 MVC** 渲染 —— 无 iframe、无第三方面板（zashboard/yacd/metacubed）。
2. 浏览器**永不**直连 `:9090`；所有实时数据由 **服务端 PHP** 经 loopback + Bearer secret 取回。
3. 特权操作（写配置、写 env、读日志）**全部经 configd 以 root 执行**，不给 Web 进程放宽任何文件权限。

---

## 4. 实现清单

### 4.1 新增文件（安装路径镜像）

```
src/usr/local/opnsense/mvc/app/
├── models/OPNsense/Mihomo/
│   ├── Mihomo.php / Mihomo.xml         设置模型（挂载 //OPNsense/mihomo）
│   ├── Config.php                      config.yaml 扫描 + 嵌套键补丁 + 临时文件
│   ├── Controller.php                  mihomo REST 客户端（loopback）
│   ├── Safety.php                      安全体检规则集
│   ├── Logs.php                        日志读取（经 configd）
│   ├── Subscription.php                订阅 env / 执行 / 日志
│   ├── RequestParamsTrait.php          参数读取（POST/JSON/GET 兼容）
│   ├── ACL/ACL.xml                     ui/mihomo/*、api/mihomo/*、旧页面
│   └── Menu/Menu.xml                   VPN → Proxy Suite → 4 项
├── controllers/OPNsense/Mihomo/
│   ├── Index/Settings/Subscription/LogController.php     4 个页面控制器
│   ├── forms/settings.xml                                原生表单定义
│   └── Api/{Dashboard,Service,Settings,Subscription,Log}Controller.php
└── views/OPNsense/Mihomo/{index,settings,subscription,log}.volt

src/usr/local/opnsense/scripts/mihomo/
├── config_apply.php      校验( mihomo -t )→ 备份 → 原子安装（root）
├── env.php               订阅 env 读写（root，0600）
├── logtail.php           日志尾部（root）
├── logclear.php          日志清空（root）
├── service_enable.php    写 /etc/rc.conf.d/mihomo
└── subscription_run.sh   订阅执行器（默认不重启服务）

src/usr/local/www/mihomo{,_sub,_logs,_sub_log}.php    → 302 跳转页
src/usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf   新增 9 个动作
```

### 4.2 API 一览

| 端点 | 方法 | 说明 |
|---|---|---|
| `/api/mihomo/service/status` | GET | 状态（`running`/`stopped`/`disabled`）+ 控件文案 |
| `/api/mihomo/service/{start,stop,restart}` | POST | 服务控制（configd → rc.d/mihomo） |
| `/api/mihomo/service/safety` | GET/POST | 安全体检（可选 `validate=1` 触发语法校验） |
| `/api/mihomo/settings/get` `set` | GET/POST | 模型读写（原生 `ApiMutableModelControllerBase`） |
| `/api/mihomo/settings/apply` | POST | 模型 → config.yaml + rc.conf.d + env（带校验/备份） |
| `/api/mihomo/settings/import` | POST | 现状 → 模型（首次使用/手工改过配置后同步） |
| `/api/mihomo/settings/config_{get,set,validate,test}` | 混合 | 原始 YAML 读/写/校验 |
| `/api/mihomo/dashboard/{overview,proxies,connections}` | GET | 概览 / 代理分组 / 连接表（服务端分页搜索） |
| `/api/mihomo/dashboard/{select_proxy,test_delay,set_mode,close_connection}` | POST | 选节点 / 测速 / 切模式 / 断连接 |
| `/api/mihomo/subscription/{get,save,run,log,clear_log}` | 混合 | 订阅管理 |
| `/api/mihomo/log/{tail,clear}` | 混合 | 日志 |

### 4.3 config.yaml 的「外科手术式」修改

设置页的 Apply 不是"整文件覆盖"，而是严格的最小改动流程：

1. 读入现有 `config.yaml`；
2. **逐键比较**：目标值与文件现有值等价的键 **一个字节都不动**（保留原有注释、引号风格、缩进）；
3. 需要改动的键，只替换该行的值，并**保留该行的行尾注释**；
4. 只触及受管键（`log-level`、`mode`、`allow-lan`、`external-controller`、`secret`、`tun.*`、`dns.*`），
   `proxies` / `proxy-groups` / `rules` / 其它注释完全不动；
5. 写入 `/tmp/mihomo-XXXXXX`（0600，随机名）；
6. `configd` 以 root 运行 `mihomo -t` 校验 → **不通过就一个字都不写**；
7. 通过后备份 `config.yaml.bak.YYYYmmdd_HHMMSS`（保留最近 20 份），再 `install -o root -g wheel` 原子替换。

实测效果（Apply 后的完整 diff，配置里原本有大量中文注释与代理规则）：

```diff
-external-controller: 0.0.0.0:9090
+external-controller: 127.0.0.1:9090
```

就这一行。其余 233 行（含 `log-level: info #在调试结果后…`、`secret: "CHANGE_ME"`、4 个代理节点、19 条规则）**逐字节未变**。

补丁器有 **35 项回归测试**（`tests/test_patch.php`），在目标机上对真实 `config.yaml` 跑通 **0 失败**，
覆盖：幂等性、值相同零改动、行尾注释保留、CRLF、特殊值引号、嵌套块新增、proxies/rules 完整性、
以及"补丁结果必须能通过 `mihomo -t`"。

---

## 5. 界面实测（真实截图）

> 截图采集方式：`agent-browser`（真实 Chromium）登录 `https://192.168.1.1` 后逐页截图。
> 仪表盘的数据来自一个**隔离 demo 实例**（无 TUN、无 DNS 劫持、仅监听 127.0.0.1），
> 目的只是让曲线/连接表/代理组有真实内容；该实例已停止，见 §7。

### 5.1 概览 / 仪表盘

![概览仪表盘](screenshots/01-overview.png)

自上而下：

1. **服务未启用提示**（橙）——默认不 enable，避免重启后自动接管路由；
2. **启动前安全体检**（红）——逐条列出 TUN 自动接管、strict-route、占位节点、控制器暴露、DNS 劫持；
3. **四个原生统计卡**——活动连接、实时上下行、累计流量、内存/内核版本（图标徽章样式与核心页面一致）；
4. **流量曲线**——2 秒采样，实时速率；
5. **Proxy Groups**——每个分组一张卡片：类型徽章、整组测速、成员列表（已选中的打绿勾）、
   单节点测速按钮、延迟徽章（<200ms 绿 / <500ms 黄 / 超时红）；
6. **Active Connections**——标准 `UIBootgrid`：搜索、排序、分页、"关闭全部"，每行可单独断开。

不运行服务时（交付后的默认状态）：

![概览（未启用服务）](screenshots/01b-overview-idle.png)

### 5.2 菜单集成

![菜单](screenshots/02-menu.png)

`VPN → Proxy Suite → Mihomo / 设置 / 订阅 / 日志`，与 `IPsec`/`OpenVPN`/`WireGuard` 同级，
带主题高亮与锁图标（继承 `ProxySuite` 的 `fa-lock`），标题栏显示完整面包屑
`VPN: PROXY SUITE: MIHOMO`。

### 5.3 设置

![设置](screenshots/03-settings.png)

原生 `base_form` 渲染：分节折叠、开关、下拉、文本框全部由模型驱动，
页脚是 Apply / Import from configuration file / Restart the service after applying。

「Configuration File」标签页提供原始 YAML 编辑：

![配置文件编辑](screenshots/06-settings-config.png)

### 5.4 订阅

![订阅](screenshots/04-subscription.png)

上图是**真实执行过一次订阅更新**后的日志（订阅地址是随包占位的 `https://bing.com`，
所以下载失败）。请注意日志首尾：

```
[2026-10-18 10:50:10] Subscription task submitted (restart service after update: no).
...
[2026-10-18 10:50:12] Subscription task finished (exit=2).
```

**任务失败但配置文件与运行中的服务毫发无伤** —— 这正是上游 `sub.sh` 结尾写死
`service mihomo restart` 所带来的风险，本次通过 `MIHOMO_SERVICE_CMD` 覆写为
「不重启」，并把"更新后重启"做成显式勾选项（默认关闭）。

### 5.5 日志

![日志](screenshots/05-log.png)

内核日志（真实 mihomo 输出，含规则匹配明细）。切换数据源可看订阅日志：

![订阅日志](screenshots/05-log-subscription.png)

> 这两处日志文件属主是 root（`0640`），页面能读是因为统一经 configd 取回，
> 与核心插件（Monit / Unbound 的日志页）走的是同一条可审计路径。

### 5.6 服务控件（临时演示）

把模型开关临时打开（**未修改 rc.conf.d、未启动服务**）后，页面标题栏出现原生服务控件：

![服务控件](screenshots/07-overview-service-widget.png)

红色方块 = 服务已停止，绿色 ▶ = 启动按钮（悬停提示文案来自 API 的 `widget.caption_*`）。
演示后已还原为「未启用」。

---

## 6. 与 OPNsense 原生风格的一致性

对照同一个设备上的核心页面：

| 核心页面 | 本次交付 |
|---|---|
| ![Unbound 概览](screenshots/90-ref-unbound.png) | 同样的 `content-box` 卡片、`nav-tabs`、统计卡、图表与列表 |
| ![Monit 状态](screenshots/91-ref-monit.png) | 同样的服务控件、`UIBootgrid` 表格、BootstrapDialog 弹窗 |

具体对齐点：

- **框架**：`IndexController extends \OPNsense\Base\IndexController`、`ApiMutableModelControllerBase`、`ApiMutableServiceControllerBase`
- **视图**：Volt 模板、`layout_partials/base_form`、`lang._()` 国际化、`cache_safe()` 资源
- **交互**：`mapDataToFormUI` / `saveFormToEndpoint` / `updateServiceControlUI` / `ajaxGet` / `ajaxCall` / `UIBootgrid`
- **样式**：`content-box`、`nav-tabs`、`btn btn-primary`、`label-opnsense`、`fa` 图标、
  `grid-bottom-reserve` 应用栏、统计卡使用主题强调色 `rgba(217,79,0,…)`
- **无自定义 CSS 文件**：所有微调都是就地内联，避免污染主题

---

## 7. 安全边界与「零网络改动」证明

### 7.1 红线（写进 `AGENTS.md`，全程遵守）

- 不执行上游 `packaging/freebsd/+POST_INSTALL`（它会改 `config.xml`、加 TUN 接口、加防火墙放行规则、改 Unbound 转发）
- 不执行 `service mihomo start`（默认配置 `tun.auto-route: true` 会劫持全局路由）
- 不做 `configctl filter reload` / `unbound restart` / 任何 `pfctl` 写操作
- 唯一受控例外：通过原生模型机制写入**本插件自己的** `<OPNsense><mihomo>` 节点（写入前备份、写入后逐节点 diff、全程留痕）

### 7.2 部署前后指纹对比（设备实测）

| 指纹 | 部署前 | 部署后（最终） | 结论 |
|---|---|---|---|
| `/conf/config.xml`（去掉 mihomo 节点与 revision 后） | — | — | **逐节点完全相同** |
| pf 运行规则 | `b8585944…95aaa6` | `b8585944…95aaa6` | 一致 |
| pf NAT 规则 | `3bc6b546…afd385` | `3bc6b546…afd385` | 一致 |
| 路由表 | `46676138…8c5619` | `46676138…8c5619` | 一致 |
| Unbound 配置 | `1d1849c3…dcf532` | `1d1849c3…dcf532` | 一致 |
| 接口清单 | `igb0..7 lo0 enc0 pfsync0 pflog0 pppoe1` | 同左（**无 tun**） | 一致 |
| 监听端口 | 仅 Unbound/DNS | 同左（**无 9090/1053**） | 一致 |
| `/etc/rc.conf.d/mihomo` | 不存在 | `mihomo_enable="NO"` | 安全默认 |
| mihomo 服务 | 未安装 | **未运行、未启用** | 安全默认 |

config.xml 的差异只有两类，且都是预期的：

```
+ <OPNsense><mihomo>…</mihomo></OPNsense>      ← 插件设置节点（受控例外，不参与网络行为）
~ <revision><description>/<time>              ← OPNsense 框架每次保存配置都会追加的审计记录
```

`config.yaml` 在 Apply 后的差异（**完整 diff**）：

```diff
-external-controller: 0.0.0.0:9090
+external-controller: 127.0.0.1:9090
```

这一行是**有意的加固**：把控制器从"全网段可访问"改成"仅本机回环"，
与本插件"浏览器永不直连 :9090"的设计一致。

> 想恢复成上游的 `0.0.0.0:9090` 只需在「设置 → External Controller → Bind Address」填 `0.0.0.0` 再 Apply；
> 或直接编辑 `config.yaml` 后 `service mihomo restart`。
> 备份文件在 `/usr/local/etc/mihomo/config.yaml.bak.*`（保留最近 20 份）。

### 7.3 权限模型

| 操作 | 执行者 | 说明 |
|---|---|---|
| 读 `config.yaml` | Web PHP | 文件是 0644 |
| 读 `/var/log/mihomo*.log` | configd (root) | 统一经 configd，保持与核心插件一致的可审计路径 |
| 写 `config.yaml` | configd (root) | 参数经 `escapeshellarg`，临时文件 0600 + 随机名 + 非符号链接 + 内容必须通过 `mihomo -t` |
| 写 `sub/env` | configd (root) | 0600，原子 rename |
| 写 `/etc/rc.conf.d/mihomo` | configd (root) | 仅 yes/no |
| 调用 mihomo API | Web PHP → 127.0.0.1 | Bearer secret，2~5 秒超时，服务未运行优雅降级 |

> 关于权限的一处实测更正：本机 WebGUI 的 PHP 是以 **root** 运行的（`php-cgi`，见 §2 末尾说明）。
> 因此"经 configd"并不是权限所迫，而是出于**可审计、少一处 shell 拼接、可独立测试**的工程选择；
> 所有特权脚本也都可以脱离 Web 环境单独以 root 运行做回归。

---

## 8. 验证矩阵

`tools/webtest.ps1` 在交付状态下的最后一轮结果：

| 类别 | 项目 | 结果 |
|---|---|---|
| 登录 | 带 CSRF 的 WebGUI 登录 | ✅ 302 |
| 页面 | `/ui/mihomo` / `/ui/mihomo/settings` / `/ui/mihomo/subscription` / `/ui/mihomo/log` | ✅ 200，关键 DOM 存在，无 PHP 错误 |
| 兼容 | `/mihomo.php` → `/ui/mihomo` | ✅ 302 |
| API GET | service/status、service/safety、settings/get、settings/config_get、subscription/get、subscription/log、log/tail、dashboard/overview、dashboard/proxies、dashboard/connections | ✅ 全部 200 |
| API POST | service/safety、dashboard/set_mode、settings/config_test、settings/import | ✅ 全部 200 |
| ACL | 未登录访问 `/ui/mihomo`、`/api/mihomo/service/status` | ✅ 302（被拦） |
| 语法 | 全部 PHP `php -l`、全部 shell `sh -n` | ✅ 0 错误 |
| 后端 | configd 注册 `mihomo` 动作 14 个 | ✅ |
| 后端 | `configctl mihomo status / config-current / env-get / log-tail / set-enabled / log-clear` | ✅ |
| 安全 | 真实 config.yaml 上的补丁器回归（35 断言） | ✅ 0 失败 |
| 写入 | 设置页 Apply 往返（模型 → config.yaml，含备份） | ✅ 成功，diff 仅 1 行（见 §4.3/§7.2） |
| 写入 | 值相同时的零改动保证 | ✅ 字节完全一致 |

---

## 9. 部署 / 回滚 / 日常运维

### 9.1 部署（本机 → 设备，安全模式）

```powershell
# 仅同步 WebUI / 脚本（不动内核二进制，不改任何网络配置）
.\tools\deploy.ps1

# 首次部署需要内核二进制时
.\tools\deploy.ps1 -WithBinary
```

`scripts/deploy.sh` 做的事情：净化（去 BOM/CRLF）→ 备份到
`/usr/local/opnsense/_bak/os-mihomo/<时间戳>/`（含 config.xml 与状态快照）→ 按清单安装 →
`php -l`/`sh -n` → 清菜单/ACL/模型缓存 → `service configd restart` → 报告。
**不会** enable 服务，**不会**碰 config.xml / 防火墙 / Unbound。

### 9.2 回滚

```sh
# 设备上：列出备份
ls -1 /usr/local/opnsense/_bak/os-mihomo/
# 从指定备份恢复（示例）
cp -a /usr/local/opnsense/_bak/os-mihomo/<TS>/usr/local/etc/mihomo /usr/local/etc/
cp -a /usr/local/opnsense/_bak/os-mihomo/<TS>/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo /usr/local/opnsense/mvc/app/models/OPNsense/
# 恢复旧 WebUI 页面（若是从 1.0.4 升级）
cp -a /usr/local/opnsense/_bak/os-mihomo/<TS>/usr/local/www/mihomo*.php /usr/local/www/
rm -f /var/lib/php/tmp/opnsense_{menu,acl}_cache.*
service configd restart
```

代码层面：`git log --oneline` 三次提交，任意一次都能 `git checkout` 回退：

```
fa63bbb  feat(ui): 对齐原生统计卡与服务控件，修复主题 max-width 限制
b21013a  feat(mvc): 用 OPNsense 原生 MVC 重写 WebUI（后端 + 视图 + 部署链路）
8bfe014  chore: 导入上游 os-mihomo 1.0.4 基线 + 工程脚手架
```

### 9.3 日常运维

```sh
service mihomo status|start|stop|restart     # 服务（注意：见下方警告）
tail -f /var/log/mihomo.log                  # 日志
configctl mihomo config-current              # 校验当前配置
sockstat -4 -l | egrep ':9090|:1053|:7891'   # 端口
```

> ⚠️ **启动前务必确认**：默认 `config.yaml` 里是随包分发的**占位节点 `88.88.88.88`**，
> 且 `tun.auto-route: true`。在换成真实订阅/节点之前启动，会让本机后面所有设备断网。
> 仪表盘的红色安全体检横幅就是在提示这件事。

---

## 10. 事故记录

**事件**：`scripts/reset_state.sh` 中误留一行 `sh /tmp/__remote.sh ...`，而该路径正是脚本在设备上的落盘位置，
导致**无限递归自调用**，设备上短时间内堆积约 **9791 个 shell 进程**，`load average` 峰值 **129.90**。

**处置**：`pkill -9 -f '__remote.sh'` 多轮清理 → 逐 PID 清理 → 全面体检。

**影响评估（已逐项实测）**：

- pf 规则 / NAT / 路由表 / Unbound 配置指纹 **与基线逐字节一致**
- DNS 解析正常（NOERROR 3 答案）、出网 HTTP 200、默认路由正常
- Unbound 进程 PID 自事故前起未变（68002）→ **从未被重启**
- lighttpd / configd 正常，WebGUI 全程可用
- 结论：**未造成任何网络中断**；影响限于设备进程表与短时负载，清理后进程数回到 96、负载持续回落

**永久加固**：`tools/remote.ps1` 增加护栏 —— 待执行脚本内容只要出现 `__remote.sh` 就**拒绝执行**（exit 3）。

### 第二次小事故：误启了一个 lighttpd 实例（已复原）

排查 i18n 生效问题时，我先用了 `service lighttpd onerestart` —— 它管理的是
`/usr/local/etc/lighttpd/lighttpd.conf` 那个实例，**不是 WebGUI 所用的**
`/usr/local/etc/lighttpd_webgui/lighttpd.conf`（由 `/usr/local/etc/rc.restart_webgui` 管理）。
结果多起了一个监听 `*:80` 的 lighttpd 进程。发现后立即 `kill` 该 PID，
并确认 WebGUI 实例（51761）仍独占 443/80，WebGUI 返回 200。
正确做法已写入 `tools/i18n.ps1` 与报告 §13.3。

> 诚实记录在此，原因有二：一是这条约束对后续维护者有价值；
> 二是它恰好说明为什么本任务把「可探测、可回滚、每一步留指纹」当成硬要求。

---

## 11. 已知限制与后续建议

| # | 事项 | 建议 |
|---|---|---|
| 1 | 界面文案中英混杂（`Settings` 显示为「设置」而 `Access Secret` 仍是英文） | **已解决**：146 条 zh_CN 词条（`locales/zh_CN.po`），四页 + 表单标签 + 帮助文本 + 风险详情全中文；见 §13.3。注意词条合并进的是基础系统 `OPNsense.mo`，系统升级可能覆盖，重跑 `tools/i18n.ps1` 即可 |
| 2 | 上游 `+POST_INSTALL` 会自动改 `config.xml` / 加防火墙规则 / 改 Unbound 转发 | 本仓库保留上游行为（`pkg` 安装与上游等价），但**强烈建议**改为显式 opt-in；本次实机安装走的是安全路径，从未执行它 |
| 3 | 默认 `config.yaml` 是占位节点 + TUN 自动接管 | 已在 UI 做红色体检提示；可考虑首次进入时强制走"导入/编辑"向导 |
| 4 | 控制器默认 `external-controller: 0.0.0.0:9090` | 已把回环绑定写进模型默认值：本次 Apply 后实际已改为 `127.0.0.1:9090`（见 §7.2）；如需还原见同处说明 |
| 5 | 仪表盘不做历史留存（刷新即丢） | 可加"最近 N 分钟"环形缓冲或写 RRD（OPNsense 有现成 rrd 基础设施） |
| 6 | 没有单元测试框架 | 已有 `tests/test_patch.php`；可扩展成 `phpunit` 套件并接入 CI |

---

## 13. P8 收尾：打包 / 回滚演练 / 中文化

### 13.1 实机构建安装包

在目标机上（FreeBSD 15.1 + pkg 2.8.4）实跑 `make package`：

```
==> Staging files
==> Using local asset .../clash-meta-freebsd-amd64.xz     ← SHA256 与 build.sh 里记录的一致
==> Generating plist / metadata
==> Creating package for FreeBSD:*:amd64
==> Package: .../dist/os-mihomo.pkg
==> Verified package metadata
SHA256 (os-mihomo.pkg) = 01221aa2853962652a3d0df47d5811f458f6c6aa0bee09dc4ae88eb8e881d032
```

| 项 | 值 |
|---|---|
| 文件名 | `os-mihomo-1.1.0.pkg`（`dist/os-mihomo.pkg`，已回传本地 `dist/`） |
| 大小 | 26,934,356 字节（25.7 MiB） |
| SHA256 | `2faa09a9…16f2c54`（本地与设备一致，native ABI 构建） |
| ABI / 架构 | `FreeBSD:15:amd64` / `freebsd:15:x86:64` |
| 文件数 | 49 |
| Flat size | 76.8 MiB |
| 元数据 | `pkg info -F` 校验通过（name/version/origin/ABI/deps/annotations） |
| 安装脚本 | `+POST_INSTALL`(135 行) / `+PRE_DEINSTALL`(122 行) / `+POST_DEINSTALL`(13 行)，`sh -n` 全部通过 |

> `make package` 生成的 tar 会记录文件 mtime，因此**两次构建的 SHA256 不同**（本次先出 `b23d4dd2…`，
> 随后 `make repo` 触发的重构建产出 `2faa09a9…`）。以最后一次构建产物与 `dist/` 回传副本为准。

**发现并修掉一个打包缺陷**：`build.sh` 只给上游那批文件设了执行位，
本次新增的 `subscription_run.sh` 在包里是 `0644` —— 而 configd 会**直接执行**它，
安装后会动作失败。已在 `build.sh` 中补齐 chmod，并加了权限审计脚本：

```
=== 包内所有非 0644 的条目 ===
-rwxr-xr-x /usr/bin/mihomo_sub
-rwxr-xr-x /usr/local/bin/mihomo
-rw------- /usr/local/etc/mihomo/sub/env                      ← 敏感文件 0600
-rwxr-xr-x /usr/local/etc/mihomo/sub/sub.sh
-rw------- /usr/local/etc/mihomo/sub/template_config.yaml     ← 敏感文件 0600
-rwxr-xr-x /usr/local/etc/rc.d/mihomo
-rwxr-xr-x /usr/local/opnsense/scripts/mihomo/*.{php,sh}      ← 7 个可执行脚本
```

> ⚠️ 安装这个包会执行上游的 `+POST_INSTALL`（改 config.xml / 加防火墙规则 / 改 Unbound 转发），
> 与上游行为一致；不想动网络配置请用 `scripts/deploy.sh` 的安全路径。

### 13.1b 把包做成「插件管理器可管理」的标准格式（P10）

**需求**：本项目是**独立插件项目**，交付物必须是 OPNsense **自带插件管理器**（`系统 → 固件 → 插件`）
能安装 / 升级 / 卸载的标准插件包，而不只是一个能 `pkg add` 的文件。

**取证**（在目标机上对着同类插件反推格式）：

| 取证点 | 结论 |
|---|---|
| 已由插件管理器安装的 `os-ttyd` / `os-ddns-go` 的 `+MANIFEST` | 字段：`name/origin/version/comment/maintainer/www/abi/arch/prefix/flatsize/licenses/desc/annotations{repo_type,repository}`，`abi` 是**本机 ABI**（`FreeBSD:15:amd64`），`annotations.repository` = 仓库名 |
| 仓库从哪来 | `/usr/local/etc/pkg/repos/opnwall.conf` → `url: https://opnwall.github.io/OPNsense-repo/repo/${ABI}`，即**第三方插件仓库** |
| 插件页面的数据源 | `configctl firmware remote` / `firmware local`，每行 9 个 `|||` 字段：`name\|version\|comment\|flatsize\|locked\|automatic\|license\|repository\|origin`；`Core/Api/FirmwareController::infoAction()` 里只要 `name` 以 `os-` 开头就归为插件 |
| 安装路径 | `firmware/install.sh`：`os-*` 包先校验核心版本，然后 `pkg install -y <pkg>` + `register.php install <pkg>` |

**据此改造**：

1. `build.sh`：`ABI` 默认由 `universal` 改为 **`native`**（仓库按 ABI 分目录，必须匹配）；
   清单新增 `licenses` 与 `annotations{repo_type:"binary", repository:"$REPO_NAME"}`；
   同时修掉 `VERSION` 默认值仍是上游 `1.0.4` 的陈旧默认。
2. `Makefile`：`ABI ?= native`、新增 `REPO_NAME`、新增 **`make repo`** 与 `make install-repo`。
3. `scripts/make_repo.sh`（新增）：产出标准仓库目录
   `dist/repo/<ABI>/{meta.conf,meta,data.pkg,packagesite.pkg,os-mihomo-<ver>.pkg,os-mihomo.conf}`。
4. 目标机上落地：仓库放到 `/usr/local/opnsense/_bak/os-mihomo-repo/<ABI>/`，
   仓库配置 `/usr/local/etc/pkg/repos/os-mihomo.conf` 默认 **`enabled: no`**（现网设备不启用）。

**验证（临时启用 → 取证 → 立即关闭并清缓存）**：

```
Updating os-mihomo repository catalogue... 1 packages processed.

# 插件页面的数据源（configctl firmware remote）：
os-mihomo|||1.1.0|||Mihomo proxy integration for OPNsense|||76.8MiB|||0|||0||||||os-mihomo|||opnsense/os-mihomo
os-mihomo|||1.0.4|||Mihomo proxy integration for OPNsense|||76.7MiB|||0|||0||||||opnwall|||opnsense/os-mihomo

pkg version -t 1.1.0 1.0.4   →  >          # 插件管理器会视为「上游版本的升级」
```

关闭后复核：`pkg search os-mihomo` 只剩上游 `1.0.4`；`/var/db/pkg/repos/os-mihomo` 缓存已删除；
启用中的仓库仍是 `OPNsense` + `opnwall` 两个（与改造前一致）。本插件**没有**进入 pkg 数据库
（`pkg info os-mihomo` → no package matching），即目标机仍是手工部署状态，未因这次验证被安装。

### 13.2 回滚演练（实跑，0 failures）

演练内容：从旧备份集回滚 41 个受管文件 → 校验 → 重新部署 → 校验 → 恢复配置数据。

```
########## 1. 快照当前状态（LATEST）##########
  受管文件数: 41      缺失: 0
########## 2. 暂存 config.yaml 与 rc.conf.d（配置数据不参与回滚）##########
########## 3. 从备份集回滚代码文件：_bak/os-mihomo/20261018_102822 ##########
  恢复 41 个文件
########## 4. 校验回滚结果 ##########
  与 LATEST 不同的文件（期望 > 0）：
    - .../controllers/OPNsense/Mihomo/forms/settings.xml
    - .../models/OPNsense/Mihomo/Config.php
    - .../models/OPNsense/Mihomo/Menu/Menu.xml
    - .../models/OPNsense/Mihomo/Safety.php
    - .../views/OPNsense/Mihomo/index.volt   (等 11 个)
  差异文件数: 11
  与备份集逐字节比对（期望 0 处不一致）：    一致 41 / 不一致 0
  回滚后页面可用性（未登录 302 = 正常响应）：
    /ui/mihomo 302   /ui/mihomo/settings 302   /ui/mihomo/subscription 302
    /ui/mihomo/log 302   /mihomo.php 302
  版本标记（期望呈现旧版特征）：
    valuesEqual（新）: no -> 已回滚到旧版
    checkbox（新）   : no -> 已回滚到旧版
########## 中间：重新部署最新版 ##########
  php files with syntax errors: 0
  registered mihomo actions: 14 (expected 14)
########## 6. 与回滚前（LATEST）比对 ##########
  PASS：重新部署后与回滚前逐字节一致
  版本标记：valuesEqual YES / Safety.shorten YES / checkbox YES / fail()写stdout YES
########## ROLLBACK DRILL RESULT: 0 failures ##########
```

结论：**回滚可用、可探测、可复原**——回滚后与备份逐字节一致，重新部署后与回滚前逐字节一致，
配置数据（`config.yaml` / `rc.conf.d`）在整个过程中被单独保护、不参与回滚。

### 13.3 中文化（消除中英混杂）

**难点**：OPNsense 用**单一 gettext 域**（`defaultDomain = OPNsense`，
目录 `/usr/local/share/locale/<locale>/LC_MESSAGES/OPNsense.mo`），
插件字符串要显示中文只能合并进这个系统文件；而 FreeBSD 上没有 `msgfmt`/`msgunfmt`。

**做法**（可回滚、只增不改）：

1. `tools/extract_strings.py` 提取全部会进 gettext 的字符串 —— 包括
   **表单/模型 XML 的 label / help / hint / ValidationMessage**
   （它们由 `ControllerBase::parseFormNode()` 统一 `gettext()`，最容易被漏掉）；
2. `tools/i18n_translate.py` 生成标准 `locales/zh_CN.po`，并**双向严格校验**：
   每条 msgid 必须真实存在于源码中，且**不得覆盖核心已有译文**；
3. `tools/mo_editor.py` 用纯 Python 读写 `.mo`（无 gettext 工具链也能合并），
   合并后校验 + `diff-core` 确认「只增不改」；
4. `tools/i18n.ps1` / `scripts/i18n_apply.sh`：备份 → 合并 → 校验 → 重启 WebGUI，支持 `-Rollback`。

**同时修掉一个真问题**：`Safety.php` 里 7 处跨行字符串拼接（`'长句 A ' .\n '长句 B'`）
让 `gettext()` 无法提取整句 → 页面上的风险详情一直是英文。
已把它们并为单字面量（`tools/join_php_strings.py`，带 dry-run 与引号计数自检）。

**结果**：

| 指标 | 值 |
|---|---|
| 插件字符串 | 174 |
| 核心已有译文（复用，不重复维护） | 28 |
| 本次补充词条 | **146** |
| 覆盖核心译文 | **0** |
| .mo 词条总数 | 13010 → **13156** |
| 生效范围 | 概览 / 设置 / 订阅 / 日志 四页 + 表单标签 + 帮助文本 + 风险详情 |

> 生效需要**重启 WebGUI**：php-cgi 会在进程内缓存 gettext 词库；
> 且 WebGUI 用的是 `/usr/local/etc/lighttpd_webgui/lighttpd.conf` 那个实例，
> 必须用 `/usr/local/etc/rc.restart_webgui`（`service lighttpd` 管的是另一个实例）。
>
> 注意：`OPNsense.mo` 属于基础系统，**系统升级可能覆盖它**；
> 届时重新执行 `tools/i18n.ps1` 即可（备份在 `/usr/local/opnsense/_bak/os-mihomo-i18n/`）。

中文界面截图：

![设置页（中文）](screenshots/08-settings-zh_CN.png)

![概览（中文）](screenshots/09-overview-zh_CN.png)

---

## 14. 附录：命令速查

```sh
# ---- 本机 ----
.\tools\deploy.ps1 [-WithBinary]          # 安全部署（不动网络配置）
.\tools\webtest.ps1 [-Post]               # 端到端验证
.\tools\rollback_drill.ps1                # 回滚演练（两阶段）
.\tools\i18n.ps1 [-Rollback|-Status]      # 应用/回滚中文词条
.\tools\remote.ps1 -Cmd "<命令>"           # 远端执行
.\tools\remote.ps1 -Script .\scripts\xxx.sh [-ScriptArgs "参数"]
.\tools\remote.ps1 -Pull /var/log/mihomo.log -PullTo .\refs\
python tools\sanitize.py --write          # 去 BOM / 统一 LF

# ---- 设备 ----
sh /usr/local/opnsense/scripts/mihomo/snapshot_state.sh   # 状态指纹
configctl mihomo status|config-current|env-get|log-tail|log-clear|set-enabled
ls -1 /usr/local/opnsense/_bak/os-mihomo/                 # 部署备份集
ls -1 /usr/local/opnsense/_bak/os-mihomo-i18n/            # 词库备份
/usr/local/etc/rc.restart_webgui                          # 重启 WebGUI（改词库/改视图后）
```

---

**报告完** — 如需继续（i18n、opt-in 化 post-install、历史曲线），见 `TODO.md` 的 P8 与 §11。
