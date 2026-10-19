#!/usr/bin/env python3
"""P20 文档：哪些项没有「不修改」开关 + 设备名/协议栈写死"""
import io

# ---------------- 1. config-guide.md ----------------
p = 'docs/config-guide.md'
t = io.open(p, encoding='utf-8').read()

old_note = """> **默认一项都不写**：设置页每一项前面都有一条「不修改」（默认勾上）。
> 勾着 = 插件不碰这一项（文件里原本怎么写就怎么用，文件里没有的键也不会加上）；
> 想让它按页面上的值写，先把那一项的勾去掉。`rc.conf.d`（开机自启）、订阅环境文件、Cron（自动更新）同理。
"""
new_note = """> **默认一项都不写**：`config.yaml` 里的键前面都有一条「不修改」（默认勾上）。
> 勾着 = 插件不碰这一项（文件里原本怎么写就怎么用，文件里没有的键也不会加上）；
> 想让它按页面上的值写，先把那一项的勾去掉。
>
> 有两类项**没有**这条勾，它们始终随「应用」写入：
> * **设备名称 / 协议栈**：写死的（`tun_mihomo` / `gvisor`），页面上只读 ——
>   前者是防火墙规则按名字引用的接口，后者是 FreeBSD 上验证过的组合，改了只会把网络弄坏；
> * **插件自己的状态**（开机自启、订阅地址/密钥、订阅自动更新）：它们不在 `config.yaml` 里，
>   勾「不修改」没有意义（插件必须知道自己的状态），但仍然只有页面上的值说了算。
"""
if old_note in t:
    t = t.replace(old_note, new_note, 1)
    print('config-guide 说明已更新')
else:
    print('!! config-guide 说明未匹配')

old_dev = "| 设备名称 | `tun.device` | tun_mihomo | 要和防火墙规则里的一致，一般别改 |"
new_dev = "| 设备名称 | `tun.device` | **固定 tun_mihomo** | 页面只读：防火墙规则按这个名字引用接口 |"
old_stk = "| 协议栈 | `tun.stack` | gvisor | FreeBSD 上建议 gvisor |"
new_stk = "| 协议栈 | `tun.stack` | **固定 gvisor** | 页面只读：FreeBSD 上验证过的组合 |"
for a, b in ((old_dev, new_dev), (old_stk, new_stk)):
    if a in t:
        t = t.replace(a, b, 1)
        print('表行已更新:', b.split('|')[1].strip())
    else:
        print('!! 表行未匹配:', a[:40])

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)

# ---------------- 2. report.md ----------------
p = 'docs/report.md'
t = io.open(p, encoding='utf-8').read()
anchor = "### 23.4 后续（同日晚）：对照页只留表格\n"
add = """### 23.5 后续：不是每一项都需要「不修改」；设备名称 / 协议栈写死

用户指出：**不是每个设置都需要「不修改」**（例如「启用 mihomo」），并要求把
**设备名称（tun.device）与协议栈（tun.stack）** 写死、页面不可操作、默认覆盖配置文件。

| 类别 | 处理 |
|---|---|
| `config.yaml` 里的键（日志层级、模式、允许局域网、外部控制器、密钥、TUN 开关、自动路由、严格路由、MTU、DNS 四项、IPv6 处理、域名嗅探） | 保留「不修改」勾，默认不写 |
| **设备名称 / 协议栈** | 页面只读（禁用 + 小灰标「固定」），值恒为 `tun_mihomo` / `gvisor`；写配置时直接用常量，不看模型值 |
| **插件自己的状态**（开机自启、订阅地址/密钥、订阅自动更新） | 不给勾，始终随「应用」同步 |

实现：

* `Config::FIXED_SETTINGS`（写死项：字段 → YAML 键 + 固定值）、`Config::PLUGIN_OWNED_FIELDS`（插件自己的状态）、
  `Config::fieldsWithoutSwitch()`（前端不给开关的清单）、`Config::ownedFieldsWithDefaults()`（后端兜底：
  页面没传也照样写这些项）、`Config::fixedValue()`；
* 设置页把两个清单渲染进 JS（`ALWAYS_OWNED` / `FIXED`）：前者不装勾、后者禁用并强制显示固定值；
* 写入侧 `managedKeys()` 与对照页 `modelValues()` 都用 `fixedValue()`，所以即使配置文件被手工改过，
  写进去的仍然是固定值；
* 顺带把三处"每次都刷屏"的提示修成只在真的变化时才说话：`rc.conf.d` 的开机自启、
  订阅 env（`env.php` 值没变就不写文件也不打印）、Cron 任务（已在位且一致就静默）；
* 删除设置页里那个从来没生效的「更新后重启」复选框（`subscription.restartAfterUpdate`）——
  真正起作用的是订阅页按钮旁边那个勾。

实测：设置页现在 15 个「不修改」勾（正好是 `config.yaml` 的键）、2 个「固定」标记；
「启用 mihomo」「订阅地址」等可编辑且没有勾；设备名称/协议栈禁用且值为 `tun_mihomo` / `gvisor`；
点「应用」提示"写入了 13 项：… 设备名称、协议栈 …"，不再有多余的开机自启/env 提示；
回归测试第 15 节扩到 22 条断言，0 失败。

"""
if anchor in t:
    t = t.replace(anchor, add + anchor, 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('report.md 已更新')
else:
    print('!! report.md 锚点未匹配')

# ---------------- 3. TODO.md ----------------
p = 'TODO.md'
t = io.open(p, encoding='utf-8').read()
old = "- [x] **对照页精简**"
add2 = """- [x] **不是每项都要「不修改」**：`config.yaml` 的键才有勾；插件自己的状态（开机自启/订阅/自动更新）
      不给勾（始终同步）；**设备名称/协议栈写死**（页面只读 + 小灰标「固定」，写配置时用常量）
- [x] 三处刷屏提示改为只在变化时说话（rc.conf.d / 订阅 env / Cron）；删除没生效的「更新后重启」复选框
- [x] 回归测试第 15 节扩到 22 条断言（含写死项与兜底清单），0 失败
- [x] **对照页精简**"""
if old in t:
    t = t.replace(old, add2, 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('TODO.md 已更新')
else:
    print('!! TODO.md 未匹配')

# ---------------- 4. logs ----------------
p = 'logs/2026-10-18-session.md'
t = io.open(p, encoding='utf-8').read()
t += ("\n### 追加（同日晚 21:4x）：不是每项都要「不修改」+ 设备名/协议栈写死\n"
      "- 用户指出「启用 mihomo」这类项不需要「不修改」勾；并要求设备名称/协议栈写死、不可操作、默认覆盖配置文件\n"
      "- 处理：Config 增加 FIXED_SETTINGS / PLUGIN_OWNED_FIELDS / fieldsWithoutSwitch / ownedFieldsWithDefaults / fixedValue；\n"
      "  设置页 JS 用 ALWAYS_OWNED 决定不给勾、FIXED 决定禁用+显示固定值；写入侧与对照页都用 fixedValue；\n"
      "  修掉三处刷屏提示（rc.conf.d/env.php/Cron 只在变化时说话）；删掉设置页里没生效的「更新后重启」\n"
      "- 实测：15 个勾（正好是 config.yaml 的键）+ 2 个「固定」标记；启用 mihomo/订阅地址可编辑且没有勾；\n"
      "  设备名=tun_mihomo / 协议栈=gvisor 且禁用；应用提示「写入了 13 项：…设备名称、协议栈…」无多余提示；回归 0 失败\n")
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('logs 已追加')
