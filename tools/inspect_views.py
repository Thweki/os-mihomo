#!/usr/bin/env python3
"""检查设置页/订阅页的结构：有哪些区块、有没有原始编辑器"""
import io
import re

t = io.open('src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt', encoding='utf-8').read()
print('=== settings.volt（%d 字节）区块与控件 ===' % len(t))
for m in re.finditer(r'<h3>(.*?)</h3>', t):
    print('  区块:', re.sub(r'\s+', ' ', m.group(1))[:80])
print('  textarea 数:', t.count('<textarea'))
for m in re.finditer(r'<textarea[^>]*>', t):
    print('   ', m.group(0)[:150])
for m in re.finditer(r'id="([a-zA-Z][-\w]*)"', t):
    pass
ids = sorted(set(re.findall(r'id="([a-zA-Z][-\w]*)"', t)))
print('  带 id 的元素:', ', '.join(ids[:40]))

print()
print('=== 设置页表单字段（forms/settings.xml）===')
f = io.open('src/usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml', encoding='utf-8').read()
for m in re.finditer(r'<field>\s*<id>([^<]+)</id>\s*<label>([^<]*)</label>', f):
    print('  %-42s %s' % (m.group(1), m.group(2)))

print()
print('=== 订阅页按钮/文案 ===')
s = io.open('src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/subscription.volt', encoding='utf-8').read()
for m in re.finditer(r"lang\._\('([^']+)'\)", s):
    print('  ', m.group(1))
