#!/usr/bin/env python3
"""P21 词条：小锁 / 图钉的提示文案（换掉旧复选框那两条）"""
import io
import re

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

# 1. 掉旧的：复选框的说明、小灰标「固定」
patterns = [
    r"^\s*'Tick = this plugin never writes this item.*\n(?:.*\n)?",
    r"^\s*'fixed': '.*',\n",
]
for pat in patterns:
    t2, cnt = re.subn(pat, '', t, count=1, flags=re.M)
    if cnt:
        t = t2
        print('已删:', pat[:46])
    else:
        print('!! 没找到:', pat[:46])

# 2. 加新的
anchor = "    'leave alone': '不修改',\n"
add = (anchor
       + "    'Written by the plugin: on Apply the value above is written into the file. Click to leave the file alone instead.':\n"
         "        '由插件写入：点「应用」时按上面的值改配置文件；点一下改为「不修改」。',\n"
         "    'Leave alone: the plugin never writes this item, the file keeps whatever you wrote. Click to let the plugin write it here.':\n"
         "        '不修改：插件不碰这一项，文件里怎么写就怎么用；点一下改为「由插件写入」。',\n"
         "    'Fixed by the plugin, not editable here (see the help text).':\n"
         "        '固定值：插件写死，这里改不了（详见帮助）。',\n")
if 'Written by the plugin: on Apply' in t:
    print('新词条已在，跳过')
elif anchor in t:
    t = t.replace(anchor, add, 1)
    print('新词条已加')
else:
    print('!! 锚点未匹配')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
