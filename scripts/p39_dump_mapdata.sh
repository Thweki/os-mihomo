#!/bin/sh
set -u
echo "########## mapDataToFormUI 定义在哪儿 ##########"
grep -rln 'function mapDataToFormUI\|mapDataToFormUI *=' /usr/local/opnsense/www/js/ 2>/dev/null | sed 's/^/  /'

F=$(grep -rln 'mapDataToFormUI' /usr/local/opnsense/www/js/ 2>/dev/null | head -3)
for f in $F; do
    echo "  -- $f"
done

echo
echo "########## 实现 ##########"
G=/usr/local/opnsense/www/js/opnsense_ui.js
[ -f "$G" ] || G=$(echo "$F" | head -1)
python3 - "$G" <<'PY'
import io,sys,re
p=sys.argv[1]
t=io.open(p,encoding='utf-8',errors='replace').read()
i=t.find('mapDataToFormUI')
i=t.find('mapDataToFormUI', i+10)
# find function definition
for m in re.finditer(r'(function\s+mapDataToFormUI|mapDataToFormUI\s*=\s*function|const mapDataToFormUI)', t):
    print(t[m.start()-200:m.start()+2600])
    break
else:
    print('未找到定义（只有调用）')
PY
