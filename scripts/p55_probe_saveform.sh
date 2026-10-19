#!/bin/sh
set -u
python3 - <<'PY'
import io, re
p = '/usr/local/opnsense/www/js/opnsense_ui.js'
t = io.open(p, encoding='utf-8', errors='replace').read()
m = re.search(r'saveFormToEndpoint\s*=\s*function|function\s+saveFormToEndpoint', t)
if m:
    print(t[m.start(): m.start()+1500])
else:
    print('未找到 saveFormToEndpoint：')
    for i, line in enumerate(t.splitlines(), 1):
        if 'saveFormToEndpoint' in line:
            print(i, line.strip()[:150])
PY
