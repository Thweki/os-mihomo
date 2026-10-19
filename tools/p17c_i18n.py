#!/usr/bin/env python3
"""补一条词条：Safety 的 IPv6 详情（指向新的设置项）"""
import io

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

old = ("    'The TUN device only carries IPv4, so IPv6 traffic leaves this firewall without going through mihomo. "
       "Set ipv6: false in the configuration to stop that, or add IPv6 handling separately.':\n"
       "        'TUN 设备只有 IPv4 地址，IPv6 流量会不经过 mihomo 直接出去。可在配置里设 ipv6: false 阻止它，或单独处理 v6。',\n")
new = ("    'IPv6 traffic does not go through mihomo (this tunnel only carries IPv4). Open Settings → IPv6 and clear "
       "\"IPv6 handling\" to turn it off; otherwise you can ignore this.':\n"
       "        'IPv6 流量不会经过 mihomo（这条通道只管 IPv4）。要关掉就到「设置 → IPv6」把「IPv6 处理」取消勾选；'\n"
       "        '不在意也可以不管。',\n")

if old in t:
    t = t.replace(old, new, 1)
    print('已替换 Safety IPv6 详情的词条')
elif new in t:
    print('已是最新，无需改动')
else:
    anchor = "    'IPv6 traffic bypasses the proxy': 'IPv6 流量不经过代理',\n"
    if anchor in t:
        t = t.replace(anchor, new + anchor, 1)
        print('已新增词条')
    else:
        raise SystemExit('锚点未找到')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
