# 路由策略（按接口分流）WebUI —— 设计规格

> 目标：在 **OPNsense 原生界面**里，用一张和「防火墙: 规则」同形态的表格，配置
> **「哪个接口 / 哪些源 → 走哪个代理出网」**；未配置的接口**完全不经过 mihomo**；
> 改动同步到 mihomo 配置与 OPNsense 网络侧配置（防火墙/网关/接口/DNS），
> 同步前**弹窗列出将发生的一切**，并自动备份、可一键回滚。

---

## 1. 结论：为什么"能符合 OPNsense 规范"

| 界面元素 | 用 OPNsense 的什么 | 参照页面 |
|---|---|---|
| 表格（接口/源/出站/描述/命令 列） | `UIBootgrid`（`layout_partials/base_bootgrid_table.volt`） | 防火墙: 规则 |
| 行内编辑对话框 | `forms/policy_rule.xml` + `layout_partials/base_form` + Bootstrap Dialog | 同 |
| 底部「应用」按钮 | `layout_partials/base_apply_button` + 我们自己的 `apply` 端点 | 同 |
| 接口下拉 | 系统已配置接口（config.xml `interfaces`，显示描述名） | 接口配置 |
| 代理组下拉 | 当前 `config.yaml` 的 `proxy-groups` 名字（运行中时优先用 `/proxies`） | — |
| 弹窗确认 | `BootstrapDialog`（`layout_partials/base_dialog`） | 各处 |
| 文案 | `lang._()` / `gettext()` + zh_CN 词条 | 全站 |
| 权限 | 归属现有 ACL `page-mihomo-*`，菜单 `VPN → Proxy Suite → 路由策略` | 菜单规范 |

新增文件（全部落在既有插件目录内，不新增服务、不新增端口）：

```
mvc/app/models/OPNsense/Mihomo/Mihomo.xml              ← 新增 <policyRouting> 节点（Grid 支持）
mvc/app/controllers/OPNsense/Mihomo/forms/policy_rule.xml   ← 对话框字段定义
mvc/app/controllers/OPNsense/Mihomo/Api/RoutingController.php ← search/set/add/del/toggle/preview/apply
mvc/app/controllers/OPNsense/Mihomo/RoutingController.php     ← 页面控制器
mvc/app/views/OPNsense/Mihomo/routing.volt                    ← 页面（表格 + 应用按钮）
opnsense/scripts/mihomo/policy_apply.php                       ← 特权侧：写 config.yaml/模板 + 同步网络侧（root, via configd）
service/conf/actions.d/actions_mihomo.conf                     ← 新增 policy-apply / policy-preview / policy-status 动作
```

## 2. 表格列（对齐「防火墙: 规则」的心智）

| 列 | 含义 | 取值 |
|---|---|---|
| 启用 | 行开关 | on/off |
| 接口 | 哪个 OPNsense 接口（按描述名显示，如 Console / LanDirect / LanUS） | config.xml 中的接口列表 |
| 源 | 默认＝该接口网段，可改成别名/自定义 CIDR | 默认 `192.168.10.0/24` |
| 出站 | 走到哪里 | `不使用 mihomo（直连）` / 具体代理组（🇺🇸美国节点…）/ `按全局规则集` |
| 规则范围 | 该源的匹配范围 | `全部流量` / `仅国外（geolocation-!cn + gfw）` / `自定义规则块` |
| DNS | 该接口的 DNS 是否交给 mihomo（fake-ip） | `mihomo（自动加 NAT 重定向）` / `系统 Unbound` |
| 策略路由 | 是否让插件写防火墙策略路由 | `自动` / `手动（仅 mihomo 侧）` |
| 描述 | 备注 | 文本 |
| 命令 | ✎ 编辑 / 复制 / 删除（UIBootgrid 原生） | — |

表格下方一行只读状态（不点应用也能看，避免误配）：

```
当前生效状态：Console → 直连(未进 mihomo)   LanDirect → 直连(未进 mihomo)   LanUS → 美国节点(策略路由已生效)
```

## 3. Apply 时生成什么

### 3.1 mihomo 侧（安全，属于插件自己的文件，最小 diff + `mihomo -t` 校验）

在 `config.yaml` 的 `rules:` **最前面**插入受管区块（含标记，整块替换 → 幂等）：

```yaml
rules:
  # >>> os-mihomo:policy-routing (managed) >>>
  - AND,((SRC-IP-CIDR,192.168.10.0/24),(GEOSITE,geolocation-!cn)),🇺🇸美国节点
  - AND,((SRC-IP-CIDR,192.168.10.0/24),(GEOSITE,gfw)),🇺🇸美国节点
  # <<< os-mihomo:policy-routing <<<
  # ↓ 以下为用户原有规则，原样保留
  ...
  - MATCH,🌍选择节点
```

* 「全部流量」→ 直接 `SRC-IP-CIDR,<源>,<组>`
* 「仅国外」→ `AND,((SRC-IP-CIDR,<源>),(GEOSITE,geolocation-!cn)),<组>`（+ gfw）
* 「按全局规则集」→ `SUB-RULE,(SRC-IP-CIDR,<源>),<子规则名>`（在 `sub-rules:` 里生成一份带该出口组的规则副本）
* 「直连」→ 该接口**不生成任何规则**（它本来就不进 mihomo，见 §4）

### 3.2 OPNsense 网络侧（**需要弹窗确认**，属于网络配置变更）

仅当该行「策略路由 = 自动」时生成：

| 生成物 | 位置（config.xml） | 说明 |
|---|---|---|
| `tun_mihomo` 接口 | `<interfaces><optN>` | 只加一次；上游 `+POST_INSTALL` 做的是同一件事 |
| 网关 `MIHOMO_TUN` | `<gateways>` | interface=tun_mihomo，地址取 TUN 对端，**关闭网关监控** |
| 策略路由规则 | `<filter><rule>` | 所选接口上 `pass` + `<gateway>MIHOMO_TUN</gateway>`（即 pf `route-to`） |
| DNS 重定向 | `<nat><rule>` | 仅「DNS=mihomo」时：所选接口 + 目的端口 53 → `127.0.0.1:1053` |
| 重新加载 | — | `configctl filter reload`（必要时 `service configd restart`） |

> 未列出的接口**一条规则都不加**：它们的流量还是走系统默认路由（pppoe1），
> 从头到尾不经过 mihomo —— 这正是"未设置的接口不走 mihomo"。

## 4. 为什么这样能同时满足两条要求

* **不同接口走不同代理**：pf 只把"被选中的接口"的流量 `route-to` 进 TUN；进 TUN 后
  由 §3.1 的按源规则决定走哪个代理组。
* **未配置的接口不走 mihomo**：它的流量在 pf 层就没有策略路由 → 直接走默认网关，
  连 mihomo 进程都不经过（不是"进 mihomo 再 DIRECT"）。mihomo 崩溃/重启也不影响它。

⚠️ 前提：`tun.auto-route` 必须为 **false**。`auto-route: true` 会把默认路由抢到 TUN，
等于"所有接口都进 mihomo"，与上面的模型互斥。页面在 TUN 页签给出联动提示。

## 5. 弹窗文案（Apply 前，gettext 可 i18n）

```
将进行以下变更

■ mihomo 配置（可自动回滚）
  · 写入/更新 3 条分流规则（config.yaml 与订阅模板）
  · 校验：mihomo -t（失败则整体放弃，不写入）

■ OPNsense 网络配置（会影响转发与防火墙）
  · 新增接口 tun_mihomo
  · 新增网关 MIHOMO_TUN（tun_mihomo，监控关闭）
  · 在 LanUS 新增 1 条策略路由规则（网关 MIHOMO_TUN）
  · 在 LanUS 新增 DNS 重定向：53 → 127.0.0.1:1053
  · 重新加载防火墙

未列出的接口不受影响（LanDirect、Console 仍按原路由出网）。
变更前会自动备份 /conf/config.xml，应用后显示 diff，可一键回滚。

[取消]  [应用并重新加载防火墙]
```

## 6. 必须处理的两个真实约束（本次勘察发现）

1. **订阅更新会重写 config.yaml**：`sub/sub.sh` 把订阅里的节点填进
   `sub/template_config.yaml` 的 `__MIHOMO_PROXIES__` / `__MIHOMO_NODE_NAMES__`，
   **`proxy-groups` 与 `rules` 以模板为准**。→ 受管区块必须**同时**写入模板，
   并在每次订阅更新后由 `subscription_run.sh` 重新注入（幂等），否则一次订阅更新就会冲掉分流规则。
2. **策略路由需要接口先被 OPNsense 认识**：`系统 → 网关` 里能选到 `tun_mihomo` 的前提是
   它在 config.xml 里有接口块（上游 `+POST_INSTALL` 做的就是这件事，我们这次没执行）。
   → 这一步在 §3.2 里由插件生成，且放在弹窗确认之后。

其它：IPv6 需另配（TUN v6 + 独立规则），当前设备未启用 v6 → 页面默认提示"IPv6 保持直连"。

## 7. 分期

| 阶段 | 内容 | 是否动网络配置 |
|---|---|---|
| **P12-1** | 路由策略页 + 表格 + 受管区块写入（config.yaml/模板）+ 预览 + `mihomo -t` 校验 + 状态列 + i18n | 否（只写插件自己的文件） |
| **P12-2** | 网络侧同步：接口/网关/策略路由/NAT-DNS + 弹窗确认 + config.xml 备份 + diff + 一键回滚 + `filter reload` | **是**（弹窗确认后） |
| **P12-3** | IPv6、按端口/目标细分、把策略路由导出成可审计的 pf 片段、与 `os-firewall` 插件的兼容检查 | 是 |

## 8. 验收方式（沿用本项目既有手法）

* `tools/deploy.ps1` 安全部署 + `php -l` 全绿；`tools/webtest.ps1` 增加路由策略端点检查；
* 只读验证：`pfctl -sr | grep MIHOMO_TUN`（策略路由规则）、`netstat -rn`（默认路由未被 TUN 抢走）、
  `ifconfig tun_mihomo`、mihomo `/proxies` 里各组可用；
* 端到端：LanUS 内的机器 `curl ifconfig.me` 得到代理出口 IP，LanDirect 内的机器得到本地公网 IP；
* 回滚：`config.xml.bak.os-mihomo-<ts>` 还原 + `filter reload`，并比对 pf/路由指纹回到基线。
