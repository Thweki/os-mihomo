#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 验收「配置对照」：API 返回 + 设置页第三个标签 + 体检里的 IPv6 提示
set -u
BASE=https://127.0.0.1
JAR=/tmp/p27_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## 1. /api/mihomo/settings/inspect ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/inspect" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'), '| runtime:', d.get('runtime'), '| 不一致:', d.get('differs'), '| 文件未写:', d.get('missing'))
print()
print('  %-22s %-18s %-20s %-14s %s' % ('项目','页面','文件','运行','状态'))
print('  ' + '-'*88)
for r in d.get('rows', []):
    print('  %-22s %-18s %-20s %-14s %s' % (
        r['label'][:20], (r['model'] or '—')[:16], (r['file'] or '—')[:18],
        (r['runtime'] or '—')[:12], r['state'] + ('（仅运行值）' if r.get('runtime_only') else '')))
print()
print('  提示:')
for n in d.get('notes', []):
    print('   [%s] %s' % (n['level'], n['text'][:90]))
"

echo
echo "########## 2. 设置页第三个标签 + 列头（中文） ##########"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" -o /tmp/p27-settings.html
python3 - <<'PY'
import re
t = open('/tmp/p27-settings.html', encoding='utf-8').read()
for kw in ('配置对照', '项目', '页面（设置）', '文件（config.yaml）', '运行中（内存）', 'compare-body', 'compare-refresh'):
    print('  %-18s %s' % (kw, '有 ✅' if kw in t else '没有 ❌'))
m = re.search(r'<div id="compare".{0,700}', t, re.S)
print('  --- 区块片段 ---')
print('  ' + re.sub(r'\s+', ' ', m.group(0))[:420] if m else '  (没找到)')
print('  PHP 报错:', '有 ❌' if ('Fatal error' in t or 'PHP Error' in t) else '无 ✅')
PY

echo
echo "########## 3. 首页体检（应新增 IPv6 警告） ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/service/safety" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for i in d.get('items',[]):
    print('   [%-7s] %s' % (i['level'], i['title']))
"
rm -f "$JAR"
