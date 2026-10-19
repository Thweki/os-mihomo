#!/bin/sh
# 验收：设置页 IPv6 选项 + 应用方式 + 配置对照的运行值补全
set -u
BASE=https://127.0.0.1
JAR=/tmp/p35_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## 1. 设置页新元素（中文） ##########"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" -o /tmp/p35-settings.html
python3 - <<'PY'
t = open('/tmp/p35-settings.html', encoding='utf-8').read()
for kw in ('IPv6 处理', 'DNS 返回 IPv6', '只写入我改过的项', '以页面为准，全部写入文件',
           'changed-summary', 'mihomo.general.ipv6', 'mihomo.dns.ipv6', '配置对照'):
    print('  %-26s %s' % (kw, '有 ✅' if kw in t else '没有 ❌'))
print('  PHP 报错:', '有 ❌' if ('Fatal error' in t or 'PHP Error' in t) else '无 ✅')
PY

echo
echo "########## 2. 配置对照：运行中那栏是否补全 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/inspect" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'), '| 不一致:', d.get('differs'), '| 文件未写:', d.get('missing'), '| 运行值可用:', d.get('runtime'))
print()
print('  %-16s %-16s %-18s %-18s %s' % ('项目','页面','文件','运行中','状态'))
print('  ' + '-'*86)
for r in d.get('rows', []):
    print('  %-16s %-16s %-18s %-18s %s' % (
        r['label'][:14], (r['model'] or '—')[:14], (r['file'] or '—')[:16],
        (r['runtime'] or '—')[:16], r['state'] + ('（仅运行值）' if r.get('runtime_only') else '')))
print()
print('  提示:')
for n in d.get('notes', []):
    print('   [%s] %s' % (n['level'], n['text'][:100]))
"

echo
echo "########## 3. 体检（IPv6 项现在指向设置页开关） ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/service/safety" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for i in d.get('items',[]):
    print('   [%-7s] %-24s %s' % (i['level'], i['title'][:22], i['detail'][:70]))
"
rm -f "$JAR"
