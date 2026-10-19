#!/usr/bin/env python3
"""补一条词条：TUN 未开启时路由页的提醒"""
import io

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()
anchor = "    # ---- 「不修改」开关（P18）----\n"
block = ("    'TUN mode is off: the bindings below stay inactive until it is on. Enable it in Settings.':\n"
         "        'TUN 模式关着：下面的绑定在它打开之前都不会生效。到「设置」里打开再回来。',\n")
if block in t:
    print('已存在')
elif anchor in t:
    t = t.replace(anchor, block + anchor, 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print('词条已加')
else:
    raise SystemExit('锚点未找到')
