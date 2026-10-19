#!/usr/bin/env python3
"""P18 词条：每项「不修改」开关（设置页）+ 对照页标记；清掉旧的应用方式词条"""
import io

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

# ---------- 1. 删掉不再出现的旧词条 ----------
drop = [
    "    'Write only what I changed (recommended)': '只写入我改过的项（推荐）',\n",
    "    'Write all page settings into the file': '以页面为准，全部写入文件',\n",
    "    'All page settings will be written into the file.': '将把页面上的全部设置写入文件。',\n",
    "    'You have not changed anything yet — pressing Apply will not write to the file.':\n"
    "        '你还没改任何项 —— 现在点「应用」不会写文件。',\n",
    "    'Nothing was changed on this page, so the file was left alone.': '本次没有改动任何设置，文件保持原样。',\n",
    "    'The page and the file disagree on %d item(s), but you did not touch them, so they were left as they are: %s — press Import to use the file values in the page, or pick \"takes precedence\" to write them.':\n"
    "        '还有 %d 项页面和文件对不上，但你这次没改，所以文件里没动它们：%s —— 想用文件里的值刷新页面就点「从配置导入」；想以页面为准就选「全部写入文件」。',\n",
]
removed = 0
for item in drop:
    if item in t:
        t = t.replace(item, '', 1)
        removed += 1
print('清理旧词条:', removed, '/', len(drop))

# ---------- 2. 新增 ----------
anchor = "    # ---- 首绑顺序修复相关（P17）----\n"
block = """    # ---- 「不修改」开关（P18）----
    'leave alone': '不修改',
    'Tick = this plugin never writes this item: the file keeps whatever you wrote. Clear the tick to let the page write it.':
        '勾上 = 本插件完全不写这一项：文件里你怎么写的就怎么用；取消勾选才由页面写入。',
    'Each item has a "leave alone" tick (on by default): this plugin then never writes that item — the file keeps whatever you wrote, and what is not in the file stays out. Clear the tick to let the page write it.':
        '每一项前面都有一条「不修改」（默认勾上）：勾着的时候插件完全不碰这一项 —— 文件里你怎么写的就怎么用，'
        '文件里没有的也不会被加上；想让它按页面上的值写入，就把勾去掉。',
    'Every item is set to "leave alone" — pressing Apply will not touch the configuration file.':
        '所有项都是「不修改」—— 现在点「应用」不会改动配置文件。',
    'Every item is set to "leave alone", so the configuration file was not touched.':
        '所有项都是「不修改」，配置文件保持原样。',
    'The page and the file disagree on %d item(s), but those are still set to "leave alone", so the file keeps its own values: %s — clear "leave alone" on them to write the page values, or press Import to load the file values into the page.':
        '有 %d 项页面和文件对不上，但它们还是「不修改」，所以文件里保持原样：%s —— 想让页面说了算就把它们的勾去掉；'
        '想用文件里的值刷新页面就点「从配置导入」。',
    'Let the page write every item.': '让页面负责每一项（全部取消勾选）。',
    'Tick nothing (write all)': '全部取消勾选（都由页面写）',
    'Nothing is written to any file.': '勾上之后什么都不写。',
    'Tick everything (leave all alone)': '全部勾上（都不修改）',
    'Rows marked with a "leave alone" tag are items this plugin does not write: whatever you put in the file stays as it is.':
        '带「不修改」标记的项：本插件不会写它 —— 文件里你写的是什么，就还是什么。',
    'Internal list of the page fields this plugin may write.':
        '内部字段：允许本插件写入的页面项清单。',
"""
if anchor in t:
    t = t.replace(anchor, block + anchor, 1)
    print('新增词条完成（P18）')
else:
    raise SystemExit('锚点未找到')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
