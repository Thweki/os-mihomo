#!/bin/sh
set -u
python3 - <<'PY'
import io, re
p = '/usr/local/opnsense/www/js/opnsense.js'
t = io.open(p, encoding='utf-8', errors='replace').read()
for name in ('function getFormData', 'function saveFormData', 'function saveFormToEndpoint'):
    m = re.search(re.escape(name), t)
    if not m:
        print('  !! 未找到', name)
        continue
    print('  ===== %s =====' % name)
    seg = t[m.start(): m.start()+1200]
    for line in seg.splitlines():
        print('  ' + line)
    print()
PY
