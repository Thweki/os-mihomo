# TODO / 状态看板

> 每轮工作结束必须更新本文件。图例：`[ ]` 待办 `[~]` 进行中 `[x]` 完成 `[!]` 阻塞 `[-]` 取消

## 阶段总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 侦察：上游源码、目标设备、OPNsense MVC 惯例 | [x] |
| P1 | 工程基建：git、AGENTS.md、远程工具、备份/回滚 | [x] |
| P2 | 设计：页面/接口/数据流、MVC 目录规划 | [~] |
| P3 | 实现：模型 + 控制器 + API | [ ] |
| P4 | 实现：Volt 视图（4 页面，OPNsense 原生风格） | [ ] |
| P5 | 部署到设备 + 语法/接口验证 | [ ] |
| P6 | 视觉验收（agent-browser 截图、与核心页面对照） | [ ] |
| P7 | 报告：docs/report.md（含真实截图） | [ ] |
| P8 | 收尾：打包脚本、README、回滚演练 | [ ] |

## P0 侦察（已完成）

- [x] 上游 `src/os-mihomo` 1.0.4 源码通读（legacy `www/*.php` 四页 + rc.d + sub.sh + packaging）
- [x] 目标机：OPNsense 26.7.7 / FreeBSD 15.1-p4 / PHP 8.5.11，**未安装 os-mihomo**
- [x] 目标机防火墙/DNS 当前状态快照（用于验收时证明"零改动"）
- [x] OPNsense MVC 惯例取证：Monit / Unbound / layout_partials
- [x] ACL 匹配语义确认（`ui/x/*` 与 `api/x/*` 模式）

## P1 工程基建（已完成）

- [x] `git init` + `.gitignore`（logs/refs/upstream/大文件不入库）
- [x] SSH 密钥免密 + `tools/remote.ps1`（执行/推送/拉取）
- [x] 部署前全量备份策略（`/usr/local/opnsense/_bak/os-mihomo/<ts>/`）

## P2 设计

- [x] 页面规划：Dashboard / Settings / Subscription / Log（+ 旧链接 301 兼容页）
- [x] API 规划：service / settings / dashboard / subscription / log
- [x] 数据流：浏览器 → OPNsense MVC API → loopback `127.0.0.1:9090`（secret 鉴权）
- [x] `docs/design.md`

## P3 实现（后端）

- [ ] `models/OPNsense/Mihomo/Menu/Menu.xml`（VPN → Proxy Suite → Mihomo ▸ 4 项）
- [ ] `models/OPNsense/Mihomo/ACL/ACL.xml`（ui/api 通配）
- [ ] `models/OPNsense/Mihomo/Mihomo.xml` + `Mihomo.php`（设置模型）
- [ ] `controllers/OPNsense/Mihomo/{Index,Settings,Subscription,Log}Controller.php`
- [ ] `controllers/OPNsense/Mihomo/forms/*.xml`
- [ ] `controllers/OPNsense/Mihomo/Api/{Service,Settings,Dashboard,Subscription,Log}Controller.php`
- [ ] `usr/local/opnsense/scripts/mihomo/`（控制器客户端 lib、YAML 键补丁器、日志读取）

## P4 实现（视图）

- [ ] `views/OPNsense/Mihomo/index.volt`（仪表盘：状态/统计/流量图/代理组/连接表）
- [ ] `views/OPNsense/Mihomo/settings.volt`（原生表单 + 配置校验 + 原始配置编辑）
- [ ] `views/OPNsense/Mihomo/subscription.volt`（订阅 URL/密钥 + 执行 + 日志）
- [ ] `views/OPNsense/Mihomo/log.volt`（日志查看/清空，遵循 Monit Log 风格）
- [ ] 旧 `www/mihomo*.php` → 301 到 `/ui/mihomo*`

## P5 部署与功能验证

- [ ] `scripts/deploy.sh`（安全模式：不动 config.xml/unbound/pf，服务不 enable）
- [ ] 远端 `php -l` 全绿
- [ ] 菜单出现、4 页面 200、无 PHP 错误
- [ ] 每个 API 端点 curl 自测（含未授权 403 检查）

## P6 视觉验收

- [ ] agent-browser 登录设备截图：Dashboard / Settings / Subscription / Log
- [ ] 与 OPNsense 核心页面对照（Unbound Overview、Monit Status、System Log）
- [ ] 深色/浅色主题、窄宽度响应式抽查
- [ ] 截图归档 `docs/screenshots/`

## P7 报告

- [ ] `docs/report.md`：目标、架构、实现、截图、验证矩阵、安全边界、回滚、后续建议

## P8 收尾

- [ ] README 重写（安装/使用/升级/卸载，含安全提示）
- [ ] `pkg` 打包链路确认（build.sh 可用，post-install 改为安全默认）
- [ ] 回滚演练（rollback.sh 至少实跑一次）

## 风险与决策记录

| # | 风险/决策 | 结论 |
|---|---|---|
| R1 | 上游 +POST_INSTALL 会改 config.xml/防火墙/Unbound | **不执行**；部署脚本只铺文件 |
| R2 | 默认 config.yaml `tun.auto-route: true` | 服务默认 `enable=NO`；UI 显式风险提示；只用隔离 demo 配置取证 |
| R3 | `external-controller: 0.0.0.0:9090` 暴露 | 新 UI 全走 loopback 代理；文档建议改绑 127.0.0.1（不自动改） |
| R4 | 菜单/ACL 缓存导致新页面不出现 | 部署脚本清理 `/var/lib/php/tmp/opnsense_{menu,acl}_cache.*` |
| R5 | 浏览器直连 :9090 的旧习惯 | 文档说明新姿势；控制台保留但不再是必需 |
