# AGENTS.md — os-mihomo WebUI 二次开发（长线任务手册）

> 本文件是本仓库的**唯一协作信源**：任务边界、目录约定、工作流程、验收标准、状态看板。
> 任何 agent / 协作者在动手前必须先读完本文件；每次工作结束必须更新「状态看板」与 `logs/`。

---

## 1. 任务目标

把上游 `Opnwall/OPNsense-repo` 里的 `src/os-mihomo` 插件（OPNsense 的 mihomo/Clash.Meta 集成）
**拷贝过来并二次开发其 WebUI**：

> 将其以 **OPNsense WebGUI 原生美术风格**完美嵌入 OPNsense，而不是另起 HTTP 服务器来展示 WebUI。

含义（判定标准）：

1. 所有页面必须由 **OPNsense 自身的 MVC 框架**（Phalcon + Volt + Bootstrap 3 + opnsense 主题）渲染，
   入口是 `/ui/mihomo/*`，数据接口是 `/api/mihomo/*`。
2. 页面结构必须使用 OPNsense 惯用元素：`nav-tabs` / `content-box` / `base_form` 局部模板 /
   `UIBootgrid` 表格 / `SimpleActionButton` / `updateServiceControlUI` / `lang._()` 国际化 / `fa` 图标。
3. **禁止** iframe 嵌入 zashboard/yacd/metacubexd 之类第三方面板，
   **禁止**要求浏览器直连 mihomo 的 `:9090` 外部控制器；
   控制器的数据一律由 **服务端 PHP（loopback + secret）** 代理后以 OPNsense API 形式吐给浏览器。
4. 保留并兼容上游的服务端资产（mihomo 内核、rc.d、subscription 脚本、configd actions）。

## 2. 绝对红线（安全约束）

> 目标设备是一台**正在服务真实网络**的 OPNsense 路由器（`192.168.1.1`）。破坏它 = 全屋断网。

- ❌ **禁止**修改防火墙规则、NAT、接口、路由表、网关、DHCP、Unbound/DNS 配置。
- ❌ **禁止**执行上游 `packaging/freebsd/+POST_INSTALL`（它会改 `config.xml`、加 TUN 接口、加防火墙放行规则、改 Unbound 转发）。
- ❌ **禁止**执行 `service mihomo start`（默认配置 `tun.auto-route: true` 会劫持全局路由）。
- ❌ **禁止** `configctl filter reload` / `unbound restart` / `pfctl` 写操作。
- ⚠️ **受控例外**：通过 OPNsense 原生模型机制写入**仅限本插件自己的** `<OPNsense><mihomo>` 设置节点
  （由 `/ui/mihomo/settings` 的「Apply」触发，这是 OPNsense 插件持久化设置的标准方式，且不参与网络行为）。
  执行前必须：(1) 备份 `/conf/config.xml`；(2) 写后 diff 证明除该节点外无任何变化；(3) 记录到 `logs/`。
  **除该节点外的任何 config.xml 修改仍然严格禁止**（防火墙/NAT/接口/路由/DNS/DHCP 一律只读）。
- ✅ 允许：写 `/usr/local/opnsense/mvc/**`、`/usr/local/www/mihomo*.php`、`/usr/local/etc/mihomo/**`、
  `/usr/local/etc/rc.d/mihomo`、`/usr/local/opnsense/scripts/mihomo/**`、`/usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf`、
  `/var/lib/php/tmp/*cache*`（菜单/ACL 缓存）、重启 `webgui`/`configd`。
- ✅ mihomo 内核只允许以**隔离 demo 配置**（无 tun、无 dns hijack、`allow-lan:false`、控制器绑 `127.0.0.1`）手工前台启动用于 UI 取证。
- ✅ 服务默认 **不 enable**（`/etc/rc.conf.d/mihomo` → `mihomo_enable="NO"`），避免重启后自动劫持网络。

任何越界操作前，必须写进 `logs/` 并说明理由；默认答案是「不做」。

## 3. 目标环境

| 项 | 值 |
|---|---|
| 设备 | OPNsense 26.7.7 (amd64)，FreeBSD 15.1-RELEASE-p4，PHP 8.5.11 |
| 地址 | `root@192.168.1.1` / `https://192.168.1.1`（密码见对话，不入库、不写进文件） |
| SSH | 已配置密钥 `~/.ssh/opn_ed25519`（本机）→ `/root/.ssh/authorized_keys`（设备） |
| 现状 | **os-mihomo 未安装**；已装 `os-ddns-go`、`os-ttyd`（同作者、纯 legacy `.php` 页面） |
| 菜单锚点 | `VPN → Proxy Suite → Mihomo`（与上游 README 一致） |

## 4. 目录约定

> 重要：**仓库根目录 = 插件树本身**（与上游 `Opnwall/OPNsense-repo` 的 `src/os-mihomo/` 一一对应）。
> 这是用户既有的布局（2026-10-01 拷贝完成，内容与上游逐字节一致，仅行尾为 CRLF；本仓库已统一为 LF）。
> 开发时直接在根目录的 `src/`、`packaging/` 上改，**不要**再套一层 `src/os-mihomo/`。

```
os-mihomo/                      ← ★ 插件仓库根（= 上游 src/os-mihomo 的内容）
├── AGENTS.md                   ← 本文件（唯一信源）
├── TODO.md                     ← 状态看板（每轮必须更新）
├── .gitignore / .gitattributes ← 忽略规则 / 行尾强制 LF
├── Makefile, build.sh          ← 上游打包链路（make package → dist/os-mihomo.pkg）
├── README.md / README.US.md    ← 中文/英文说明（本仓库会重写）
├── packaging/freebsd/…         ← pkg 元数据与安装脚本
├── src/{etc,usr}/…             ← ★ 交付物：安装路径镜像
│   └── usr/local/opnsense/mvc/app/{models,controllers,views}/OPNsense/Mihomo/  ← 本次二次开发核心
├── images/                     ← 上游截图（保留）
│
├── scripts/                    ← 部署/校验/取证脚本（幂等、可回滚）
│   ├── deploy.sh               部署到设备（安全模式，不碰防火墙/DNS/路由）
│   ├── rollback.sh             从备份回滚
│   ├── verify_remote.sh        远端体检
│   └── dump_*.sh               参考资料导出
├── tools/remote.ps1            ← 本机远程执行/传输封装（OpenSSH + 密钥）
├── docs/                       ← 设计文档、验收报告（含真实截图）
│   ├── report.md               ← ★ 最终交付文档（含截图）
│   ├── design.md
│   └── screenshots/            ← agent-browser / 远端取证截图
├── logs/                       ← 工作日志（.gitignore，不入库）
├── refs/                       ← 从设备导出的参考实现（.gitignore，不入库）
└── upstream/                   ← 上游仓库克隆（.gitignore，只读参考）
```

## 5. 交付物清单（Definition of Done）

| # | 交付物 | 判定方式 |
|---|---|---|
| D1 | 上游源码拷贝入库并留档 | `git log` 可追溯；`src/os-mihomo` 完整 |
| D2 | 原生 MVC WebUI：Dashboard / Settings / Subscription / Log | 设备上 `/ui/mihomo/*` 4 个页面可访问，无 PHP 报错 |
| D3 | 仪表盘数据全部经服务端代理（浏览器不直连 :9090） | 页面源码中无 `:9090`；`api/mihomo/dashboard/*` 有数据 |
| D4 | 无 iframe / 无第三方面板 JS | 页面源码 grep 无 `iframe`、无 `zashboard` |
| D5 | 视觉风格与 OPNsense 一致 | agent-browser 截图 + 与 Unbound/Monit 页面对照 |
| D6 | 不触碰防火墙/DNS/路由，服务默认不 enable | `config.xml` diff 为空；`pfctl -sr` 无新增；`/etc/rc.conf.d/mihomo` = NO |
| D7 | 全流程可回滚 | `scripts/rollback.sh` 可用；部署前备份清单存在 |
| D8 | 文档 | `docs/report.md` 含真实截图与操作步骤；AGENTS.md/TODO.md 更新 |

## 6. 工作流（每轮迭代）

1. **读**：`AGENTS.md` → `TODO.md` → 最近一条 `logs/*.md`。
2. **改**：本地改 `src/os-mihomo/`（禁止直接改设备上的文件，一律经 `scripts/deploy.sh` 推送）。
3. **部署**：`powershell -File tools/remote.ps1 -Script scripts/deploy.sh`（幂等、先备份）。
4. **验证**：
   - 语法：远端 `php -l` 所有改动文件；
   - 页面：`curl -k -u` 或 agent-browser 登录实拍；
   - 日志：`/var/log/lighttpd/*`、`/var/lib/php/tmp/PHP_errors.log`、`/tmp/`。
5. **提交**：`git add -A && git commit`，commit message 用 `feat/fix/docs/chore(scope): 描述`。
   每个可工作状态都必须可 `git checkout` 回退。
6. **记录**：追加 `logs/YYYY-MM-DD-*.md`（时间、动作、命令、结果、下一步），并更新 `TODO.md`。

## 7. 状态看板

见 `TODO.md`（唯一权威）。当前阶段：**P3 实现 MVC WebUI**。

## 8. 版本

- 上游基线：`os-mihomo 1.0.4`（mihomo 内核 `1.19.31-vincent`）
- 本仓库版本：`1.1.0`（二次开发：原生 MVC WebUI）
