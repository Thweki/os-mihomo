#!/usr/bin/env python3
"""打印 Mihomo.xml 设置模型（除 policyRouting）的字段清单，供文档映射表使用"""
import io
import re

t = io.open('src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.xml', encoding='utf-8').read()
i = t.find('<items>')
j = t.find('<policyRouting>')
seg = t[i:j]

for m in re.finditer(r'<(\w+)>\s*(.*?)\s*</\1>', seg, re.S):
    name, body = m.group(1), m.group(2)
    if not body.lstrip().startswith('<'):
        continue
    print('[' + name + ']')
    for f in re.finditer(r'<(\w+) type="(\w+)">(.*?)</\1>', body, re.S):
        fn, ft, fb = f.group(1), f.group(2), f.group(3)
        d = re.search(r'<Default>([^<]*)</Default>', fb)
        opt_block = re.search(r'<OptionValues>(.*?)</OptionValues>', fb, re.S)
        opts = re.findall(r'<(\w+)>([^<]*)</\1>', opt_block.group(1)) if opt_block else []
        print('   %-22s %-14s 默认=%-14s %s' % (
            fn, ft, (d.group(1) if d else '-'), ', '.join('%s=%s' % o for o in opts)))
