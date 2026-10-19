#!/usr/bin/env python3
"""P18 文档更新：config-guide（不修改开关 / 行编辑）/ report §23 / TODO / logs"""
import io

# ---------------- 1. docs/config-guide.md ----------------
p = 'docs/config-guide.md'
t = io.open(p, encoding='utf-8').read()

old = ('| 只改某一项（日志等级 / MTU / 嗅探…） | 设置页 | 「应用」默认只写**你改过的项** —— '
       '没动过的值不会被顺手覆盖；想让页面说了算就切到「以页面为准，全部写入文件」 |')
new = ('| 只改某一项（日志等级 / MTU / 嗅探…） | 设置页 | 先把那一项前面的**「不修改」勾去掉**（默认都勾着），'
       '点「应用」就只写这一项；其余项插件一概不碰 —— 连文件里没有的键也不会给你加上 |\n'
       '| 什么都不想它动 | 设置页 | 保持所有「不修改」都勾着（默认）。点「应用」只会说一句"配置文件保持原样" |')
t = t.replace(old, new, 1)

# 对照页标记说明
old2 = '### 第 0 步的补充：哪些项目「运行中」那栏会是空的'
new2 = ('### 第 0 步的补充：「不修改」标记\n\n'
        '设置页每一项前面都有一条**「不修改」**（默认勾上）。勾着的项，对照表在「页面」那一列会多一个灰底小标：\n'
        '**含义是"页面上的值不会写进文件，文件里你写的是什么就还是什么"** —— 所以看到「页面」和「文件」不一致时，\n'
        '先看有没有这个标记：有标记 = 正常（你说了算），没标记 = 插件会让文件跟上页面（点「应用」即可）。\n\n'
        '### 第 0 步的补充：哪些项目「运行中」那栏会是空的')
t = t.replace(old2, new2, 1)

# 受管键表头加一句：默认全部不修改
old3 = '## 4. 本插件管理的键（设置页「应用」会写的范围）'
if old3 in t:
    t = t.replace(old3, old3 + '\n\n> 注：**默认一项都不写** —— 设置页每一项前面的「不修改」勾默认勾上；\n'
                              '> 想让它按页面写，先把那一项的勾去掉。', 1)
else:
    print('!! §4 标题未匹配（跳过）')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('config-guide.md 已更新')

# ---------------- 2. TODO ----------------
p = 'TODO.md'
t = io.open(p, encoding='utf-8').read()
block = """## P18 修「策略只能加/删不能改」+ 每项「不修改」开关（本轮）

- [x] **修策略行编辑打不开**：框架的 `setFormData()` 在 `<select>` 绑到**纯字符串**时抛
      `TypeError: Cannot use 'in' operator to search for 'length' in opt2` —— 异常中断整个对话框填充，
      模态框压根不显示（新增能用是因为空值走的是另一条分支，所以"只能加/删不能改"）
      → `get_rule` 在**返回给对话框的数据**里把 interface/target 转成 `{值:{value,selected}}`（模型仍是 TextField）
- [x] 顺手删掉路由页里为绕开这个坑写的一堆 JS（fillSelect/refreshSelects/optionCache/show.bs.modal）
- [x] **每项「不修改」开关**（设置页）：默认全部勾着 = 插件一项都不写；取消勾 = 这一项由页面写入
      - 语义统一：config.yaml / rc.conf.d（开机自启）/ 环境文件（订阅凭据）/ Cron（自动更新）都一样
      - 状态存模型新字段 `mihomo.managed`（允许写入的字段 id，逗号分隔），跟着表单一起提交
      - 勾着的行控件禁用变灰；底部实时显示「将写入：X、Y」；两个小按钮切换「全部勾选/全部取消」
      - 「配置对照」里带「不修改」标记，解释"页面和文件不一致是正常的"
- [x] `Config::selectManagedKeys()` 改成按「不修改」开关挑选（一个键多字段 / 一个字段多键都覆盖）
- [x] 回归测试第 15 节重写（11 条断言）；五个页面 0 报错；实测：勾着 = 文件 md5 不变、只开 MTU 一项 = 只写 MTU
- [x] 浏览器实测：行编辑对话框正常打开（接口/规则范围/出口/防火墙规则四个下拉全部带正确选中值）、
      改值保存后 config.xml 生效、再改回来；设置页 23 条开关（控制器地址/端口共用一个）、
      取消勾选后输入框可编辑且提示「将写入：启用 mihomo」，应用后提示"所有项都是「不修改」，配置文件保持原样"

## P17 修报错 + IPv6 选项 + 「只写入我改过的项」（上一轮）"""
t = t.replace('## P17 修报错 + IPv6 选项 + 「只写入我改过的项」（本轮）', block, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('TODO.md 已更新')

# ---------------- 3. report.md ----------------
p = 'docs/report.md'
t = io.open(p, encoding='utf-8').read()
section = """## 23. P18：修好「策略只能加/删，不能改」+ 设置项「不修改」

### 23.1 用户报的问题：策略行只能新增/删除，改不了

**现象**：点某一行的铅笔图标 → 什么都不发生（对话框不弹）；新增却正常。

**排查过程**（浏览器实测 + 读框架源码）：

1. 用 CDP 打开对话框：`#dialog_policy_rule` 停在 `class="modal fade"`（没有 `in`）→ 根本没显示；
2. 对话框里 `#mihomo.interface` 的 `<option>` 数量是 **0**（页面加载时明明填过）；
3. 直接在控制台调框架的填表函数：

```js
setFormData('frm_dialog_policy_rule', {mihomo:{interface:'opt2'}})
// TypeError: Cannot use 'in' operator to search for 'length' in opt2
```

**根因**：`/usr/local/opnsense/www/js/opnsense.js` 的 `setFormData()` 在处理 `<select>` 时，
会把值当作"选项字典"（`{key: {value, selected}}`）。接口/出口这两个字段的模型类型是 **TextField**，
`get_rule` 返回的是纯字符串 `"opt2"` → 走进 `$.each('opt2', …)` 分支 → jQuery 的 `isArrayLike()`
里执行 `'length' in 'opt2'` → **抛 TypeError** → 异常从 `mapDataToFormUI` 的成功回调里冒出去，
`dfObj.resolve()` 永远不会执行 → 对话框永远不显示。

**新增为什么能用**：新建时值都是空串，`!!'' === false` 会短路，不抛错，所以一路正常。

**修法**（不动模型、不动核心 JS）：`Api\\RoutingController::getRuleAction()` 在**返回给对话框的数据**里
把 `interface` / `target` 转成框架要的字典形状，标签用友好名（`LanUS (opt2) — 192.168.10.0/24`），
当前值不在列表里时也补一条（接口改名/分组删除后编辑不会丢值）。模型里仍是 TextField，
校验与存储不变。同时删掉路由页里为绕开这个坑写的一堆 JS
（`fillSelect` / `refreshSelects` / `optionCache` / `show.bs.modal` 钩子）。

### 23.2 新增：设置页每项「不修改」（默认全部不修改）

用户要求"设置里所有可选项都要有'不修改'，指不覆盖默认配置"。做成**逐项开关**：

| | 行为 |
|---|---|
| 勾上（默认） | 插件完全不碰这一项：config.yaml 里原本怎么写就怎么用，**文件里没有的键也不会加上**；`rc.conf.d`（开机自启）、订阅环境文件、Cron（自动更新）同理 |
| 取消勾 | 这一项由页面负责写入（点「应用」时按页面上的值改文件） |

* 状态存进模型新字段 `mihomo.managed`（= 允许写入的字段 id，逗号分隔），跟着表单一起提交，**刷新后仍在**；
* 勾着的行控件会被禁用并变灰，底部实时显示「将写入：X、Y」或「所有项都是「不修改」……」；
* 两个小按钮：**全部取消勾选（都由页面写）** / **全部勾上（都不修改）**；
* 「配置对照」标签里，没交给插件的项在「页面」列后面带一个灰底**「不修改」**标记，
  用来解释"页面和文件不一致是正常的"；
* 一个 YAML 键由多个输入组成时共用一个开关（如 `external-controller` = 绑定地址 + 端口）；
  一个输入管一组键时也一样（域名嗅探 = 8 个键）；
* `Config::selectManagedKeys($keys, $ownedFields, $fileValues)` 重写为按这个清单挑选要写的键，
  并回报"没写、但文件里和页面不一样"的项。

### 23.3 实测

```
浏览器（真实点击）：
  行编辑    点铅笔 → 对话框弹出（modal … in）；接口=opt2、规则范围=仅国外、出口=US-AUTO、防火墙规则=创建
            改成 出口=US-EXIT、描述=edit-test → 保存 → config.xml 里确实变了；再改回原值 ✅
  设置页    23 条开关，全部默认勾上，对应输入框全部 disabled ✅
            取消「启用 mihomo」的勾 → 输入框可编辑，提示「将写入：启用 mihomo」→ 应用
            → 对话框：所有项都是「不修改」，配置文件保持原样。服务将在开机时自动启动。（只写了 rc.conf.d）
            点「全部取消勾选」→ 提示列出全部 24 项；点「全部勾上」→ 回到"什么都不写" ✅

接口/文件级：
  默认（全不修改）应用 → config.yaml md5 不变 ✅
  只把 MTU 交给插件 → "配置文件已更新，写入了 1 项：MTU"，md5 仍不变（值本来就一样）✅
  模型 mihomo.managed 持久化 ✅  对照表 managed 标记正确（只有 MTU 没有标记）✅
  回归测试：第 15 节 11 条断言全过，总计 0 失败 ✅
  五个页面 0 PHP 报错；默认路由/出网/LanDirect 均未变 ✅
```

---

"""
t = t.replace('## 22. P17：修好「应用」报错 + IPv6 选项 + 只写入我改过的项', section + '## 22. P17：修好「应用」报错 + IPv6 选项 + 只写入我改过的项', 1)
t = t.replace('22. [P17：修好「应用」报错 + IPv6 选项 + 只写入我改过的项](#22-p17修好应用报错--ipv6-选项--只写入我改过的项)',
              '22. [P17：修好「应用」报错 + IPv6 选项 + 只写入我改过的项](#22-p17修好应用报错--ipv6-选项--只写入我改过的项)\n'
              '23. [P18：修好「策略只能加/删，不能改」+ 设置项「不修改」](#23-p18修好策略只能加删不能改--设置项不修改)',
              1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('report.md 已更新')

# ---------------- 4. logs ----------------
log = io.open('logs/2026-10-18-session.md', encoding='utf-8').read()
log += """

---

## 2026-10-19 09:0x-09:5x P18：策略行编辑修复 + 设置「不修改」开关

### 用户反馈
1. 路由策略的行**只能新增/删除，不能修改**；
2. 设置页所有可选项要加「不修改」（不覆盖默认配置），或者做一个"全局覆盖"页，默认不修改、可选覆盖。

### 排查 1：行编辑打不开（浏览器实测 + 框架源码）
- `.command-edit` 点击后 `#dialog_policy_rule` 仍是 `class="modal fade"`（没 `in`）→ 对话框没显示
- `#mihomo.interface` 的 option 数量为 0；控制台直接调 `setFormData('frm_dialog_policy_rule', {mihomo:{interface:'opt2'}})`
  → `TypeError: Cannot use 'in' operator to search for 'length' in opt2`
- 根因：opnsense.js 的 setFormData 把 <select> 的值当"选项字典"；TextField 返回纯字符串 →
  `$.each('opt2', …)` → jQuery isArrayLike 里 `'length' in 'opt2'` 抛异常 → mapDataToFormUI 的 resolve 不执行 → 对话框永不显示
- 新增能用：空值 `''` 会短路不抛错 → 于是"只能加/删不能改"
- 修法：get_rule 返回给对话框时把 interface/target 转成字典形状（标签用友好名，当前值不在列表也补一条）；
  删掉路由页里的 fillSelect/refreshSelects/optionCache/show.bs.modal 绕坑代码
- 实测：对话框正常弹出，四个下拉选中值正确；改值保存 → config.xml 生效；再改回 ✅

### 排查 2：设置「不修改」
- 模型新增 TextField `mihomo.managed` = 允许写入的字段 id 清单（逗号分隔）
- 设置页每行标签前注入一条「不修改」勾（默认勾上）；勾着 = 插件不碰（config.yaml / rc.conf.d / env / Cron 全一样）
- 勾着时控件 disabled + 变灰；底部实时「将写入：…」；两个小按钮"全部勾选/全部取消"
- Config::selectManagedKeys(keys, ownedFields, fileValues) 重写；对照表加 managed 标记（页面列显示「不修改」）
- 踩坑：`$('#mihomo.tun.mtu')` 这种 id 里带点的选择器是无效的（点=class），要用 getElementById；
  fieldLabel 取标签文字时要把自己塞的开关摘掉、且不能让 children().remove() 把 <b> 里的名字删掉
- 实测：全不修改 → md5 不变；只开 MTU → 写 1 项、md5 不变；managed 持久化；对照表标记正确；
  浏览器里取消勾选 → 可编辑 + 提示正确 → 应用提示"所有项都是「不修改」，配置文件保持原样"（只写了 rc.conf.d）
- 回归测试第 15 节重写（11 条断言），0 失败；五个页面 0 报错；网络侧/服务/默认路由均未变
"""
io.open('logs/2026-10-18-session.md', 'w', encoding='utf-8', newline='\n').write(log)
print('logs 已追加')
