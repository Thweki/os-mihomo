#!/bin/sh
# 诊断：用户新配置（secret 空、分组少）下，仪表盘各接口是否还返回数据
set -u
BASE=https://127.0.0.1
JAR=/tmp/p18_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

for ep in dashboard/overview dashboard/proxies dashboard/traffic dashboard/connections; do
    echo "########## /api/mihomo/$ep ##########"
    curl -sk -b "$JAR" "$BASE/api/mihomo/$ep" | head -c 600 | python3 -c "
import sys, json
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    if isinstance(d, dict):
        keys = list(d.keys())
        print('  keys:', keys[:12])
        for k in ('version','mode','uptime','upload','download','memory','groups','total','items','error','message'):
            if k in d:
                v = d[k]
                if isinstance(v, list):
                    print('   ', k, '→ list(%d)' % len(v), str(v[:1])[:160])
                else:
                    print('   ', k, '→', str(v)[:160])
    else:
        print('  (非对象)', str(d)[:200])
except Exception as e:
    print('  解析失败:', e, '| 原始:', raw[:200])
"
    echo
done
rm -f "$JAR"
