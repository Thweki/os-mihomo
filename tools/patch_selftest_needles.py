#!/usr/bin/env python3
"""让自检的日志解析同时用「IP」和「域名」作为匹配串（sniffer 生效后日志里显示域名）"""
import io

p = 'src/usr/local/opnsense/scripts/mihomo/selftest.php'
t = io.open(p, encoding='utf-8').read()

before = t
t = t.replace(
    "[$rule, $group] = parse_match($newLog, $probeIp);",
    "[$rule, $group] = parse_match($newLog, [$probeIp, 'api.ipify.org']);"
)
t = t.replace(
    "[$rule2] = parse_match($newLog2, $domesticIp);",
    "[$rule2] = parse_match($newLog2, [$domesticIp, 'www.baidu.com']);"
)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)

print('changed:', t != before)
for i, line in enumerate(t.splitlines(), 1):
    if 'parse_match(' in line and 'function' not in line:
        print(' ', i, line.strip())
