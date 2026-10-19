#!/bin/sh
# 看路由策略页真实渲染出来的 grid 配置与行操作按钮
set -u
BASE=https://127.0.0.1
JAR=/tmp/p44_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" -o /tmp/p44-routing.html
python3 - <<'PY'
import io, re
t = io.open('/tmp/p44-routing.html', encoding='utf-8', errors='replace').read()
print('页面字节:', len(t))
i = t.find('UIBootgrid(')
print('=== UIBootgrid 配置 ===')
print(t[i-600:i+900])
print()
print('=== 行操作按钮相关的类/属性 ===')
for kw in ('row-actions', 'edit_dialog_id', 'fa-pencil', 'fa-trash', 'btn-edit', 'editDlg', 'command'):
    print('  %-18s %d 次' % (kw, t.count(kw)))
m = re.search(r'<div class="modal fade" id="([^"]+)"', t)
print()
print('对话框 id:', m.group(1) if m else '未找到')
print()
print('=== 对话框里 interface / target 的 html ===')
for kw in ('id="mihomo.interface"', 'id="mihomo.target"', 'id="mihomo.scope"', 'id="mihomo.firewall"'):
    j = t.find(kw)
    print('  %s -> %s' % (kw, ('...' + t[j:j+180].replace('\n', ' ')) if j > 0 else '未找到'))
PY
