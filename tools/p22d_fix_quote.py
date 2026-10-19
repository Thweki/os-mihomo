#!/usr/bin/env python3
"""修掉 scrub 产生的一处单引号残留：p34 顶部的 PASS='${PASS}'（单引号里不展开）"""
import io

p = 'scripts/p34_verify_after_restart.sh'
t = io.open(p, encoding='utf-8').read()
old = "JAR=/tmp/p34_jar.txt; PASS='${PASS}'; BASE=https://127.0.0.1"
new = "JAR=/tmp/p34_jar.txt; BASE=https://127.0.0.1"
if old in t:
    io.open(p, 'w', encoding='utf-8', newline='\n').write(t.replace(old, new))
    print('p34 已修（PASS 由顶部块提供）')
else:
    for i, line in enumerate(t.split('\n'), 1):
        if '${PASS}' in line:
            print('  仍含 ${PASS} 的第 %d 行: %s' % (i, line.strip()))
