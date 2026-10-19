#!/bin/sh
# 验收「不修改」开关：默认不写、勾选后只写那一项、状态持久、文件校验和
set -u
BASE=https://127.0.0.1
JAR=/tmp/p57_jar.txt
PASS='${OPN_PW}'
CFG=/usr/local/etc/mihomo/config.yaml
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }
SETM() { POST /api/mihomo/settings/set "{\"mihomo\":{\"managed\":\"$1\"}}" > /dev/null; }
APLY() { POST /api/mihomo/settings/apply '{"restart":0}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('   ', m)
if d.get('message'): print('   !! ', str(d['message'])[:300])
"; }

echo "########## 0. 文件现在的样子（校验和 + 关键行） ##########"
SUM0=$(md5 -q "$CFG")
echo "  md5: $SUM0"
grep -n 'mtu\|^ipv6\|^mode' "$CFG" | head -5 | sed 's/^/    /'

echo
echo "########## 1. 默认：所有项都是「不修改」→ 应用应该什么都不写 ##########"
SETM ''
APLY
SUM1=$(md5 -q "$CFG")
echo "  md5 一致: $([ "$SUM0" = "$SUM1" ] && echo '是 ✅' || echo '否 ❌')"

echo
echo "########## 2. 只把 MTU 交给插件（值本来就一样）→ 只写这一项 ##########"
SETM 'mihomo.tun.mtu'
APLY
SUM2=$(md5 -q "$CFG")
echo "  md5 一致: $([ "$SUM1" = "$SUM2" ] && echo '是 ✅（值没变，文件没被乱动）' || echo '否 ❌')"

echo
echo "########## 3. 状态持久化：模型里的 managed 还在吗 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/get" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  mihomo.managed =', repr(d.get('mihomo',{}).get('managed')))
"

echo
echo "########## 4. 对照表：没交给插件的项应该标 managed=false ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/inspect" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  %-18s %-14s %-14s %s' % ('项目','页面','文件','不修改?'))
for r in d.get('rows', []):
    print('  %-18s %-14s %-14s %s' % (r['label'][:16], (r['model'] or '—')[:12], (r['file'] or '—')[:12],
        '是' if r.get('managed') is False else ''))
"

echo
echo "########## 5. 收尾：全部恢复「不修改」 ##########"
SETM ''
APLY
SUM3=$(md5 -q "$CFG")
echo "  md5 仍与最初一致: $([ "$SUM0" = "$SUM3" ] && echo '是 ✅' || echo '否 ⚠️')"
echo "  managed = $(curl -sk -b "$JAR" "$BASE/api/mihomo/settings/get" | python3 -c "import json,sys; print(repr(json.load(sys.stdin).get('mihomo',{}).get('managed')))")"
rm -f "$JAR"
