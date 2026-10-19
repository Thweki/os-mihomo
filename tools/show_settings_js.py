#!/usr/bin/env python3
"""打印 settings.volt 里表单装载/应用/导入三段 JS 的原文，便于精确替换"""
import io

t = io.open('src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt', encoding='utf-8').read()
for kw in ('mapDataToFormUI', "\\$('#applyAct')", "\\$('#importAct')"):
    key = kw.replace('\\', '')
    i = t.find(key)
    print('=' * 24, key, i)
    print(t[max(0, i - 380):i + 1300])
    print()
