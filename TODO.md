# TODO / 状态看板

> 每轮工作结束必须更新本文件。图例：`[ ]` 待办 `[~]` 进行中 `[x]` 完成 `[!]` 阻塞 `[-]` 取消

## 阶段总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 侦察：上游源码、目标设备、OPNsense MVC 惯例 | [x] |
| P1 | 工程基建：git、AGENTS.md、远程工具、备份/回滚 | [x] |
| P2 | 设计：页面/接口/数据流、MVC 目录规划 | [x] |
| P3 | 实现：模型 + 控制器 + API | [x] |
| P4 | 实现：Volt 视图（4 页面，OPNsense 原生风格） | [x] |
| P5 | 部署到设备 + 语法/接口验证 | [x] |
| P6 | 视觉验收（agent-browser 截图、与核心页面对照） | [x] |
| P7 | 报告：docs/report.md（含真实截图） | [x] |
| P8 | 收尾：打包脚本、README、回滚演练 | [x] |
| P9 | 修复：表单布尔控件、Apply 落盘链路、补丁器最小化 | [x] |
| P10 | 项目定位与分发格式：标准 OPNsense 插件包 + 插件管理器可管理 + README 重写 | [x] |
| P11 | 上手试用：安全启动（TUN 关闭）+ 修复服务控制缺陷 | [x] |
| P12-1 | 路由策略页（原生表格 + 受管区块 + 预览/应用/状态）+ 真实节点实测 | [x] |
| P12-2 | 路由策略网络侧同步（接口/网关/策略路由 + 弹窗确认 + 回滚） | [x] |
| P12-3 | 可选：DNS 交给 mihomo（NAT 53→1053）、IPv6、按端口/目标细分 | [ ] |

## 交付结果（2026-10-18）

- 设备最终状态：插件已安装、4 个页面可用、**服务未启用（`mihomo_enable="NO"`）**、**零网络改动**
- 网络指纹（pf/NAT/路由/Unbound）与部署前**逐字节一致**
- 端到端验证：4 页面 200、旧链接 302、20 个 API 200、未授权 302、语法 0 错误
- 截图：`docs/screenshots/` 11 张（含核心页面对照）
- 提交：`8bfe014`（基线）→ `b21013a`（MVC 重写）→ `fa63bbb`（UI 精修）

## P8 收尾（已完成）

- [x] README 重写（指向新 UI，移除"浏览器连 :9090"的旧姿势）
- [x] 版本号提升到 1.1.0（`Makefile` / `version/mihomo`）
- [x] 部署/回滚/体检/取证脚本齐备（`scripts/`、`tools/`）
- [x] `make package` 实机跑通：`os-mihomo-1.1.0.pkg`（26.9 MB，native ABI，sha256 `2faa09a9…`），
      并修掉 `subscription_run.sh` 在包里权限是 0644 的打包缺陷
- [x] 回滚演练实跑：41 文件回滚 → 与备份逐字节一致 → 重新部署 → 与回滚前 100% 一致，**0 failures**
- [x] 补 `zh_CN` 翻译：146 条词条，四页全中文，覆盖核心译文 0 条（见报告 §13.3）

## P10 项目定位与分发格式（已完成）

- [x] **定位**：README 重写为**独立新项目**（不再是"上游的新版本"），中英文各一份
- [x] **标准插件包**：`ABI` 默认 `native`；清单补 `licenses` 与
      `annotations{repo_type:"binary", repository:"os-mihomo"}`（与同类插件 `os-ttyd`/`os-ddns-go` 的格式对齐）
- [x] **插件仓库**：`scripts/make_repo.sh` + `make repo` → `dist/repo/<ABI>/{meta.conf,meta,data.pkg,packagesite.pkg,os-mihomo-<ver>.pkg,os-mihomo.conf}`
- [x] **插件管理器验证**：临时启用本机仓库后，插件页数据源 `configctl firmware remote` 出现
      `os-mihomo|||1.1.0|||…|||os-mihomo|||opnsense/os-mihomo`，且 `pkg version -t 1.1.0 1.0.4` → `>`（视为升级）
- [x] 验证后复原：仓库配置改回 `enabled: no`、删除该仓库的本地缓存、`pkg search` 只剩上游 1.0.4
- [x] 目标机保留物：`/usr/local/opnsense/_bak/os-mihomo-repo/<ABI>/`（仓库）+ `/usr/local/etc/pkg/repos/os-mihomo.conf`（默认不启用）

## P11 上手试用（已完成）

- [x] 安全启动：`tun.enable: true → false`（走插件自己的 import→set→apply，diff 恰好 1 行），服务已运行
- [x] 服务控制缺陷 1：configd 动作用 `start`，`rcvar=NO` 时被 `/etc/rc.subr` 拒绝 → 改用 `onestart/onestop/onerestart`
- [x] 服务控制缺陷 2：基类 `statusAction()` 在未启用时返回 `disabled`，核心 JS 对 `disabled` 不渲染按钮
      → 覆盖 `statusAction()` 归一为 `stopped`（+ `boot_enabled` 字段）
- [x] 实测：界面 start/restart 均生效（pid 变化），控制器 alive、7 个代理分组、9 个监听全在 127.0.0.1
- [x] 安全复核：pf/NAT/路由/Unbound 指纹与基线逐字节一致；无 TUN 接口；开机自启仍为 NO
- [x] 截图：`docs/screenshots/10-trial-live-dashboard.png`
- [ ] **待用户确认**：要跑透明代理还需加 `tun_mihomo` 接口 + 防火墙放行（可选 Unbound 转发 1053）——属网络配置变更，需明确同意

## P12-1 路由策略（已完成）

- [x] 模型 `policyRouting.rule`（ArrayField）+ 对话框表单 + 页面控制器 + API 控制器（核心 CRUD 约定）
- [x] 视图：`base_bootgrid_table` + `base_dialog` + 底部应用按钮 + 只读"当前生效状态"表（全中文）
- [x] `policy_apply.php`（configd/root）：受管区块写入 `config.yaml` **与订阅模板**，`mihomo -t` 校验 + 时间戳备份 + 原子替换 + 幂等
- [x] 预览/应用前弹窗列出将写入的规则与目标文件；应用后返回 diff
- [x] 回归测试：受管区块（幂等/替换/移除/缩进/插入位置）、规则渲染（仅国外/全部/直连/跳过）、
      分组名解析（块风格 + **flow 风格**）、`mihomo -t` 接受合法块并拒绝不存在的分组 —— **0 失败**
- [x] 真实节点实测（lan 侧）：日志显示 `match AND(((SrcIPCIDR,192.168.1.0/24) && (GeoSite,geolocation-!cn))) using 🇺🇸 United States[01]`，
      出口 IP 从 `188.253.115.13`（环回/HK）变为 `5.34.216.210`（LAN 源/美国组），国内目标 DIRECT
- [x] LanDirect 零影响：config.yaml 无该网段、无监听、无策略路由；pf/NAT/路由/Unbound 指纹与基线逐字节一致
- [x] 截图：`docs/screenshots/11-routing-policy.png`

## P12-2 路由策略 · 网络侧同步（已完成）

- [x] 实测 TUN 地址形态：`198.18.0.1/30`（auto-route 关闭，只多一条 /30 直连路由）→ 网关用对端 `198.18.0.2`
- [x] `policy_net.php`（configd/root）：`check` / `plan` / `apply` / `rollback [备份文件]`
      —— 只增不改 + config.xml 时间戳备份 + 文本级插入 + XML 自检 + **写后安全自检（无 route-to … tun_mihomo 就自动回滚）**
- [x] config.xml：`opt3 -> tun_mihomo` 接口 + `MIHOMO_TUN` 网关（monitor_disable=1）+ `lan` 上的 `pass + gateway=MIHOMO_TUN` 规则
- [x] 页面：OPNsense 网络侧状态表 + 「同步 / 预览变更 / 回滚」+ 弹窗确认（列出全部变更与备份说明）
- [x] 实测：pf 生成 `pass in quick on igb0 route-to (tun_mihomo 198.18.0.2)`；经 TUN 的出口 IP = 188.253.115.13（代理）；幂等（二次同步 nothing changed）
- [x] LanDirect 零影响：igb4 上 0 条 route-to、10 条既有 pass 规则未变、opt1 仍是 igb4/LanDirect、默认路由与 Unbound 指纹未变、本机出网 200
- [x] 体检横幅新增告警：策略路由生效的接口，在 mihomo 停止期间会断网
- [x] 事故与修复：①接口块误插到 WebGUI 的 `<interfaces>`（已回滚 + 改为识别根接口段 + 加自动回滚安全网）②脚本内 `service configd restart` 自杀（已移除）③规则去重正则脆弱（改为按 rule 块解析）
- [x] 截图：`docs/screenshots/12-routing-opnsense-side.png`

## P12-3 可选（待确认）

- [ ] DNS 交给 mihomo：被策略路由接口的 NAT 重定向（53 → 127.0.0.1:1053）——写错会影响整段解析，需单独确认
- [ ] IPv6 的对应处理（TUN v6 + 独立规则）
- [ ] 按端口/目标的更细粒度分流；把策略路由导出成可审计的 pf 片段

## 后续可选（不在本轮范围）

- [ ] 把 146 条词条提交到 OPNsense 官方翻译平台（translate.opnsense.org），
      以便随基础系统分发、避免每次系统升级后重打 `.mo`
- [ ] 仪表盘历史曲线（RRD 或环形缓冲）
- [ ] 把 demo 实例改造成正式的"单机自测模式"（写进 README）
- [ ] 上游 `+POST_INSTALL` 改为显式 opt-in（当前与上游行为一致，已在 README/报告显著警示）

## 风险与决策记录

| # | 风险/决策 | 结论 |
|---|---|---|
| R1 | 上游 +POST_INSTALL 会改 config.xml/防火墙/Unbound | **不执行**；部署脚本只铺文件，服务默认不 enable |
| R2 | 默认 config.yaml `tun.auto-route: true` + 占位节点 | 服务默认关闭；仪表盘红色安全体检；文档三处警告；只用隔离 demo 实例取证 |
| R3 | `external-controller: 0.0.0.0:9090` 暴露 | 新 UI 全走 loopback 代理；设置页可改为 `127.0.0.1`；文档建议 |
| R4 | 菜单/ACL 缓存导致新页面不出现 | 部署脚本清缓存；且必须 `service configd restart` 才会重载 actions.d |
| R5 | 浏览器直连 :9090 的旧习惯 | README/报告说明新姿势；控制台仍可用但不再是必需 |
| R6 | 主题对所有输入控件加 `max-width: 348px` | 宽文本框内联覆盖 `max-width: 100%` |
| R7 | 侧边栏只支持 3 层菜单 | 菜单结构改为 `VPN → Proxy Suite → 4 项` |
| R8 | PowerShell 5.1 的 ANSI 默认编码损坏 UTF-8 脚本 | `tools/sanitize.py` + `fix_ps1_bom.py` + 传输后 sha256 校验 |
| R9 | 脚本自我调用导致进程风暴（已发生，见报告 §10） | `tools/remote.ps1` 增加"含 `__remote.sh` 即拒跑"护栏 |
| R10 | 表单布尔字段用 `<type>boolean</type>`，`base_form` 不渲染 | 改为 `<type>checkbox</type>`（核心对 base_form 都这么写）；已实测 7 个开关全部正常 |
| R11 | 误判"上游保存配置/日志必然失效" | **已更正**：WebGUI 的 PHP 以 root 运行，上游那些写法可用；文档与日志均已修正 |
| R12 | Apply 会重写受管行从而丢掉行尾注释 | 补丁器改为"值相同不动 + 改动时保留行尾注释"，Apply 实测只产生 1 行 diff |
| R13 | 插件要"可被 OPNsense 自带插件管理器管理" | 光有 `.pkg` 不够：必须是 `os-*` 命名 + native ABI + `annotations.repository`，且由**仓库**提供（固件系统走 `pkg install`）；已补 `make repo` 与仓库配置模板，并实测插件页数据源可见 |
| R14 | `make package` 两次构建哈希不同 | tar 记录 mtime，构建不可复现；文档标注以最后一次产物为准 |
| R15 | 关掉"开机自启"后，界面无法启停服务 | `/etc/rc.subr` 在 `rcvar=NO` 时拒绝 `start`，而 configd 动作正是 `start`（且被拒后仍以 0 退出，界面无任何报错）→ 动作改 `onestart/onestop/onerestart`；"当前启停"与"开机自启"彻底解耦 |
| R16 | 服务未启用时页面右上角没有启停按钮 | 基类 `statusAction()` 返回 `disabled`，核心 JS 只认 `running`/`stopped` → 覆盖归一为 `stopped`，自启状态由 `boot_enabled` 字段与安全横幅表达 |
| R17 | 路由策略表格的 `rule` 节点未声明 `ArrayField` | `addBase/searchBase` 直接 500（`ContainerField::Add()`）；声明为 `<rule type="ArrayField">` 即可（核心 `Route.xml` 同写法） |
| R18 | 用户配置里的代理组是 flow 风格 `- { name: 'X', ... }` | 分组扫描器要同时认块风格与 flow 风格，否则下拉为空并误报"分组不存在" |
| R19 | 回归测试拿线上配置当夹具 | 用户换配置后大量误报 → 固定用仓库随包配置作夹具（`/tmp/mihomo-test/fixture-config.yaml`），测试与线上数据解耦 |
| R20 | config.xml 里有多个同名 `<interfaces>`（WebGUI 段也有） | 插入接口块必须**按"内部含 `<if>` 设备赋值"识别根接口段**，否则会写进 WebGUI 设置；写完自检，且无 `route-to … tun_mihomo` 时自动回滚 |
| R21 | configd 拉起的脚本里不能 `service configd restart` | 等于自杀（输出丢失、后续步骤不执行）→ 移除该调用；`filter reload` 本身会重读 config.xml |
| R22 | 策略路由生效后 mihomo 停止会断网 | 属预期行为；已写入体检横幅与文档；临时绕过 = 把该行改「手动」/禁用，或在 OPNsense 里禁用该规则 |
