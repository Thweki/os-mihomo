#!/bin/sh
set -u
python3 - <<'PY'
import io, re
t = io.open('/usr/local/opnsense/www/js/opnsense.js', encoding='utf-8', errors='replace').read()
m = re.search(r'function setFormData', t)
seg = t[m.start(): m.start() + 9000]
# 只打印 select 分支的后半段与 input/checkbox 分支
i = seg.find('// default "dictionary" type select items')
print('########## setFormData 的 select 分支后半段 ##########')
print(seg[i:i+2600])
PY
echo
echo "########## UIBootgrid 构造函数的 options 处理 ##########"
python3 - <<'PY'
import io
t = io.open('/usr/local/opnsense/www/js/opnsense_bootgrid.js', encoding='utf-8', errors='replace').read()
lines = t.splitlines()
for i, l in enumerate(lines[:90], 1):
    print('  %3d %s' % (i, l))
PY
