#!/usr/bin/env python3
"""P17 文档更新：config-guide（IPv6 选项 / 应用方式 / 运行值补全）、report §22、TODO、logs"""
import io

# ---------------- 1. docs/config-guide.md ----------------
p = 'docs/config-guide.md'
t = io.open(p, encoding='utf-8').read()

# 3.1 表格：补上新的 IPv6 键
old_row = "| 订阅自动更新 | **不写 YAML** | 关 | 只写 OPNsense 的原生定时任务（Cron），不碰这个文件 |"
new_rows = (old_row + "\n"
            "| IPv6 处理 | `ipv6` | **关**（随插件语义：分流只管 IPv4） | 让内核处理 IPv6。\n"
            "关掉（`ipv6: false`）＝ v6 流量照常走普通线路，不会出现\"一半流量偷偷绕过代理\"；开着则需要自己另外做 v6 分流 |\n"
            "| DNS 返回 IPv6 | `dns.ipv6` | 关 | 是否回答 AAAA 解析。隧道只有 IPv4 时开着容易让被代理的域名解析到 v6 地址 |")
t = t.replace(old_row, new_rows, 1)

# §6 第 0 步：补一句"运行中那栏现在会尽量填满"
anchor = "### 第 1 步：看文件（文件值）"
add = ("""### 第 0 步的补充：哪些项目"运行中"那栏会是空的

内核只对外报告一部分字段。能报告的（日志等级、模式、TUN 开关/设备/协议栈/自动路由/MTU、
域名嗅探、端口、IPv6）都会填上；**密钥**用一次探针判断（拿错密钥去问内核，401 = 会校验）；
**DNS 监听**用一次真实查询探测（有应答 = 正在监听那个地址）。
真正拿不到的只有「严格路由」「DNS 模式」这几项 —— 页面会在提示里说明，要确认得看文件和内核日志。

### 第 1 步：看文件（文件值）""")
t = t.replace(anchor, add, 1)

# §8 表格：应用方式一行
old_flow = "| 日志等级、TUN、DNS、控制器、嗅探开关 | 设置页 | 应用（可选重启） |"
new_flow = (old_flow + "\n"
            "| 只改某一项（日志等级 / MTU / 嗅探…） | 设置页 | 「应用」默认只写**你改过的项** —— 没动过的值不会被顺手覆盖；想让页面说了算就切到「以页面为准，全部写入文件」 |")
t = t.replace(old_flow, new_flow, 1)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('config-guide.md 已更新')

# ---------------- 2. TODO ----------------
p = 'TODO.md'
t = io.open(p, encoding='utf-8').read()
block = """## P17 修报错 + IPv6 选项 + 「只写入我改过的项」（本轮）

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

## P16 配置对照（本轮）"""
t = t.replace('## P16 配置对照（本轮）', block, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('TODO.md 已更新')

# ---------------- 3. docs/report.md ----------------
p = 'docs/report.md'
t = io.open(p, encoding='utf-8').read()
section = """## 22. P17：修好「应用」报错 + IPv6 选项 + 只写入我改过的项

### 22.1 用户报的错：首绑时「防火墙规则未能更新：…网关无效」

**现象**（真实对话框）：第一次把接口绑给 mihomo 时，应用失败：

```
[mihomo]     config.yaml: already up to date
[OPNsense]   防火墙规则未能更新: [OPNsense\\Firewall\\Filter:rules.rule.….gateway]
             从与网络ip协议匹配的列表中指定一个有效网关。{MIHOMO_TUN}
```

**根因**：顺序反了。原本先写**浮动规则**（带 `gateway=MIHOMO_TUN`）再建**网关**，
而防火墙模型的 gateway 字段会校验「这个网关存在且与规则的 IP 协议匹配」——
网关还不存在，校验直接失败。independently，mihomo 侧的规则已经写好了，于是留下"一半绑定"的状态。

**修法**：改成三段式（`policy_net.php` 支持 `verify` / `verify_only` 标志）：

| 段 | 做什么 | 自检 |
|---|---|---|
| ① `verify=false` | 只写接口块 + 网关（config.xml，带备份） | 不重载（规则还没写） |
| ② （WebGUI 侧） | 写/删浮动规则（核心防火墙模块） | 网关已存在 → 校验通过 |
| ③ `verify_only=true` | `configctl filter reload` + 数 pf 里的 `route-to … tun_mihomo` | 数量为 0 → 报错，并让 WebGUI **撤销刚写的规则**（宁可"没绑定"也不留假象） |

### 22.2 同一轮抓出的另外三个坑

| # | 坑 | 表现 | 修法 |
|---|---|---|---|
| 1 | bypass 规则**撞名** | 描述只写目标接口（`Mihomo bypass (opt1)`），两个绑定接口会生成同名规则 → 把"重复项"去重时把该留的那条删掉了（实测 6 条只留 5 条） | 描述改成 `来源 -> 目标`（`Mihomo bypass (lan -> opt1)`） |
| 2 | **configd 丢弃失败脚本的 stdout** | 第三段自检失败时 `exit 1` → 界面只显示「（无输出）」，真实原因被吞掉 | 第三段改成输出 `{"status":"failed","message":…}` 并 `exit 0` |
| 3 | 部署脚本的 **`php -l` 有洞** | `find` 表达式写错，`/usr/local/opnsense/scripts/mihomo/*.php` **从未被检查** —— 我的解析错误因此溜到线上 | 修好 find；现在 32 个 PHP 文件全部检查（日志会打印检查数量） |

### 22.3 新增功能（按用户要求）

* **设置页 → IPv6**：`IPv6 处理`（`ipv6`）、`DNS 返回 IPv6`（`dns.ipv6`）两项，纳入受管键。
  体检里的 IPv6 警告现在直接指向这个开关。
* **「应用方式」默认只写改动过的项**：页面装载时记快照，提交时把动过的字段名列给后端，
  后端只改对应的那几行。未动过的项即使与文件不一致也**不覆盖**，并在结果里告诉你有哪些
  （"想同步请点『从配置导入』，或选『以页面为准』"）。按钮旁边实时显示「将写入：X、Y」。
* **配置对照的「运行中」栏补全**：协议栈、域名嗅探、控制器地址都能填了；
  密钥用"拿错密钥问内核"的探针判断（401 = 会校验），DNS 监听用一次真实查询探测（有应答 = 在监听）。
  真正拿不到的只剩「严格路由」「DNS 模式」，页面明确说明。
* 对照页的提示文案改成**说人话**（"运行中那列是内核现在真的在用的值，改完文件还得重启服务才会变"…）。

### 22.4 实测（真实设备，用户自己的两个接口）

```
应用：interface block added: opt3 -> tun_mihomo / gateway added: MIHOMO_TUN -> 198.18.0.2 via opt3
      firewall: 6 floating rules added (opt2, lan)
      filter reload: OK      pf route-to rules into tun_mihomo: 2

pf 顺序：第一条 route-to 行号 69 < 接口默认放行 73   ✅（浮动规则先于接口规则）
规则：  opt2 → lan/opt1 内网直达 + 策略路由(US-AUTO)
        lan  → opt1/opt2 内网直达 + 策略路由(US-AUTO)
        igb4（LanDirect）route-to：0 条 ✅

内核规则：SrcIPCIDR 192.168.10.0/24 → US-AUTO
          AND((SrcIPCIDR,192.168.1.0/24) && (GeoSite,geolocation-!cn)) → US-AUTO
自检：  opt2 出口 48.46.15.95（US-AUTO[US-HK01]）命中 SrcIPCIDR(192.168.10.0/24)
        lan  出口 48.46.15.95（US-AUTO[US-HK01]）命中 AND(…GeoSite…)

安全：默认路由 pppoe1 未变；出网 200；TUN 198.18.0.1；回归测试 0 失败
```

> 注：应用完成后内核仍在跑旧配置（文件比进程新），重启一次才加载 —— 这是"应用 ≠ 重启"的活例子，
> 也正好写进了 `docs/config-guide.md` §2。

---

"""
t = t.replace('## 21. P15：界面细节修复 + 配置说明文档', section + '## 21. P15：界面细节修复 + 配置说明文档', 1)
# 目录补一行
t = t.replace('21. [P15：界面细节修复 + 配置说明文档](#21-p15界面细节修复--配置说明文档)',
              '21. [P15：界面细节修复 + 配置说明文档](#21-p15界面细节修复--配置说明文档)\n22. [P17：修好「应用」报错 + IPv6 选项 + 只写入我改过的项](#22-p17修好应用报错--ipv6-选项--只写入我改过的项)',
              1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('report.md 已更新')

# ---------------- 4. logs ----------------
log = io.open('logs/2026-10-18-session.md', encoding='utf-8').read()
log += """

---

## 2026-10-19 08:2x-09:0x P17：修「应用」报错 + IPv6 选项 + 只写入我改过的项

### 用户报错（截图）
路由策略页点「应用」：
  [mihomo] config.yaml / template_config.yaml: already up to date
  [OPNsense] 防火墙规则未能更新: …rules.rule.<uuid>.gateway 从与网络ip协议匹配的列表中指定一个有效网关。{MIHOMO_TUN}

### 根因与修法
- 根因：先写浮动规则（gateway=MIHOMO_TUN）后建网关 → 防火墙模型校验"网关不存在"直接失败
- 修法：三段式
  ① verify=false  接口+网关（不重载）
  ② WebGUI 侧写浮动规则（此时网关已在 config.xml → 校验通过）
  ③ verify_only=true  filter reload + 数 route-to；为 0 则报错 + WebGUI 撤销刚写的规则

### 同轮抓出的另外三个坑
1. bypass 规则撞名：描述只带目标接口 → 两个绑定接口生成同名规则被去重删掉（6 条只留 5 条）
   → 描述改成 "来源 -> 目标"
2. configd 在脚本非零退出时丢掉 stdout → 界面只显示「（无输出）」
   → 第三段改成 status:failed + exit 0
3. 部署脚本的 php -l 有洞：find 表达式写错，scripts/mihomo/*.php 从未被检查（我的解析错误因此溜上线）
   → 修好 find；现在 32 个 PHP 文件全部检查

### 新功能
- 设置页新增 IPv6 区：IPv6 处理（ipv6）、DNS 返回 IPv6（dns.ipv6）
- 「应用方式」默认「只写入我改过的项」：页面快照 + 实时"将写入：X、Y"；未改动项不覆盖
- 配置对照「运行中」栏补全：协议栈/嗅探/控制器地址；密钥用错误密钥探针（401=会校验）、
  DNS 用一次真实查询探测（有应答=在监听）；只有严格路由/DNS 模式内核不报告
- 对照页提示文案改成说人话

### 实测（用户的两个接口：lan + opt2）
- 应用成功：6 条浮动规则 + pf route-to 2 条；顺序 route-to(69) < 默认放行(73)；igb4 0 route-to
- 自检命中受管规则：opt2 → SrcIPCIDR(192.168.10.0/24)；lan → AND(…GeoSite,geolocation-!cn)
  出口 48.46.15.95（US-AUTO[US-HK01]）
- 应用后内核仍跑旧配置 → 重启一次加载（文件比进程新），这是"应用≠重启"的活例子
- 默认路由未变、出网 200、回归测试 0 失败
"""
io.open('logs/2026-10-18-session.md', 'w', encoding='utf-8', newline='\n').write(log)
print('logs 已追加')
