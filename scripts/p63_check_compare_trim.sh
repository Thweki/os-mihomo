#!/bin/sh
# 核对：对照页只剩表格 + 刷新按钮；页面 0 报错；接口仍返回 rows
set -u
BASE=https://127.0.0.1
JAR=/tmp/p63_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" -o /tmp/p63-settings.html

echo "########## 1. 应消失的 ##########"
for kw in 'compare-notes' '同一个设置可能同时存在于三个地方' '带「不修改」标记的项' '运行中」那一列是内核' '内核不对外报告' '是自己写的（不是订阅生成的）' '没有任何接口走 mihomo' 'notes' ; do
    C=$(grep -c "$kw" /tmp/p63-settings.html || true)
    echo "  $([ "$C" = "0" ] && echo '已去掉 ✅' || echo "仍在 ❌ ($C)")  $kw"
done

echo
echo "########## 2. 应保留的 ##########"
for kw in 'compare-table' 'compare-body' 'compare-refresh' '配置对照' 'Running (memory)\|运行中' ; do
    C=$(grep -c "$kw" /tmp/p63-settings.html || true)
    echo "  $([ "$C" != "0" ] && echo '在 ✅' || echo '不见了 ❌')  $kw ($C)"
done

echo
echo "########## 3. 接口 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/inspect" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'), '| rows:', len(d.get('rows',[])), '| 还有 notes 字段吗:', 'notes' in d)
print('  前 3 行:', [(r['label'], r['state'], r.get('managed')) for r in d.get('rows',[])[:3]])
"

echo
echo "########## 4. 五个页面 ##########"
for page in "" settings subscription routing log; do
    OUT=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/$page")
    SZ=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
    ERR=$(printf '%s' "$OUT" | grep -c -E 'Fatal error|Parse error|Uncaught' || true)
    echo "  /ui/mihomo/$page  ${SZ} 字节  报错: ${ERR}"
done
rm -f "$JAR"
