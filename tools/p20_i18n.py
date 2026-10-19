#!/usr/bin/env python3
"""P20 词条：写死项的小灰标 + 设备名/协议栈的固定说明；清掉不再出现的"""
import io

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

drop = [
    "    'Device name, must match the firewall rules (default tun_mihomo).': '设备名，必须和防火墙规则里的一致（默认 tun_mihomo）。',\n",
    "    'gvisor is recommended on FreeBSD.': 'FreeBSD 上建议 gvisor。',\n",
    "    'Restart After Update': '更新后重启',\n",
]
removed = 0
for item in drop:
    if item in t:
        t = t.replace(item, '', 1)
        removed += 1
    else:
        print('  !! 未匹配:', item.strip()[:70])
print('清理:', removed, '/', len(drop))

anchor = "    'leave alone': '不修改',\n"
add = (anchor
       + "    'fixed': '固定',\n"
         "    'Fixed (tun_mihomo): the firewall rules refer to this device name by hand.':\n"
         "        '固定为 tun_mihomo：防火墙规则里是按这个名字写的。',\n"
         "    'Fixed (gvisor): the combination verified on FreeBSD.':\n"
         "        '固定为 gvisor：FreeBSD 上验证过的组合。',\n")
if anchor in t and "'fixed': '固定'," not in t:
    t = t.replace(anchor, add, 1)
    print('新增词条完成（P20）')
else:
    print('新增无需改动')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
