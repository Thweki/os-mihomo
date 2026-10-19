#!/usr/bin/env python3
"""看看对照页当前的 JS 与标记"""
import io

t = io.open('src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt', encoding='utf-8').read()
i = t.find('function renderCompare')
j = t.find('原始配置编辑器')
print('====== renderCompare ======')
print(t[i:i + 1400])
print('====== 标记 ======')
k = t.find('id="compare"')
print(t[k - 900:k + 1400])
