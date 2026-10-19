# 配置说明：YAML 文件 vs WebUI 选项

> 这份文档回答三件事：
> 1. WebUI 上的每个开关，到底改的是 YAML 里的哪一行？
> 2. 同一个东西两个地方都能改时，**听谁的**？
> 3. 怎么确认「此刻真的在用什么配置」，而不是靠猜？

面向使用者写的，尽量说人话；所有命令都可以直接复制粘贴（在 OPNsense 的 SSH 里执行，或在 WebUI 的「诊断 → 命令提示符」里执行）。

---

## 0. 先记住四句话

1. **内核只认一个文件**：`/usr/local/etc/mihomo/config.yaml`。mihomo 启动时读它，别的地方改了它不算数。
2. **WebUI 不是"另一份配置"，它是一个"改写器"**：你在页面上勾的选项，最后都是去改这个 YAML 文件里的某几行。改完还要**重启服务**才真正生效。
3. **改文件 ≠ 已生效**：内核在启动的那一刻把配置读进内存，之后你在文件里怎么改都不影响正在跑的进程。**运行值（内存里）才是"此刻真实生效"的那一个。**
4. **有三类东西不在这个 YAML 里**：开机自启（`/etc/rc.conf.d/mihomo`）、OPNsense 网络层（接口/网关/防火墙规则）、以及插件自己的"记忆"（`/conf/config.xml` 里的 `<OPNsense><mihomo>`）。

---

## 1. 全景图：三处存储、四个写入者

```
 谁会去改 config.yaml？
 ┌────────────────────────────────────────────────────────────┐
 │ ① 设置页「应用」     只改 22 个键：逐行替换那一行的值        │
 │ ② 路由策略页「应用」  只改"受管区块"：整块替换标记之间的内容  │
 │ ③ 订阅页「更新订阅」  用模板整份重写（节点段除外）→ 最暴力   │
 │ ④ 设置页「原始配置编辑器」/ 你自己 SSH 编辑 → 想改哪都行     │
 └────────────────────────────────────────────────────────────┘
                              │
                              ▼
              /usr/local/etc/mihomo/config.yaml   ←── 唯一权威
                              │  启动时读一次
                              ▼
                     mihomo 进程内存里的配置 ←── 真正生效的那份

 另外两处（不在 YAML 里）：
 ┌──────────────────────────────┐  ┌───────────────────────────────────┐
 │ /etc/rc.conf.d/mihomo        │  │ /conf/config.xml                  │
 │ mihomo_enable="YES|NO"       │  │ <OPNsense><mihomo>  ← WebUI 的"记  │
 │ → 开机要不要自动启动          │  │ 忆"：设置页字段值 + 策略表行        │
 └──────────────────────────────┘  └───────────────────────────────────┘
                                   ┌───────────────────────────────────┐
                                   │ OPNsense 网络层（只有策略页会动）    │
                                   │ · 接口 opt3 → tun_mihomo          │
                                   │ · 网关 MIHOMO_TUN → 198.18.0.2    │
                                   │ · 防火墙"浮动规则"：把某接口流量送进  │
                                   │   TUN + 内网直达规则                │
                                   └───────────────────────────────────┘
```

### 相关文件一览

| 文件 | 作用 | 谁写它 |
|---|---|---|
| `/usr/local/etc/mihomo/config.yaml` | **唯一真配置**（权限 600） | 上面四个写入者 |
| `/usr/local/etc/mihomo/config.yaml.bak.<时间戳>` | 插件每次落盘前的备份（保留最近 20 份） | 插件（设置页/策略页/编辑器） |
| `/usr/local/etc/mihomo/config.yaml.bak.sub_<时间戳>` | 订阅更新前的备份 | 订阅脚本 |
| `/usr/local/etc/mihomo/sub/template_config.yaml` | 订阅模板：订阅更新时用它当骨架 | 插件（同时会把受管区块写进去） |
| `/usr/local/etc/mihomo/sub/env` | 订阅地址与订阅密钥（`mihomo_URL` / `mihomo_secret`） | 订阅页「保存设置」 |
| `/usr/local/etc/rc.d/mihomo` | 服务脚本（启动/停止/状态、起前的 `mihomo -t` 校验） | 插件安装包 |
| `/etc/rc.conf.d/mihomo` | `mihomo_enable` 开机自启开关 | 设置页「启用 mihomo」复选框 |
| `/var/log/mihomo.log` | 内核日志（stdout/stderr） | 内核 |
| `/var/log/mihomo_sub.log` | 订阅更新日志 | 订阅脚本 |
| `/conf/config.xml` | OPNsense 主配置：插件设置 + 策略表行的"记忆" | OPNsense 模型机制 |

---

## 2. 三个"真"：文件值 / 运行值 / WebUI 值

这仨经常不一样，弄不清就会得出"我明明改了怎么没用"的结论。

| | 是什么 | 怎么看 | 什么时候和别的不同 |
|---|---|---|---|
| **WebUI 值** | 你在页面里填/勾的值，存在 `/conf/config.xml` 的 `<OPNsense><mihomo>` 里 | 打开设置页看；或 `configctl mihomo` 系列无关——直接看页面 | 你改了页面但没点「应用」；或者你手工改了 YAML（页面不知道） |
| **文件值** | `config.yaml` 里真实写着的那一行 | `grep` / 设置页的「原始配置编辑器」 | 你点了「应用」但没重启；或者订阅更新把文件重写了 |
| **运行值** | 内核**内存里正在用**的配置（启动那一刻读的） | 仪表盘；或读外部控制器 `/configs` | 只要改了文件没重启，就与文件不同 |

> **最快的一次性看法**：设置页 →「**配置对照**」标签页。它把上面三个值并排列出来（同一行一项），
> 下面还有自动提示：哪些值和页面不一致、这份配置是不是手写的（订阅更新会覆盖）、有没有受管区块、IPv6 是否绕过代理。

**一句话记法：**

- 页面 ≠ 文件 → **忘了点「应用」**（或手工改了文件，页面的"记忆"过期了）
- 文件 ≠ 运行 → **忘了重启**

---

## 3. 对照表：WebUI 选项 ↔ YAML 键 ↔ 默认值

### 3.1 设置页（点「应用」才会落盘）

下面 24 个键就是设置页能改的**全部**。表中"WebUI 字段"是页面上的名字。

> **默认一项都不写**：设置页每一项前面都有一条「不修改」（默认勾上）。
> 勾着 = 插件不碰这一项（文件里原本怎么写就怎么用，文件里没有的键也不会加上）；
> 想让它按页面上的值写，先把那一项的勾去掉。`rc.conf.d`（开机自启）、订阅环境文件、Cron（自动更新）同理。

| WebUI 字段 | YAML 键 | 默认值 | 说明 |
|---|---|---|---|
| 日志等级 | `log-level` | info | `debug/info/warning/error/silent`；长期运行建议 `error` 或 `silent` |
| 运行模式 | `mode` | rule | `rule` 按规则分流 / `global` 全走代理 / `direct` 全直连 |
| 允许局域网 | `allow-lan` | false | 开放代理端口给局域网；**插件要求它保持关闭**，分流靠 TUN |
| 绑定地址 | `external-controller` 的主机部分 | 127.0.0.1 | 控制器监听地址。**别改成 0.0.0.0**，否则整个网络都能改你的代理配置 |
| 端口 | `external-controller` 的端口部分 | 9090 | 控制器端口；WebGUI 自己也靠它取数据（走本机回环） |
| 密钥 | `secret` | 空 | 控制器的访问密钥。**留空 = 谁都能访问**（仅当绑定地址是 127.0.0.1 时可接受）。注意：WebUI 里留空会把文件里的值清成空串 |
| 域名嗅探 | `sniffer.enable`（外加 7 个嗅探键，见下） | 关 | 打开后会把嗅探端口表一起写全，否则域名类规则对"被路由进来的流量"不生效 |
| TUN 模式 | `tun.enable` | 开 | 是否启用虚拟网卡（插件分流的前提） |
| 设备名称 | `tun.device` | tun_mihomo | 要和防火墙规则里的一致，一般别改 |
| 协议栈 | `tun.stack` | gvisor | FreeBSD 上建议 gvisor |
| 自动接管路由 | `tun.auto-route` | 开* | **危险开关**：打开会让所有 IPv4 流量进 TUN；插件的做法是**关掉它**，改用"按接口分流" |
| 强制路由 | `tun.strict-route` | 开* | 让 TUN 抢赢其它默认路由；按接口分流场景建议关 |
| MTU | `tun.mtu` | 1500 | 一般不用动 |
| DNS 模块 | `dns.enable` | 开 | 是否让 mihomo 自己解析域名 |
| DNS 监听 | `dns.listen` | 127.0.0.1:1053 | 只是内核自己的 DNS 监听地址 |
| DNS 模式 | `dns.enhanced-mode` | fake-ip | `fake-ip`（返回假地址）/ `redir-host`（返回真实地址） |
| 订阅自动更新 | **不写 YAML** | 关 | 只写 OPNsense 的原生定时任务（Cron），不碰这个文件 |
| IPv6 处理 | `ipv6` | **关**（随插件语义：分流只管 IPv4） | 让内核处理 IPv6。
关掉（`ipv6: false`）＝ v6 流量照常走普通线路，不会出现"一半流量偷偷绕过代理"；开着则需要自己另外做 v6 分流 |
| DNS 返回 IPv6 | `dns.ipv6` | 关 | 是否回答 AAAA 解析。隧道只有 IPv4 时开着容易让被代理的域名解析到 v6 地址 |

\* 随包/订阅模板里的默认是"开"，插件首次「应用」会把它们改成"关"——这正是"文件值"与"模板默认"的差异来源。

**「域名嗅探」打开时同时写这 8 个键**（只写 `enable: true` 是不够的，实测域名规则对路由流量不生效）：

```yaml
sniffer:
  enable: true
  parse-pure-ip: true
  force-dns-mapping: true
  override-destination: true
  sniff:
    HTTP: { ports: [80, 8080-8880], override-destination: true }
    TLS:  { ports: [443, 8443] }
    QUIC: { ports: [443, 8443] }
```

> 关闭时**只**把 `sniffer.enable` 改成 `false`，端口表原样留着（下次打开即恢复）。

### 3.2 路由策略页（策略表 + 「应用」）

「应用」做两件事，两件事都要做才算完整：

**A. 写 mihomo 规则**（进 `config.yaml` 的受管区块，位置在 `rules:` 的第一段，先匹配）：

| 规则范围 | 生成的 mihomo 规则 | 含义 |
|---|---|---|
| 仅国外 | `AND,((SRC-IP-CIDR,<源>),(GEOSITE,geolocation-!cn)),<代理组>` + 同样一条用 `GEOSITE,gfw` | 该来源的**国外**流量走代理组；国内仍然直连（由你原来的规则决定） |
| 全部 | `SRC-IP-CIDR,<源>,<代理组>` | 该来源的所有流量都丢给代理组 |
| 直连 | `SRC-IP-CIDR,<源>,DIRECT` | 该来源强制直连（等于"排除这个网段"） |

`<源>` 的取值：策略行里"源地址"留空 → 自动用该接口的网段（例：`lan` → `192.168.1.0/24`）。

受管区块长这样（**只有这段是插件会整块替换的**）：

```yaml
rules:
  # >>> os-mihomo:policy-routing (managed, do not edit) >>>
  - AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,geolocation-!cn)),US-EXIT
  - AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,gfw)),US-EXIT
  # <<< os-mihomo:policy-routing <<<
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve      ← 你自己的规则，插件不动
  - MATCH,US-EXIT
```

**B. 写 OPNsense 网络层**（"防火墙规则"列选「创建」的行才会有）：

| 对象 | 具体内容 | 说明 |
|---|---|---|
| 接口 | `optN` → 设备 `tun_mihomo` | 给 TUN 网卡在 OPNsense 里登记一个名字 |
| 网关 | `MIHOMO_TUN` → `198.18.0.2` | TUN 的对端地址（自动从 `198.18.0.1/30` 推出） |
| 防火墙**浮动规则** | ① 内网直达（无网关）× N；② 策略路由（带 `MIHOMO_TUN`）× 1 | 浮动规则**先于**接口规则执行，所以不会被"Default allow LAN to any"抢先 |

**为什么必须是浮动规则？**（这是踩过的坑，值得记下来）

> 一开始插件把规则写进旧版 `<filter>` 段，结果 pf 里的顺序是「接口默认放行 → 我们的策略路由」。
> pf 的 `quick` 规则第一条匹配就结束，于是我们的规则评估次数永远是 0——**界面显示"生效中"，实际一点用没有**。
> 后来改用核心防火墙模块的**浮动规则**（`prio_group=200000`，接口规则是 `400000`），顺序才正确。

**对账语义**：策略表是"标准答案"。点「应用」时插件会

- 表里有、网络侧没有 → 建；
- 表里没有、网络侧有 → 删（删掉策略行后**必须点「应用」**才会回收）；
- 表里某行的"防火墙规则"是「不创建」→ 网络侧不碰，只写 mihomo 规则（你自己负责把流量送进 TUN）。

### 3.3 订阅页

| 操作 | 落到哪里 |
|---|---|
| 「保存设置」（URL / 访问密钥） | 写 `/usr/local/etc/mihomo/sub/env`（`mihomo_URL=`、`mihomo_secret=`）＋ 同步写 `/conf/config.xml` 的模型 |
| 「更新订阅」 | 跑 `/usr/local/etc/mihomo/sub/sub.sh`：下载 → **只提取订阅里的 `proxies:` 段** → 套进模板 → 校验 → 备份 → **整份替换 config.yaml** → （按勾选）重启 |
| 「重启服务 after update」 | 决定订阅脚本最后是否执行 `service mihomo restart`；**默认不勾**（不重启更安全） |

### 3.4 服务控制（不在 config.yaml 里）

| 按钮 | 干什么 |
|---|---|
| 页面右上角「启动 / 停止 / 重启」 | `configctl mihomo start|stop|restart` → 操作进程；停止时会销毁 `tun_mihomo` 接口 |
| 设置页「启用 mihomo」复选框 + 「应用」 | 写 `/etc/rc.conf.d/mihomo` 的 `mihomo_enable`：**只管开机自启**，不会顺便把服务拉起来 |
| 日志页 | 看 `/var/log/mihomo.log` 与订阅日志 |

---

## 4. WebUI 改不到的东西（只能改 YAML）

这些键插件**不碰**，你在页面上也找不到，要改就直接编辑 `config.yaml`（设置页有「原始配置编辑器」，保存前会校验）：

- `proxies:` —— 节点（订阅更新会重写这一段）
- `proxy-groups:` —— 分组（策略页的"代理组"下拉就是从这读的）
- `rules:` —— **受管区块之外**的所有规则，包括最后的 `MATCH`
- `dns:` 里的 nameserver / fake-ip 过滤 / nameserver-policy 等细节（页面只给 `enable` / `listen` / `enhanced-mode` 三个）
- 各种端口：`mixed-port`、`socks-port`、`port`
- 性能与行为开关：`unified-delay`、`tcp-concurrent`、`find-process-mode`、`client-fingerprint`、`profile.*`
- `geodata-*`（GeoIP/GeoSite 自动更新）
- `external-ui` / `external-ui-url`（内核自带的面板；**本 WebUI 不嵌入它**，只用它做数据源的方式是——不，我们不用它，我们直接读控制器 API）
- `lan-allowed-ips`、`bind-address`、`keep-alive-interval`
- `sniffer` 的 `skip-domain` 等细节（页面只管开关与端口表）

> 判断标准很简单：**设置页/策略页/订阅页上看不到的，就是"只能在 YAML 里改"的**。

---

## 5. 交叉与重复：六种情形，谁说了算

### 情形 1：同一个键，页面和文件都有 —— 点「应用」时**页面赢**

设置页「应用」的逻辑是：读文件 → 把 22 个键逐个改成页面里的值 → 校验 → 落盘。

- 结果：`tun.mtu` 你在文件里写 1400，页面里是 1500 → 点「应用」后被改回 **1500**。
- 贴心之处：**值相等时那一行一个字节都不动**（注释、引号、缩进都保留）；只有不一致才改那一行的值。

**想让页面跟随文件** → 设置页点「从配置导入」（把文件里的值读回页面）。

### 情形 2：页面里的值留空 —— 会把文件里的值**清成空**

典型是 `secret`：页面留空 + 点应用 → 文件里变成 `secret: ''`。

**所以：不要在不知情的情况下点「应用」**；点之前看一眼弹窗/日志里的说明，或者先「从配置导入」。

### 情形 3：受管区块 —— 只动标记之间那几行

- 区块外的规则、注释、其它段落：插件**一个字节都不改**。
- 删掉策略行 / 全部解绑 → 区块整体消失（不留空壳）。
- 手改区块内的内容 → 下次点「应用」会被覆盖（提示语就写着 `do not edit`）。

### 情形 4：订阅更新 —— **整份重写**（最需要注意的一条）

「更新订阅」不是"只更新节点"，而是：

```
订阅链接 → 下载 → 只取其中的 proxies: 段
        → 套进 /usr/local/etc/mihomo/sub/template_config.yaml（模板）
        → 校验 → 备份为 config.yaml.bak.sub_<时间戳>
        → 整份替换 /usr/local/etc/mihomo/config.yaml → （可选）重启
```

**后果**：你在文件里的所有手工修改（节点命名、分组、规则、以及不在页面上的任何设置）都会被模板的写法覆盖。

模板里几个需要注意的默认值：

| 模板里的写法 | 为什么要注意 |
|---|---|
| `tun.auto-route: true` + `strict-route: true` | 打开就是"全局接管路由"，代理一坏整网断网。插件的做法是应用时改成 `false` |
| `dns-hijack: any:53` | DNS 也被劫持进内核 |
| `external-controller: 0.0.0.0:9090` | 控制器对**整个网络**开放（安全体检横幅会警告） |
| `secret: "CHANGE_ME"` → 脚本会替换 | 脚本用 `sub/env` 里的 `mihomo_secret`；**空的话每次随机生成** |
| `external-ui-url` → zashboard | 内核会去下载那个第三方面板（本 WebUI 不嵌入它） |

**插件为此做了两件事**：

1. 受管区块同时写进**模板**（`sub/template_config.yaml`），这样订阅更新后策略规则不会丢；
2. 「更新订阅」默认**不重启服务**（不勾选就只生成文件、不影响正在跑的流量）。

**建议**：如果你想长期用自己手写的配置（比如你现在的 `US-AUTO`/`US-EXIT` 结构），那就**不要点「更新订阅」**；要更新节点时，改成手工把节点段贴进 `config.yaml`（或用原始编辑器），再「校验」+「重启」。

### 情形 5：OPNsense 网络层 —— 表是标准答案，必须点「应用」才对账

- 症状：删了策略行，但被绑的网段**仍然**断网/走代理 → 因为浮动规则和网关还在。
- 解决：回策略页点「应用」（它会删掉多余的规则/网关/接口块），或点「撤销网络配置」（回到上一次网络侧变更前的 config.xml）。
- 副作用提醒：被绑接口的流量一旦依赖 TUN，**服务停止/启动失败时那个网段就没有外网**（体检横幅与策略页状态行会提示）。

### 情形 6：服务层 —— 与 YAML 完全无关

| 你看到的 | 实际位置 | 与服务的关系 |
|---|---|---|
| 「启用 mihomo」复选框 | `/etc/rc.conf.d/mihomo` 的 `mihomo_enable` | 只管**开机自启**；不影响当前进程 |
| 页面右上角启动/停止/重启 | 进程本身 | 重启才会重新读 `config.yaml` |
| 服务脚本启动前 | `/usr/local/etc/rc.d/mihomo` | 会先跑 `mihomo -t -d /usr/local/etc/mihomo -f config.yaml`，**校验不过直接不启动**；还会检测 sing-box 冲突、清理残留 TUN |

---

## 6. 怎么确认「此刻真实配置」（四步法）

### 第 0 步（最快）：设置页 →「配置对照」标签

不用命令，打开就有：一行一项，三列并排 —— **页面（设置）/ 文件（config.yaml）/ 运行中（内存）**。
每行还有一个标签：

| 标签 | 含义 | 该怎么办 |
|---|---|---|
| `一致` | 页面值 = 文件值 | 不用管 |
| `不一致` | 两处都写了但值不同 | 想以页面为准 → 点本页「应用」；想以文件为准 → 点「从配置导入」 |
| `文件未写` | 文件里没有这个键（内核用内置默认值） | 一般没事；想固定下来就点「应用」写进文件 |
| `仅运行值` | 只有内核知道（如端口、IPv6 开关），页面管不到 | 要改就编辑文件 |

页面下方的提示区还会自动告诉你：**这份配置是不是手写的**（如果是，"更新订阅"会整份覆盖它）、
有没有**受管区块**、**IPv6 是否绕过代理**、以及**运行值读不到**的原因。

真实输出（2026-10-18，本机设备）：

```
项目              页面              文件               运行          状态
日志层级          info              info              info          match
允许局域网         false             false             false         match
安全              （空）            （空）             —             match      ← 密钥只显示"已设置/空"
TUN 模式          true              true              true          match
MTU              1500              1500              1500          match
混合端口          —                 7890              7890          na（仅运行值）
SOCKS 端口        —                 （文件里没有）      0             na（仅运行值）
IPv6              —                 （文件里没有）      true          na（仅运行值）

提示：
 [info] 运行值来自 mihomo 的外部控制器，也就是进程内存里正在用的那份配置。
 [warning] 这份 config.yaml 看起来是手写的：点「更新订阅」会用订阅模板整份重写它。
 [info] 文件里没有受管区块（当前没有任何接口被绑定）。
 [warning] IPv6 是开着的，而 TUN 设备只有 IPv4 地址：IPv6 流量会绕过 mihomo。
```

### 第 0 步的补充：哪些项目"运行中"那栏会是空的

内核只对外报告一部分字段。能报告的（日志等级、模式、TUN 开关/设备/协议栈/自动路由/MTU、
域名嗅探、端口、IPv6）都会填上；**密钥**用一次探针判断（拿错密钥去问内核，401 = 会校验）；
**DNS 监听**用一次真实查询探测（有应答 = 正在监听那个地址）。
真正拿不到的只有「严格路由」「DNS 模式」这几项 —— 页面会在提示里说明，要确认得看文件和内核日志。

### 第 1 步：看文件（文件值）

```sh
# 基础开关一眼扫
grep -nE '^(log-level|mode|allow-lan|mixed-port|socks-port|external-controller|secret):' /usr/local/etc/mihomo/config.yaml

# TUN / DNS / 嗅探
sed -n '/^tun:/,/^dns:/p'  /usr/local/etc/mihomo/config.yaml
sed -n '/^dns:/,/^sniffer:/p' /usr/local/etc/mihomo/config.yaml
sed -n '/^sniffer:/,/^tun:/p' /usr/local/etc/mihomo/config.yaml

# 策略规则（受管区块）与你自己规则的分界
grep -n 'os-mihomo:policy-routing' /usr/local/etc/mihomo/config.yaml
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' /usr/local/etc/mihomo/config.yaml

# 分组名（策略页的下拉就从这来）
sed -n '/^proxy-groups:/,/^rules:/p' /usr/local/etc/mihomo/config.yaml | grep 'name:'
```

### 第 2 步：校验语法（文件能不能被接受）

```sh
mihomo -t -d /usr/local/etc/mihomo -f /usr/local/etc/mihomo/config.yaml
# 或者 WebUI：设置页 →「校验当前配置」
configctl mihomo config-check <某个文件>     # 校验任意文件（插件内部用）
```

### 第 3 步：看**运行值**（内核内存里正在用的）

```sh
# 控制器密钥（空 secret 就不用带这个头）
SECRET=$(awk -F': *' '/^secret:/{gsub(/["'\'']/,"",$2);print $2}' /usr/local/etc/mihomo/config.yaml)

curl -s http://127.0.0.1:9090/configs -H "Authorization: Bearer $SECRET" | python3 -m json.tool
#   ↑ port / socks-port / mixed-port / allow-lan / mode / log-level / tun{...} / sniffer{...}

# 内核此刻实际持有的规则（第一段就是策略区块的效果）
curl -s http://127.0.0.1:9090/rules -H "Authorization: Bearer $SECRET" | head -c 800

# 入口/出口：现在挂着哪些连接
curl -s http://127.0.0.1:9090/connections -H "Authorization: Bearer $SECRET" | head -c 400
```

WebUI 里更直观：**仪表盘**页面（运行态/内核版本/模式/流量曲线）——它读的就是控制器，属于"运行值"。

### 第 4 步：看网络侧（OPNsense 那一半）

```sh
configctl mihomo policy-net-check          # 接口/网关/规则 现状（只读）
configctl mihomo policy-net-plan           # 与策略表比对：会改什么
pfctl -sr | grep route-to                  # 真把流量送进 TUN 的 pf 规则
pfctl -sr | grep -n 'on igb0' | head       # 看看顺序：浮动规则应在接口默认放行之前
```

WebUI 里：**仪表盘**底部「运行态概览」与**路由策略**页的状态行；策略页还有「自检」按钮（临时把测试流量送进 TUN，回报出口 IP 与命中的规则）。

### 一键版：三方对照脚本

仓库里带了一个只读脚本，能一次把上面四步的重点打出来：

```sh
# 本机（Windows）执行：
powershell -File tools/remote.ps1 -Script scripts/config_truth.sh
```

它输出四段：**① WebUI 值 vs 文件值 ② 文件值 vs 运行值 ③ 受管区块 ④ 不在 YAML 里的东西**。
真实输出示例（2026-10-18）：

```
 1) WebUI 值 vs 文件值
  项目               WebUI（config.xml）   文件（config.yaml）   一致
  ------------------------------------------------------------------------
  日志等级            info                  info                  ✅
  允许局域网          0                     false                 ✅
  控制器地址          127.0.0.1:9090        127.0.0.1:9090        ✅
  TUN 抢默认路由      0                     false                 ✅
  TUN 协议栈          gvisor                gvisor                ✅
  域名嗅探            1                     true                  ✅
  不一致项：0

 2) 文件值 vs 运行值
  运行模式            rule                  rule                  ✅
  mixed 端口          7890                  7890                  ✅
  socks 端口          （未写）               0                     ✅
  TUN 地址            -                     198.18.0.1/30         ✅
  文件与运行值一致 → 当前内核用的就是你文件里的配置。

 3) 受管区块：config.yaml 里没有受管区块（当前没有任何接口被绑定）

 4) 不在 config.yaml 里的东西
  开机自启（/etc/rc.conf.d/mihomo）： mihomo_enable="YES"
  OPNsense 侧网关 MIHOMO_TUN： 0 处
  pf 里送进 TUN 的规则： 0 条
```

（每段的"一致?"列：`✅` 一致，`❌` 不一致，`—` 文件里没写这个键、内核用默认值。）

---

## 7. 常见疑问

**Q1：我在 `config.yaml` 里加了几条规则，为什么没生效？**
看文件值 vs 运行值（第 3 步）。多半是**没重启**：改文件不改内存。另外确认你的规则不在受管区块内（区块内的会被覆盖），并且位置在 `MATCH` 之前（`MATCH` 一旦匹配就结束）。

**Q2：日志里找不到我的域名规则命中记录？**
被路由进 TUN 的流量是 IP 包，**没有域名**。要在"域名嗅探"打开（并且端口表写全）之后，内核才能从 TLS SNI / HTTP Host 反推出域名。设置页打开「域名嗅探」→ 应用 → 重启。

**Q3：设置页显示的和文件里不一样，信谁？**
信**文件 + 运行值**。页面只是"记忆"，可能过期。让页面跟上文件：设置页「从配置导入」。

**Q4：我在设置页改了 TUN 的开关，为什么文件里没变？**
三种可能：① 没点「应用」；② 值本来就相等（相等时不动那一行，包括写法差异，如 `1` vs `true`）；③ 之后跑过订阅更新，把文件整份重写了。

**Q5：点了「更新订阅」会把我手写的配置冲掉吗？**
**会**。订阅更新是"模板 + 订阅节点"整份重写。所以：手写配置的用户不要点它（要更新节点就手工贴）；点了也不怕的是——会自动备份成 `config.yaml.bak.sub_<时间戳>`，在策略页的「配置历史」里能看差异、能一键还原。并且**受管区块（策略规则）不会被冲掉**，因为插件把它也写进了模板。

**Q6：删了策略行为什么网络侧还留着？**
网络侧是"对账"关系，不是"实时联动"。回策略页点「应用」才回收；或者点「撤销网络配置」回到上一次改动前。

**Q7：两个地方都写了 secret，哪个算数？**
`config.yaml` 里的那个（唯一权威）。订阅页的访问密钥只是写进 `sub/env`，订阅脚本生成新文件时用它；`sub/env` 里为空时脚本**每次随机生成**一个新的并提供给你（日志里可以看到）。

**Q8：「应用」和「重启」的区别？**
- 「应用」= 把页面里的值写进文件（+校验+备份）。**不动正在跑的进程。**
- 「重启」= 让内核重新读文件。**只重启不应用 = 什么都没变。**

**Q9：TUN 开着，但没绑任何接口，流量会走代理吗？**
不会。`auto-route: false` 时 TUN 只是个安静的网卡；只有防火墙/策略路由把流量送进去，它才会处理。这也是插件坚持"关掉自动接管 + 按接口分流"的原因。

**Q10：仪表盘数据都是 0，是不是坏了？**
先看有没有绑定接口（策略页状态行），以及有没有实际流量。没绑定时所有数字天然是 0；这不代表故障。

**Q11：策略页里"防火墙规则"选「不创建」有什么用？**
只写 mihomo 规则，OPNsense 侧不动。适合你自己已经有路由/规则把流量送进 TUN 的情况（比如你手工建了网关与规则）。选它之后 pf 里不会有插件建的 `route-to` 规则，插件也不会替你兜底。

**Q12：被绑接口的机器，mihomo 一停就断网，怎么避免？**
这是分流本身的代价。缓解办法：① 保持 `tun.auto-route: false`（插件默认）；② 只用小网段试（比如 Console 那个没人的 LAN）；③ 用「撤销网络配置」一键把网络侧恢复。

**Q13：IPv6 会走代理吗？**
不会。当前是 IPv4-only 的分流：TUN 只有 IPv4 地址，IPv6 流量会按内核正常路由出去（绕过代理）。如果要管 IPv6，得单独设计（属于待办项）。

**Q14：日志在哪、怎么看？**
内核：`/var/log/mihomo.log`（日志页「内核日志」标签），级别由 `log-level` 决定。
订阅：`/var/log/mihomo_sub.log`（日志页「订阅日志」标签）。

**Q15：怎么把某一台机器排除在分流之外？**
在策略表里给它单独加一行：接口选它所在网卡、源地址填它的 IP（或另一个网段）、规则范围选「直连」→ 应用。这条规则会排在前面优先匹配。

**Q16：`config.yaml` 权限是 600，谁能读？**
root（WebGUI 的 PHP 以 root 跑、configd 以 root 跑）。所以页面里能直接看到内容；普通用户不行。

---

## 8. 建议的改动流程

| 你想做的事 | 去哪改 | 改完必须做 |
|---|---|---|
| 换节点 / 加分组 / 改规则（非受管部分） | 设置页「原始配置编辑器」（或 SSH 编辑） | 校验 → 重启 |
| 日志等级、TUN、DNS、控制器、嗅探开关 | 设置页 | 应用（可选重启） |
| 只改某一项（日志等级 / MTU / 嗅探…） | 设置页 | 先把那一项前面的**「不修改」勾去掉**（默认都勾着），点「应用」就只写这一项；其余项插件一概不碰 —— 连文件里没有的键也不会给你加上 |
| 什么都不想它动 | 设置页 | 保持所有「不修改」都勾着（默认）。点「应用」只会说一句"配置文件保持原样" |
| 按接口分流（谁走代理、谁直连） | 路由策略页 | 应用 → 自检 |
| 订阅地址 / 自动更新 | 订阅页 / 设置页 | 保存设置；自动更新另需在设置页「应用」 |
| 开机自启 | 设置页「启用 mihomo」 | 应用 |
| 回退到某个历史配置 | 路由策略页「配置历史」→ 差异/恢复 | 恢复后重启 |

**每轮改完的自检三连：**

```sh
configctl mihomo config-current      # 配置语法校验
sh scripts/config_truth.sh           # 三方对照（本机跑：tools/remote.ps1 -Script ...）
configctl mihomo selftest            # 绑定自检（临时把测试流量送进 TUN 看出口 IP）
```

---

## 9. 附录

### 9.1 全部 configd 动作（`configctl mihomo <动作>`）

| 分组 | 动作 |
|---|---|
| 服务 | `start` `stop` `restart` `status` `set-enabled` |
| 配置 | `config-check` `config-install` `config-current` `config-restore` |
| 分流 | `policy-apply` `policy-net-check` `policy-net-plan` `policy-net-apply` `policy-net-rollback` `selftest` |
| 订阅 | `sub-update` `sub-run` `env-get` `env-set` |
| 日志 | `log-tail` `log-clear` |

只读的 Web 接口（浏览器用，也可 curl）：

| 接口 | 作用 |
|---|---|
| `GET /api/mihomo/settings/inspect` | 配置对照：页面值 / 文件值 / 运行值 + 提示（设置页「配置对照」标签的数据源） |
| `GET /api/mihomo/service/safety` | 安全体检：启动前的风险清单（仪表盘横幅的数据源） |
| `GET /api/mihomo/routing/status` | 绑定状态：每个接口 → 出口代理组 → 生效/待应用 |
| `GET /api/mihomo/routing/netstatus` | 网络侧现状：接口块 / 网关 / 规则 |

### 9.2 备份与还原

| 备份 | 位置 | 谁生成 | 怎么还原 |
|---|---|---|---|
| config.yaml（插件写盘前） | `/usr/local/etc/mihomo/config.yaml.bak.<时间戳>`（留最近 20 份） | 设置页/策略页/编辑器 | 策略页「配置历史」→ 差异/恢复 |
| config.yaml（订阅前） | `/usr/local/etc/mihomo/config.yaml.bak.sub_<时间戳>` | 订阅脚本 | 同上（同一列表里） |
| config.xml（网络侧改动前） | `/conf/config.xml.mihomo-bak.<时间戳>` | 策略页「应用」/「撤销网络配置」 | 策略页「撤销网络配置」用最近一份 |
| 部署前整体备份 | `/usr/local/opnsense/_bak/os-mihomo/<时间戳>/` | `scripts/deploy.sh` | `scripts/rollback.sh` |

### 9.3 内置的"安全网"

- 写文件前一律 `mihomo -t` 校验，**不过就不落盘**（原文件保持不动）。
- 网络侧写 `config.xml` 后会检查 pf 里真的有 `route-to ... tun_mihomo`，没有就自动回滚。
- 服务停止/重启时会销毁残留的 `tun_mihomo`；启动前会检测 sing-box 冲突。
- 启动前校验配置：配置坏了，服务**拒绝启动**（而不是带着坏配置接管网络）。

### 9.4 三条"别做"的事

1. 别把 `external-controller` 改成 `0.0.0.0`（尤其别配空 secret）——那等于把你的代理配置接口公开在网络里。
2. 别在设了分流的机器上随手 `service mihomo stop`——被绑网段会断外网。
3. 别在 `# >>> os-mihomo:policy-routing` 里手改规则——下次「应用」会被覆盖（要加规则就加在区块外面）。
