#!/bin/sh
# 收尾核对：策略行 + 「不修改」状态 + 文件校验和 + 五个页面
set -u
echo "########## 1. 策略表与网络侧（用户原来那两行的现状） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
node = r.find('OPNsense/mihomo/policyRouting')
rows = [] if node is None else node.findall('rule')
print('  策略行: %d' % len(rows))
for rule in rows:
    print('   ', {c.tag: (c.text or '') for c in rule})
flt = r.find('OPNsense/Firewall/Filter')
rules = [] if flt is None else [x for x in flt.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]
print('  插件浮动规则: %d 条' % len(rules))
m = r.find('OPNsense/mihomo/managed')
print('  设置页「允许写入」清单:', repr(None if m is None else (m.text or '')))
PY
echo "  pf route-to(tun_mihomo): $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' | head -1)"
echo "  igb4（LanDirect）route-to: $(pfctl -sr 2>/dev/null | grep route-to | grep -c igb4 | head -1)"

echo
echo "########## 2. config.yaml 校验和（应与本轮开始前一致） ##########"
md5 -q /usr/local/etc/mihomo/config.yaml | sed 's/^/  md5: /'

echo
echo "########## 3. 五个页面（PHP 报错 + 字节数） ##########"
BASE=https://127.0.0.1
JAR=/tmp/p60_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
for page in "" settings subscription routing log; do
    OUT=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/$page")
    SZ=$(printf '%s' "$OUT" | wc -c | tr -d ' ')
    ERR=$(printf '%s' "$OUT" | grep -c -E 'Fatal error|Warning: mysqli|Parse error|Uncaught' || true)
    echo "  /ui/mihomo/$page   ${SZ} 字节   报错: ${ERR}"
done

echo
echo "########## 4. 安全 ##########"
echo "  默认路由: $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo "  服务: $(service mihomo status 2>&1 | head -1)"
rm -f "$JAR"
