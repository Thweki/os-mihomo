#!/usr/bin/env python3
"""P19 文档：对照页精简（去掉说明段落与提示框）"""
import io

# ---------------- report.md ----------------
p = 'docs/report.md'
t = io.open(p, encoding='utf-8').read()
anchor = "### 23.3 实测\n"
add = """### 23.4 后续（同日晚）：对照页只留表格

用户看过界面后要求去掉对照页的文字：

* 删掉表格上方那段说明（"同一个设置可能同时存在于三个地方……"）；
* 删掉表格前面的提示框（「运行中」那一列的说明、内核不报告的项、手写配置警告、受管区块说明、IPv6 提示等）；
* 后端 `Inspector::report()` 同步不再生成 `notes`（接口现在只返回 `rows` / `differs` / `missing` / `runtime`），
  10 条相关词条一并清掉；`html`/"不修改"标记与表格本身保留。

> 这些信息本来就分散在别处：手写配置的覆盖风险在**订阅页**有警告横幅、IPv6 绕过代理在**概览页体检**里会提示、
> 页面与文件不一致在表格的状态标签上一眼可见。要一次性看全，用命令 `config_truth.sh`。

实测：8 个应消失的元素/文案在页面里全部为 0；`compare-table` / `compare-body` / 刷新按钮都在；
`/api/mihomo/settings/inspect` 返回 19 行、不再有 `notes` 字段；五个页面 0 PHP 报错；回归测试 0 失败。

"""
if anchor in t:
    t = t.replace(anchor, add + anchor, 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('report.md 已更新')
else:
    print('!! report.md 锚点未匹配')

# ---------------- TODO.md ----------------
p = 'TODO.md'
t = io.open(p, encoding='utf-8').read()
old = "- [x] 浏览器实测：行编辑对话框正常打开"
add2 = """- [x] **对照页精简**：去掉表格上方的说明段落与全部提示框（Inspector::report 不再生成 notes，
      10 条词条清理）；页面只留三项对照表 + 刷新按钮
- [x] 浏览器实测：行编辑对话框正常打开"""
if old in t:
    t = t.replace(old, add2, 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('TODO.md 已更新')
else:
    print('!! TODO.md 未匹配')

# ---------------- logs ----------------
p = 'logs/2026-10-18-session.md'
t = io.open(p, encoding='utf-8').read()
t += ("\n### 追加（同日晚 21:3x）：配置对照页只留表格\n"
      "- 用户截图要求去掉对照页上方的说明段落与 4 个提示框\n"
      "- 处理：settings.volt 去掉 `<p>` 与 `#compare-notes` 容器 + renderCompare 里的 notes 渲染；\n"
      "  Inspector::report() 不再生成 notes（接口只返回 rows/differs/missing/runtime）；清掉 10 条词条；\n"
      "  config-guide §6 相应改写（不再提\"页面下方提示区\"）\n"
      "- 实测：8 个应消失元素/文案 = 0；表格与刷新按钮在；inspect 接口 19 行且无 notes；五页 0 报错；回归 0 失败\n")
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('logs 已追加')
