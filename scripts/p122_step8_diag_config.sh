#!/bin/sh
# 诊断：config.xml 现在到底是什么样（重点看 opt 接口块与网关）
set -u
X=/conf/config.xml

echo "########## 1. 所有 interfaces 区块的位置 ##########"
grep -n '<interfaces>\|</interfaces>\|<opt[0-9]>\|</opt[0-9]>\|<lan>\|</lan>' "$X" | sed 's/^/  /'

echo
echo "########## 2. 逐行看 40-70 行（插入点附近） ##########"
sed -n '40,70p' "$X" | cat -n | sed 's/^/  /'

echo
echo "########## 3. 我们写入的接口块 ##########"
sed -n '/<if>tun_mihomo<\/if>/,+4p' "$X" | sed 's/^/  /'
echo "  --- 该块所属的 optN（往上找最近的 <optN>） ---"
awk '/<opt[0-9]+>/{last=$0; line=NR} /<if>tun_mihomo<\/if>/{print "  " line": "last; exit}' "$X"

echo
echo "########## 4. 网关块 ##########"
sed -n '/<name>MIHOMO_TUN<\/name>/,+2p' "$X" | sed 's/^/  /'
awk '/<gateway_item>/{start=NR} /<name>MIHOMO_TUN<\/name>/{found=start} END{}' "$X"
echo "  --- 网关块全文 ---"
sed -n '/<gateway_item>/,/<\/gateway_item>/p' "$X" | sed 's/^/  /'

echo
echo "########## 5. 我们加的规则 ##########"
sed -n '/Mihomo policy routing/,+2p' "$X" | sed 's/^/  /'
echo "  --- 规则所属 filter（往上找最近的 <filter>） ---"
awk '/<filter>/{last=NR} /Mihomo policy routing/{print "  filter at line "last; exit}' "$X"

echo
echo "########## 6. 备份清单（回滚用） ##########"
ls -la /conf/config.xml.mihomo-bak.* 2>/dev/null | sed 's/^/  /'

echo
echo "########## 7. 现在的 opt 接口（OPNsense 视角） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
ifs = r.find('interfaces')
for node in ifs:
    print('  %-8s if=%-12s descr=%-12s enable=%s' % (
        node.tag, (node.findtext('if') or ''), (node.findtext('descr') or ''),
        (node.findtext('enable') or '')))
PY

echo
echo "########## 8. 我的链路（LanDirect）现在是否正常 ##########"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
echo "  路由表里 igb4/LanDirect 相关:"
netstat -rn -f inet | grep -E '192.168.2|igb4' | sed 's/^/    /' || echo "    (无)"
