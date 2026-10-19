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
| P12-3 | 可选：DNS 交给 mihomo（NAT 53→1053）、IPv6、按端口/目标细分 | [~] |
| P19 | DNS 状态页（只读）：mihomo DNS / 53 劫持 / 各接口客户端去向 | [x] |

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
- [x] **绑定/解绑双向对账**（用户澄清：绑定对象是**物理接口**）：加绑/解绑/全部解绑清理网关与接口块/重新绑定，全部经实测；写后安全自检在没有 route-to 时自动回滚
- [x] 截图：`docs/screenshots/13-routing-bind-unbind.png`

## P14 功能改进（本轮）

- [x] ② 内网流量不绕 mihomo：每个绑定接口加「内网直达」规则（无网关），排在策略路由之前
- [x] ④ 订阅自动更新：设置页开关 + 间隔 → 写核心 Cron 模型（command = mihomo sub-update），取消即删除
- [x] **修正**：策略路由此前写进旧版根 <filter>，被接口默认放行规则抢先（Evaluations=0）→ 改为核心防火墙模块的**浮动规则**（prio_group=200000，先于接口规则）→ 实测 route-to 行号 70 < 默认放行 71 ✅
- [x] 自检脚本的日志解析同时接受 IP 与域名；弹窗统一 HTML 实体解码

## P19 DNS 状态页（本轮，只读）

- [x] 设置页新增第 2 个标签「DNS 状态」：`GET /api/mihomo/settings/dns_status`
- [x] 汇总：DNS 模块 / 监听地址 / enhanced-mode / IPv6 / TUN / 服务状态 / 53 劫持覆盖（UDP、TCP）/ Unbound / 上游策略 / respect-rules
- [x] 逐接口表：接口、地址、策略路由、Unbound 是否监听、客户端 DNS 去向（mihomo / Unbound / 未应用 / 手动 / 无）、说明
- [x] 告警：只劫持 UDP 53、TUN/服务/DNS 关闭、Unbound 与绑定接口重叠、手动策略路由、未配置 nameserver-policy
- [x] 设备实测（只读）：`lan/opt1 → Unbound`，`opt2/LanUS → mihomo (TUN)`；当前 `dns-hijack=["0.0.0.0:53"]` → **TCP DNS 未覆盖**
- [x] 不新增/修改防火墙、NAT、DHCP、Unbound、路由；不写 config.yaml
- [x] zh_CN 新增 38 条词条（只增不改，核心译文 0 覆盖）
- [x] 用户确认后执行 `scripts/dns_tcp_hijack.sh`：运行中的 `config.yaml` → `tun.dns-hijack` 补 `any:53 + tcp://any:53`
      （`mihomo -t` 通过，备份 `config.yaml.bak.20261019_225744`，服务重启后运行态 `coverage=udp+tcp`）；
      订阅模板本来就有这两条，无需改

## P12-3 可选（待确认）

- [x] DNS 现状可视化：设置页「DNS 状态」（只读，见 P19）
- [ ] DNS 交给 mihomo：被策略路由接口的 NAT 重定向（53 → 127.0.0.1:1053）——写错会影响整段解析，需单独确认
- [x] TCP DNS 覆盖：运行配置与订阅模板均已是 `any:53 + tcp://any:53`（脚本 `scripts/dns_tcp_hijack.sh`，幂等）
- [ ] IPv6 的对应处理（TUN v6 + 独立规则）
- [ ] 按端口/目标的更细粒度分流；把策略路由导出成可审计的 pf 片段

## P13 功能改进（已完成三项）

- [x] ① 绑定自检：临时主机路由 + 源地址绑定 → 回报出口 IP / 命中规则 / 出口组（新脚本 selftest.php + 按钮）
- [x] ③ 配置历史与还原：备份列表 + 逐行 diff + 一键恢复（新动作 config-restore）
- [x] ⑥ 域名嗅探：受管键（8 个，含嗅探端口表）+ 设置页开关；**自检证明不做它「仅国外」分流不成立**
- [x] 事故记录：直接改写设备 config.yaml 导致重复键（已还原）；restore 误选旧备份（已用自动备份撤回）

## P18 修「策略只能加/删不能改」+ 每项「不修改」开关（本轮）

- [x] **修策略行编辑打不开**：框架的 `setFormData()` 在 `<select>` 绑到**纯字符串**时抛
      `TypeError: Cannot use 'in' operator to search for 'length' in opt2` —— 异常中断整个对话框填充，
      模态框压根不显示（新增能用是因为空值走的是另一条分支，所以"只能加/删不能改"）
      → `get_rule` 在**返回给对话框的数据**里把 interface/target 转成 `{值:{value,selected}}`（模型仍是 TextField）
- [x] 顺手删掉路由页里为绕开这个坑写的一堆 JS（fillSelect/refreshSelects/optionCache/show.bs.modal）
- [x] **每项「不修改」开关**（设置页）：默认全部勾着 = 插件一项都不写；取消勾 = 这一项由页面写入
      - 语义统一：config.yaml / rc.conf.d（开机自启）/ 环境文件（订阅凭据）/ Cron（自动更新）都一样
      - 状态存模型新字段 `mihomo.managed`（允许写入的字段 id，逗号分隔），跟着表单一起提交
      - 勾着的行控件禁用变灰（底部那段说明 + 两个快捷按钮 + 「将写入」实时状态按用户要求随后去掉）
      - 「配置对照」里带「不修改」标记，解释"页面和文件不一致是正常的"
- [x] `Config::selectManagedKeys()` 改成按「不修改」开关挑选（一个键多字段 / 一个字段多键都覆盖）
- [x] 回归测试第 15 节重写（11 条断言）；五个页面 0 报错；实测：勾着 = 文件 md5 不变、只开 MTU 一项 = 只写 MTU
- [x] **「不修改」复选框换成小锁**：每行标签末尾一枚图标（合上=不修改、打开=由插件写、图钉=固定值），
      颜色跟随主题、悬停有提示；删掉底部那句旧提示与自写的禁用配色；真机深/浅色都合身
- [x] **仓库里的明文口令清零**：66 个 .sh + 1 个 .ps1 改成从 `OPN_PW` 或第一个参数取口令
      （`tools/p22_scrub_secret.py`），并重写 git 历史去掉旧提交里的明文
- [x] **不是每项都要「不修改」**：`config.yaml` 的键才有勾；插件自己的状态（开机自启/订阅/自动更新）
      不给勾（始终同步）；**设备名称/协议栈写死**（页面只读 + 小灰标「固定」，写配置时用常量）
- [x] 三处刷屏提示改为只在变化时说话（rc.conf.d / 订阅 env / Cron）；删除没生效的「更新后重启」复选框
- [x] 回归测试第 15 节扩到 22 条断言（含写死项与兜底清单），0 失败
- [x] **对照页精简**：去掉表格上方的说明段落与全部提示框（Inspector::report 不再生成 notes，
      10 条词条清理）；页面只留三项对照表 + 刷新按钮
- [x] 浏览器实测：行编辑对话框正常打开（接口/规则范围/出口/防火墙规则四个下拉全部带正确选中值）、
      改值保存后 config.xml 生效、再改回来；设置页 23 条开关（控制器地址/端口共用一个）、
      取消勾选后输入框可编辑且提示「将写入：启用 mihomo」，应用后提示"所有项都是「不修改」，配置文件保持原样"

## P17 修报错 + IPv6 选项 + 「只写入我改过的项」（上一轮）

- [x] **修首绑报错**：浮动规则先于网关创建 → 防火墙模型校验报「网关无效」
      → 改成三段式（① 先建接口+网关 ② 再写浮动规则 ③ reload + 自检；自检不过自动撤销规则）
- [x] **修 bypass 规则撞名**：描述只带目标接口，两个绑定接口会生成同名规则被去重删掉 → 改成 `来源 -> 目标`
- [x] **修 configd 吞消息**：脚本非零退出时 configd 丢弃 stdout（WebGUI 只看到"(no output)"）
      → 第三段改成 `status: failed` + exit 0，真实原因能显示出来
- [x] **修部署 lint 空档**：`find` 表达式写错导致 `scripts/mihomo/*.php` 从不做 `php -l`（我的解析错误因此溜过去）
      → 修好后 32 个 PHP 文件全部检查
- [x] **设置页新增 IPv6 选项**：「IPv6 处理」(`ipv6`)、「DNS 返回 IPv6」(`dns.ipv6`)，均纳入受管键
- [x] **「应用方式」默认只写改动过的项**：页面快照 + 实时"将写入：X、Y"提示；未改动项即使与文件不一致也不覆盖
- [x] 体检的 IPv6 提示改为指向新的设置开关；配置对照文案改成说人话
- [x] 配置对照「运行中」栏补全：协议栈/嗅探/控制器地址，密钥与 DNS 用探针判断（内核不报告的只剩严格路由、DNS 模式）
- [x] 策略区块缩进沿用文件里已有规则的缩进（之前可能多两格）
- [x] 实测：lan + opt2 绑定成功；pf 顺序 route-to(69) < 默认放行(73)；自检命中受管规则（opt2 → SrcIPCIDR，lan → AND+GeoSite）；
      LanDirect 0 route-to；默认路由未变；出网 200；回归测试 0 失败

## P16 配置对照（本轮）

- [x] `Inspector.php`：只读三方对照（页面值 / 文件值 / 运行值）+ 提示（手写配置、受管区块、IPv6、不一致）
- [x] `GET /api/mihomo/settings/inspect` + 设置页第三个标签「配置对照」（项目/页面/文件/运行 四列）
- [x] 密钥永不明文（只显示"已设置/空"）；只在运行态出现的键标「仅运行值」不参与判定
- [x] 体检新增 IPv6 提示（TUN 只有 v4 → v6 绕过 mihomo）
- [x] 回归测试第 14 节（纯函数 + 对照表），实测 **0 失败**
- [x] 实测：18 行、不一致 0；五页 0 PHP 报错；默认路由未变、LanDirect 无 route-to、出网 200

## P15 界面细节修复 + 配置说明（本轮）

- [x] 路由策略行编辑对话框：接口/代理组下拉**没法选**（bootstrap-select 没 refresh）
- [x] 首页体检横幅只显示一个**空框**（条目用了 text-* 撞色）→ 改 inherit + 图标分级 + 按级别换标题
- [x] 体检「控制器未设密钥」在**只监听回环**时不再报危险（降为 info），对网络开放且无密钥才是 danger
- [x] 接口下拉排除 lo0；浮动规则目标网段同样排除回环
- [x] 路由表为空时给一行提示（还没有绑定接口 → 添加 → 应用）
- [x] 订阅页常驻警告：更新订阅会用模板整份重写 config.yaml（附备份文件名）
- [x] 新增文档 `docs/config-guide.md`（YAML vs WebUI：交叉/重复/优先级/如何确认此刻真实配置）
- [x] 新增只读脚本 `scripts/config_truth.sh`（WebUI 值 / 文件值 / 运行值 / 网络侧 四段对照）
- [x] 新词条 6 条已进 zh_CN（共 210 条）；五个页面实测 0 PHP 报错

## P14 待做（按建议清单）

- [ ] ② 内网流量不绕 mihomo（绑定接口的 LAN↔LAN / 访问路由器本身不走 TUN）
- [ ] ④ 订阅自动更新（写 OPNsense 原生 Cron）
- [ ] ⑮ +POST_INSTALL 改为 opt-in（分发质量）
- [ ] ⑤ ⑦ ⑧ ⑨ ⑩ ⑪ ⑫ ⑬ ⑭ ⑯ 见对话清单

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
