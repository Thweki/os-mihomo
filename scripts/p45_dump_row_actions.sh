#!/bin/sh
set -u
python3 - <<'PY'
import io
p='/usr/local/opnsense/www/js/opnsense_bootgrid.js'
t=io.open(p,encoding='utf-8',errors='replace').read()
print('########## 行操作按钮 / 打开对话框的触发点 ##########')
print(t[t.find('    init_row_actions') if 'init_row_actions' in t else 0:0] or '')
import re
for m in re.finditer(r'(editDialog|edit_dialog|fa-pencil|fa-trash|rowActions|row_actions)', t):
    ln = t[:m.start()].count('\n')+1
    line = t.splitlines()[ln-1].strip()
    print('  %5d  %s' % (ln, line[:150]))
PY
