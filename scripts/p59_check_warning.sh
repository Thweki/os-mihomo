#!/bin/sh
set -u
python3 - <<'PY'
import io, re
t = io.open('/tmp/p58.html', encoding='utf-8', errors='replace').read()
for m in re.finditer(r'(Warning|Notice|Deprecated|Fatal error)[^<]{0,300}', t):
    print(repr(m.group(0))[:400])
    print('---')
PY
echo "########## 页面里有几个并发的开关相关脚本片段 ##########"
grep -c 'data-managed-for' /tmp/p58.html
grep -o 'mihomo-managed-switch' /tmp/p58.html | head -3
echo "########## PHP 错误日志尾部 ##########"
tail -5 /var/lib/php/tmp/PHP_errors.log 2>/dev/null
