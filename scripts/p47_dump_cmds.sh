#!/bin/sh
set -u
python3 - <<'PY'
import io
p='/usr/local/opnsense/www/js/opnsense_bootgrid.js'
lines=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
def show(a,b,title):
    print('########## %s (行 %d-%d) ##########' % (title,a,b))
    for i in range(a-1,min(b,len(lines))):
        print('  %4d %s' % (i+1, lines[i]))
    print()
show(1935,1960,'行里的命令按钮')
show(2160,2270,'打开编辑对话框 / 保存')
PY
