#!/bin/sh
# 收尾核对：设置页的勾分布 / 写死项 / 应用行为 / 设备状态
set -u
BASE=https://127.0.0.1
JAR=/tmp/p65_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" -o /tmp/p65-settings.html

echo "########## 1. 页面里不带勾的项（应为插件状态 + 写死项） ##########"
python3 - <<'PY'
import io, re
t = io.open('/tmp/p65-settings.html', encoding='utf-8').read()
fields = re.findall(r'id="(mihomo\.[A-Za-z.]+)"', t)
no_switch = re.findall(r"const ALWAYS_OWNED = \('([^']*)'", t)
fixed = re.findall(r"const FIXED = \{\};[\s\S]{0,120}?\('([^']*)'", t)
print('  表单字段 %d 个' % len(set(fields)))
print('  不给勾的项:', no_switch[0] if no_switch else '(渲染失败)')
print('  写死的项  :', fixed[0] if fixed else '(渲染失败)')
print('  「固定」标记 CSS 在:', '是' if '.mihomo-fixed-tag' in t else '否')
PY

echo
echo "########## 2. 写死值在三条链路上一致 ##########"
grep -o 'tun_mihomo\|gvisor' /tmp/p65-settings.html | sort | uniq -c | sed 's/^/  /'
echo "  config.yaml: $(grep -E '^  (device|stack):' /usr/local/etc/mihomo/config.yaml | tr -d ' ' | tr '\n' ' ')"

echo
echo "########## 3. 应用一次（应静默，不再刷屏） ##########"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
BEFORE=$(md5 -q /usr/local/etc/mihomo/config.yaml)
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{"restart":0}' \
     "$BASE/api/mihomo/settings/apply" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages',[]): print('    ', m)
if d.get('message'): print('   !!', str(d['message'])[:200])"
AFTER=$(md5 -q /usr/local/etc/mihomo/config.yaml)
echo "  config.yaml 校验和: $([ "$BEFORE" = "$AFTER" ] && echo '未变 ✅' || echo "变了 ⚠️ ($BEFORE -> $AFTER)")"

echo
echo "########## 4. 五个页面 + 安全 ##########"
for page in "" settings subscription routing log; do
    OUT=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/$page")
    ERR=$(printf '%s' "$OUT" | grep -c -E 'Fatal error|Parse error|Uncaught' || true)
    echo "  /ui/mihomo/$page 报错: ${ERR}"
done
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
rm -f "$JAR"
