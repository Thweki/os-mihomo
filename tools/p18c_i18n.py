#!/usr/bin/env python3
"""P18c：去掉页面上已删除的那段提示/按钮/状态行的词条，补一条新的短提示"""
import io

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

drop = [
    # 设置页底部那段提示 + 两个快捷按钮 + 实时"将写入"（用户要求去掉）
    "    'Each item has a \"leave alone\" tick (on by default): this plugin then never writes that item — the file keeps whatever you wrote, and what is not in the file stays out. Clear the tick to let the page write it.':\n"
    "        '每一项前面都有一条「不修改」（默认勾上）：勾着的时候插件完全不碰这一项 —— 文件里你怎么写的就怎么用，'\n"
    "        '文件里没有的也不会被加上；想让它按页面上的值写入，就把勾去掉。',\n",
    "    'Every item is set to \"leave alone\" — pressing Apply will not touch the configuration file.':\n"
    "        '所有项都是「不修改」—— 现在点「应用」不会改动配置文件。',\n",
    "    'Let the page write every item.': '让页面负责每一项（全部取消勾选）。',\n",
    "    'Tick nothing (write all)': '全部取消勾选（都由页面写）',\n",
    "    'Nothing is written to any file.': '勾上之后什么都不写。',\n",
    "    'Tick everything (leave all alone)': '全部勾上（都不修改）',\n",
    "    'Will be written': '将写入',\n",
]
removed = 0
for item in drop:
    if item in t:
        t = t.replace(item, '', 1)
        removed += 1
print('清理废弃词条:', removed, '/', len(drop))

add_anchor = "    'leave alone': '不修改',\n"
add = (add_anchor
       + "    'Tick \"leave alone\" = this plugin never writes that item.':\n"
         "        '勾上「不修改」= 本插件不写这一项。',\n")
if add_anchor in t and "Tick \"leave alone\" = this plugin" not in t:
    t = t.replace(add_anchor, add, 1)
    print('新短提示词条已加')
else:
    print('新短提示无需改动')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
