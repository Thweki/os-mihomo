#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 诊断：策略行的 get_rule 返回什么；编辑对话框怎么取字段；set_rule 能不能改
set -u
BASE=https://127.0.0.1
JAR=/tmp/p36_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## 1. search_rule 返回的行（字段名） ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/search_rule/?rowCount=10&current=1" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  total:', d.get('total'))
for r in d.get('rows',[]):
    print('  uuid:', r.get('uuid'))
    for k,v in sorted(r.items()):
        print('     %-12s = %r' % (k, v))
    print()
"

UUID=$(curl -sk -b "$JAR" "$BASE/api/mihomo/routing/search_rule/?rowCount=10&current=1" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rows=d.get('rows',[])
print(rows[0]['uuid'] if rows else '')
")

echo "########## 2. get_rule/<uuid> 返回的 JSON ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/get_rule/$UUID" | python3 -m json.tool

echo
echo "########## 3. UIBootgrid 是怎么把行数据填进对话框的 ##########"
for f in /usr/local/opnsense/www/js/ui-bootgrid.js /usr/local/opnsense/www/js/opnsense_ui.js /usr/local/opnsense/www/js/jquery.bootgrid.js; do
    [ -f "$f" ] && echo "  -- $f: $(grep -c 'edit_dialog\|setNode\|ui-bootgrid' "$f" 2>/dev/null) 处"
done
grep -rn 'edit_dialog' /usr/local/opnsense/mvc/app/views/layout_partials/base_dialog.volt 2>/dev/null | head -3 | sed 's/^/    /'
echo "  --- base_dialog.volt 里字段 id 的写法 ---"
grep -n 'id=\|form-' /usr/local/opnsense/mvc/app/views/layout_partials/base_dialog.volt 2>/dev/null | head -12 | sed 's/^/    /'
