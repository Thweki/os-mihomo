#!/bin/sh
# 诊断：为什么「内网直达」规则没进 pf
set -u
echo "########## 1. igb0 上的全部 pf 规则 ##########"
pfctl -sr 2>/dev/null | grep 'on igb0' | head -20 | sed 's/^/  /'

echo
echo "########## 2. config.xml 里我们的规则原文 ##########"
python3 - <<'PY'
import re, io
t = io.open('/conf/config.xml', encoding='utf-8').read()
for block in re.findall(r'[ \t]*<rule\b[^>]*>.*?</rule>', t, re.S):
    if 'Mihomo' in block:
        print(block)
        print('  ----')
PY

echo
echo "########## 3. filter 生成器是否把我们的规则纳入（用 label 找） ##########"
pfctl -s labels 2>/dev/null | head -12 | sed 's/^/  /'

echo
echo "########## 4. 我们的规则在 config.xml 中的位置（与默认放行规则的相对顺序） ##########"
python3 - <<'PY'
import io
t = io.open('/conf/config.xml', encoding='utf-8').read()
i = t.find('<filter>')
seg = t[i:i+4000]
import re
for m in re.finditer(r'<rule\b[^>]*>\s*.*?<descr>([^<]*)</descr>', seg, re.S):
    print('  ', m.group(1)[:60])
PY

echo
echo "########## 5. pf 是否报错（filter reload 的输出） ##########"
configctl filter reload 2>&1 | head -10 | sed 's/^/  /'
echo "  --- reload 后再看 igb0 上的规则数 ---"
pfctl -sr 2>/dev/null | grep -c 'on igb0' | sed 's/^/    /'
pfctl -sr 2>/dev/null | grep 'on igb0' | grep -c '192.168.2' | sed 's/^/    含 192.168.2 的: /'
