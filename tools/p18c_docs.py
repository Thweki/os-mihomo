#!/usr/bin/env python3
"""P18c 文档：说明设置页底部那段提示/快捷按钮已按要求去掉"""
import io

# ---------------- docs/report.md ----------------
p = 'docs/report.md'
t = io.open(p, encoding='utf-8').read()
old = ("* 勾着的行控件会被禁用并变灰，底部实时显示「将写入：X、Y」或「所有项都是「不修改」……」；\n"
       "* 两个小按钮：**全部取消勾选（都由页面写）** / **全部勾上（都不修改）**；\n")
new = ("* 勾着的行控件会被禁用并变灰；\n"
       "  > 最初还在底部加了一段说明文字、两个快捷按钮（全部勾选/全部取消）和一行「将写入：…」的实时状态；\n"
       "  > 用户看过后要求去掉（\"去掉\"），于是这些一律删掉 —— 页面只留每项前面的「不修改」勾，\n"
       "  > 相关前端函数（fieldLabel / refreshManagedSummary 的显示部分、两个按钮的点击处理）也一并删除。\n")
if old in t:
    t = t.replace(old, new, 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('report.md 已更新')
else:
    print('!! report.md 未匹配（跳过）')

# ---------------- TODO.md ----------------
p = 'TODO.md'
t = io.open(p, encoding='utf-8').read()
old2 = ("      - 勾着的行控件禁用变灰；底部实时显示「将写入：X、Y」；两个小按钮切换「全部勾选/全部取消」\n")
new2 = ("      - 勾着的行控件禁用变灰（底部那段说明 + 两个快捷按钮 + 「将写入」实时状态按用户要求随后去掉）\n")
if old2 in t:
    t = t.replace(old2, new2, 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('TODO.md 已更新')
else:
    print('!! TODO.md 未匹配（跳过）')

# ---------------- logs ----------------
p = 'logs/2026-10-18-session.md'
t = io.open(p, encoding='utf-8').read()
t += ("\n### 追加（同日晚）：按用户要求精简设置页\n"
      "- 用户截图指出设置页底部那块（说明文字 + 「全部取消勾选」/「全部勾上」两个按钮 + 「所有项都是「不修改」……」状态行）要去掉\n"
      "- 处理：删掉这三块标记 + 相关 JS（fieldLabel、refreshManagedSummary 的显示逻辑、两个按钮的处理），\n"
      "  refreshManagedSummary 退化为只做 syncManagedHidden（隐藏字段同步）；词条里 7 条废弃条目一并清掉、补一条短提示\n"
      "- 页面现在只留：每项前面的「不修改」勾 + 底部原有的「应用 / 从配置导入 / 应用后重启服务」\n"
      "- 实测：8 个应消失的元素全为 0；开关（mihomo-managed-switch）、24 个字段、应用按钮均在；0 PHP 报错；\n"
      "  后端语义未动（全不修改时应用仍提示\"配置文件保持原样\"且 config.yaml md5 不变）\n")
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('logs 已追加')
