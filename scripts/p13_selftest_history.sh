#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# ① 绑定自检 + ③ 配置历史：功能验证
set -u
BASE=https://127.0.0.1
JAR=/tmp/feat_jar.txt
CFG=/usr/local/etc/mihomo/config.yaml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
GET()  { curl -sk -b "$JAR" "$BASE$1"; }
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 绑定自检（真的把测试流量送进 TUN） ##########"
POST /api/mihomo/routing/selftest '{}' | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'), '| service:', d.get('service_running'), '| tun:', d.get('tun_up'), '| probe:', d.get('probe'))
for r in d.get('results', []):
    print('  ---', r.get('interface'), '(' + (r.get('source') or '') + ' →', (r.get('expected_group') or 'DIRECT') + ')')
    print('     出口 IP :', r.get('foreign_ip') or '(失败)')
    print('     命中规则:', r.get('foreign_rule') or '—')
    print('     出口组  :', r.get('foreign_group') or '—')
    print('     国内    :', r.get('domestic_rule') or '—')
    if r.get('note'): print('     备注    :', r.get('note'))
"

echo
echo "########## 2. 配置历史列表 ##########"
GET /api/mihomo/routing/history | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'), '| 备份数:', len(d.get('rows', [])))
for r in d.get('rows', [])[:5]:
    print('   ', r.get('ts'), r.get('size'), 'bytes')
"

echo
echo "########## 3. 历史 Diff（最新备份 vs 当前） ##########"
TS=$(GET /api/mihomo/routing/history | python3 -c "import json,sys; print(json.load(sys.stdin)['rows'][0]['ts'])")
echo "  最新备份: $TS"
GET "/api/mihomo/routing/history_show/$TS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
diff=(d.get('diff') or '').strip()
print('  diff:', (diff[:400] if diff else '（与当前一致）'))
"

echo
echo "########## 4. 还原测试（还原到「最新备份」= 内容相同的安全用例） ##########"
H1=$(sha256 -q "$CFG")
POST /api/mihomo/routing/history_restore "{\"ts\":\"$TS\"}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'))
for m in d.get('messages', []): print('  msg:', m.strip())
"
H2=$(sha256 -q "$CFG")
[ "$H1" = "$H2" ] && echo "  还原后配置字节不变 OK（本次用例即为当前内容）" || echo "  配置有变化（属预期，若还原的是旧备份）"

echo
echo "########## 5. 还原的护栏：不存在的备份 / 非法路径 ##########"
POST /api/mihomo/routing/history_restore '{"ts":"20200101_000000"}' | python3 -c "
import json,sys
d=json.load(sys.stdin); print('  不存在的备份 →', d.get('status'), '|', d.get('message'))
"
POST /api/mihomo/routing/history_restore '{"ts":"../../etc/passwd"}' | python3 -c "
import json,sys
d=json.load(sys.stdin); print('  非法路径     →', d.get('status'), '|', d.get('message'))
"

echo
echo "########## 6. 服务与链路自检 ##########"
service mihomo status 2>&1 | head -1 | sed 's/^/  /'
echo -n "  出网(LanDirect): "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo -n "  路由表里是否残留临时路由（应为 0）: "; netstat -rn -f inet | grep -c 'tun_mihomo' || true
netstat -rn -f inet | grep tun_mihomo | sed 's/^/    /' || echo "    (只有 198.18.0.0/30 直连路由属正常)"
rm -f "$JAR"
