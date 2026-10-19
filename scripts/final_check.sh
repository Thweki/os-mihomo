#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 收工前的最终安全检查（只读）
set -u
echo "=============== 设备最终状态 ==============="
echo " 服务:        $(service mihomo status 2>&1 | head -1)"
echo " 开机自启:     $(grep -h mihomo_enable /etc/rc.conf.d/mihomo 2>/dev/null || echo '(未设置)')"
echo " 默认路由:     $(netstat -rn -f inet | awk '$1=="default"{print $2" "$4}')"
echo " TUN 接口:     $(ifconfig tun_mihomo 2>/dev/null | awk '/inet /{print $2}' | tr '\n' ' ')"
echo " pf route-to:  $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo' | head -1) 条（本插件建的送流规则）"
echo " LanDirect 侧: $(pfctl -sr 2>/dev/null | grep 'route-to' | grep -c igb4 | head -1) 条 route-to（必须 0）"
echo " 策略表行数:   $(python3 -c "
import xml.etree.ElementTree as ET
r=ET.parse('/conf/config.xml').getroot()
n=r.find('OPNsense/mihomo/policyRouting')
print(0 if n is None else len(n.findall('rule')))")"
echo " 插件浮动规则: $(python3 -c "
import xml.etree.ElementTree as ET
r=ET.parse('/conf/config.xml').getroot()
f=r.find('OPNsense/Firewall/Filter')
print(0 if f is None else len([x for x in f.findall('rules/rule') if 'Mihomo' in (x.findtext('description') or '')]))")"
echo -n " 出网测试:     "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo
echo " 最近部署备份: $(ls -1t /usr/local/opnsense/_bak/os-mihomo/ 2>/dev/null | head -1)"
echo " PHP 报错(尾部): $(tail -1 /var/lib/php/tmp/PHP_errors.log 2>/dev/null | cut -c1-100)"
echo
echo "=============== 五个页面 ==============="
JAR=/tmp/final_jar.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "https://127.0.0.1/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "https://127.0.0.1/index.php"
for p in "" "settings" "subscription" "routing" "log"; do
    body=$(curl -sk -b "$JAR" "https://127.0.0.1/ui/mihomo/$p")
    size=$(printf '%s' "$body" | wc -c | tr -d ' ')
    err=$(printf '%s' "$body" | grep -c 'Fatal error\|PHP Error' || true)
    printf '  %-13s %8s 字节   PHP 报错: %s\n' "/ui/mihomo/$p" "$size" "$err"
done
rm -f "$JAR"
