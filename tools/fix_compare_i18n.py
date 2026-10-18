#!/usr/bin/env python3
"""配置对照：列头避开核心词库（File / Running 在核心 .mo 里已有译文，工具不允许覆盖）"""
import io

p = 'src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt'
t = io.open(p, encoding='utf-8').read()
t = t.replace("{{ lang._('File') }}", "{{ lang._('File (config.yaml)') }}")
t = t.replace("{{ lang._('Running') }}", "{{ lang._('Running (memory)') }}")
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('视图列头:', t.count('File (config.yaml)'), t.count('Running (memory)'))

p2 = 'tools/i18n_translate.py'
d = io.open(p2, encoding='utf-8').read()
for drop in ["    'File': '文件（config.yaml）',\n", "    'Running': '运行中（内存）',\n", "    'IPv6': 'IPv6',\n"]:
    d = d.replace(drop, '')
anchor = "    'Item': '项目',\n"
if anchor in d:
    d = d.replace(
        anchor,
        anchor + "    'File (config.yaml)': '文件（config.yaml）',\n    'Running (memory)': '运行中（内存）',\n",
        1,
    )
io.open(p2, 'w', encoding='utf-8', newline='\n').write(d)
for kw in ["'File':", "'Running':", "'IPv6':", "'File (config.yaml)':", "'Running (memory)':"]:
    print('  %-24s %d 处' % (kw, d.count(kw)))
