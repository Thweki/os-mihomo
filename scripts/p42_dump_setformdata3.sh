#!/bin/sh
set -u
python3 - <<'PY'
import io, re
p = '/usr/local/opnsense/www/js/opnsense_ui.js'
t = io.open(p, encoding='utf-8', errors='replace').read()
print('setFormData 出现次数:', len(re.findall(r'setFormData', t)))
m = re.search(r'(function\s+setFormData|setFormData\s*=\s*function|const\s+setFormData|let\s+setFormData)', t)
if not m:
    # 可能是通过别的名字导出的，打印所有含 FormData 的行
    for i, line in enumerate(t.splitlines(), 1):
        if 'etFormData' in line:
            print(i, line.strip()[:140])
else:
    print(t[m.start():m.start() + 3200])
PY
