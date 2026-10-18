# 设计说明 — os-mihomo 原生 MVC WebUI

## 1. 问题陈述

上游 `os-mihomo 1.0.4` 的 WebUI 是 4 个 **legacy 过程式页面**（`/usr/local/www/mihomo*.php`），
用 `include("head.inc")` 拼 HTML，与 OPNsense 现代表现层（MVC/Volt）脱节：

| 问题 | 证据 | 影响 |
|---|---|---|
| 不是 MVC | 无 `controllers/` `views/`，只有 `www/*.php` | 与 OPNsense 新风格不一致，得不到框架能力（ACL/日志/主题） |
| 手写 CSRF | `$_SESSION['mihomo_service_csrf_token']` | 与框架 `csrfToken` 机制并存，重复造轮子 |
| 手写 i18n | 自建 `proxy_t()` + 解析 `/conf/config.xml` 语言 | 忽略 OPNsense 的 `lang._()` 与 gettext 体系 |
| 手写状态轮询 | `fetch('/mihomo.php?ajax=status')` + `setInterval(2000)` | 不走 `updateServiceControlUI` 标准服务控件 |
| **WebUI 依赖另起 HTTP 服务** | README 让用户访问 `http://LAN_IP:9090/ui`（mihomo 自带 zashboard）；`config.yaml` 的 `external-ui-url` 还会运行时从 GitHub 拉取第三方面板 | 需要浏览器直连 :9090，等于另起 HTTP 服务展示 WebUI |
| 控制器暴露 | `external-controller: 0.0.0.0:9090` + 占位 `secret` | 面板/API 暴露给全网段 |
| 启动无提示 | 默认 `tun.auto-route: true` + 占位节点 | 未配置就启动 → 全网断网 |
| 订阅更新无条件重启服务 | `sub.sh` 结尾 `MIHOMO_SERVICE_CMD="service mihomo restart"` | 新配置有问题也可能触发重启 |

> **实测更正**：本机 WebGUI 的 PHP 实际以 **root** 运行（lighttpd + `mod_fastcgi` + root 起的 `php-cgi`），
> 因此上游用 `exec()` / `fopen()` 的写法**是可用的**，不存在"保存失败/日志空白"的问题。
> 本次仍统一把特权写入改走 **configd**，理由是：可审计（进 syslog）、避免在 PHP 里拼 shell 命令、以及可脱离 Web 环境做回归测试。

## 2. 目标架构

```
浏览器 (OPNsense WebGUI 会话, 有 ACL 保护)
   │  /ui/mihomo/*      ← Volt 视图, Bootstrap3 + opnsense 主题
   │  /api/mihomo/*     ← MVC API (ApiControllerBase 系列)
   ▼
php-fpm (www) ── 只读直读 config.yaml (0644) / 只读 GET
   │
   ├── configd (root)  ← 特权动作：写 config.yaml / 写 rc.conf.d / 读日志 / 跑订阅
   │      └── /usr/local/opnsense/scripts/mihomo/*.{php,sh}
   │
   └── loopback HTTP (127.0.0.1:9090)  ← mihomo external controller REST API
          · GET /version /configs /proxies /connections
          · PUT /proxies/{name}  (选择节点)
          · GET /proxies/{name}/delay (测延迟)
          · PATCH /configs (切 mode / log-level)
          · DELETE /connections[/{id}]
```

**关键点**：浏览器永不直连 `:9090`，也永不加载第三方面板（zashboard/yacd）。
所有实时数据由 PHP 以 loopback + Bearer secret 取回，转成 OPNsense API 形态。

## 3. 页面与接口

| 页面 | 路由 | 控制器 | 视图 | 参照的 OPNsense 页面 |
|---|---|---|---|---|
| 概览/仪表盘 | `/ui/mihomo` | `IndexController` | `index.volt` | Unbound Overview + Monit Status |
| 设置 | `/ui/mihomo/settings` | `SettingsController` | `settings.volt` | Unbound General（`base_form` + 标签页） |
| 订阅 | `/ui/mihomo/subscription` | `SubscriptionController` | `subscription.volt` | Unbound General + 日志页 |
| 日志 | `/ui/mihomo/log` | `LogController` | `log.volt` | Monit Log File |

| API | 方法 | 用途 |
|---|---|---|
| `api/mihomo/service/status` | GET | 服务状态（继承基类，供 `updateServiceControlUI` 用） |
| `api/mihomo/service/{start,stop,restart}` | POST | 服务控制（configd → rc.d/mihomo） |
| `api/mihomo/service/safety` | GET | 安全体检：TUN 接管/占位节点/控制器暴露/配置校验 |
| `api/mihomo/settings/get` `set` | GET/POST | 模型读写（继承 `ApiMutableModelControllerBase`） |
| `api/mihomo/settings/apply` | POST | 把模型写入 `config.yaml`（configd, root, 带备份） |
| `api/mihomo/settings/config/get` `set` `validate` | GET/POST | 原始 YAML 查看/保存/校验 |
| `api/mihomo/dashboard/overview` | GET | 版本/模式/流量累计/连接数/内存 |
| `api/mihomo/dashboard/proxies` | GET | 代理组树 + 延迟 |
| `api/mihomo/dashboard/select_proxy` | POST | 选择节点 |
| `api/mihomo/dashboard/test_delay` | POST | 节点延迟测速 |
| `api/mihomo/dashboard/set_mode` | POST | 切换 rule/global/direct |
| `api/mihomo/dashboard/connections` | GET | 连接列表（前端分页/搜索） |
| `api/mihomo/dashboard/close_connection` | POST | 关闭单条/全部连接 |
| `api/mihomo/subscription/get` `save` `run` `log` `clear_log` | 混合 | 订阅 URL/密钥、执行、日志 |
| `api/mihomo/log/tail` `clear` | GET/POST | 日志读取/清空 |

## 4. 权限与安全模型

- **读写分离**：`config.yaml`（0644）由 Web 进程只读；特权写入（配置/env/rc.conf.d/日志）统一经 **configd（root）**。
  实测本机 WebGUI 的 PHP 本身就是 root（lighttpd + `mod_fastcgi` + `php-cgi`），
  走 configd 不是权限所迫，而是为了**可审计（syslog）、避免在 PHP 里拼接 shell、以及可脱离 Web 做回归测试**。
- **写配置的原子性**：随机名临时文件（0600, www）→ configd 校验（`mihomo -t`）→ 备份（`config.yaml.bak.YYYYmmdd_HHMMSS`）→
  `install -m 0644 -o root -g wheel` 落盘。校验不过一律不落盘。
- **参数注入防护**：所有 configd 调用使用 `escapeshellarg()`；临时文件路径白名单前缀 `/tmp/mihomo-`。
- **CSRF**：全部走框架（视图 `{{ security.getToken() }}` / `SimpleActionButton`）。
- **ACL**：`ui/mihomo/*` + `api/mihomo/*` 归入 `VPN: Proxy Suite: Mihomo` 权限项。
- **服务默认禁用**：模型 `general.enabled` 默认 0；`/etc/rc.conf.d/mihomo` 默认 `NO`；
  仪表盘在 TUN 接管 + 占位节点时显示红色风险横幅。

## 5. 兼容性

- 旧链接 `/mihomo.php`、`/mihomo_sub.php`、`/mihomo_logs.php`、`/mihomo_sub_log.php` 保留为 302 跳转页。
- 服务端资产（内核、rc.d、sub.sh、actions）保持上游语义；`actions_mihomo.conf` 仅**新增**动作，不改旧动作。
- `packaging/freebsd/+POST_INSTALL` 的自动改配置行为在本仓库的部署脚本中**不执行**（见 AGENTS.md 红线）。
