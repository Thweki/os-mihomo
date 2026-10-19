#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 实验：把完整的 sniffer 块（含嗅探端口）写进配置，看策略规则是否开始命中
set -u
CFG=/usr/local/etc/mihomo/config.yaml
BASE=https://127.0.0.1
JAR=/tmp/sniff2_jar.txt
rm -f "$JAR"

echo "########## 1. 备份并写入完整 sniffer 块 ##########"
cp "$CFG" /tmp/cfg-before-sniffer.yaml
python3 - <<'PY'
import io, re
p = '/usr/local/etc/mihomo/config.yaml'
t = io.open(p, encoding='utf-8').read()
block = """sniffer:
  enable: true
  parse-pure-ip: true
  force-dns-mapping: true
  override-destination: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
"""
# 删掉现有的 sniffer 段（若只有 enable 一行）
t = re.sub(r'^sniffer:\n(?:[ \t]+.*\n)*', '', t, flags=re.M)
# 插到 dns: 之前（保持结构清晰）
if re.search(r'^dns:', t, re.M):
    t = re.sub(r'^dns:', block + 'dns:', t, count=1, flags=re.M)
else:
    t = t.rstrip('\n') + '\n' + block
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('sniffer 块已写入')
PY
grep -n -A12 '^sniffer:' "$CFG" | sed 's/^/  /'

echo
echo "########## 2. 校验 + 重启 ##########"
STAGE=$(mktemp /tmp/mihomo-XXXXXX); cp "$CFG" "$STAGE"; chmod 0600 "$STAGE"
configctl mihomo config-install "$STAGE" 2>&1 | head -2 | sed 's/^/  /'
echo "  (上面若报错，则用 restart 让内核自行加载)"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${PASS}&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/service/restart" >/dev/null
sleep 12
service mihomo status 2>&1 | head -1 | sed 's/^/  /'

echo
echo "########## 3. 重新自检 ##########"
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data '{}' \
    "$BASE/api/mihomo/routing/selftest" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('results', []):
    print('  ---', r.get('interface'))
    print('     出口 IP :', r.get('foreign_ip') or '(失败)')
    print('     命中规则:', r.get('foreign_rule') or '—')
    print('     出口组  :', r.get('foreign_group') or '—')
    print('     国内    :', r.get('domestic_rule') or '—')
"

echo
echo "########## 4. 日志佐证 ##########"
tail -40 /var/log/mihomo.log | grep 'match' | tail -4 | sed 's/^/  /'
rm -f "$JAR"
