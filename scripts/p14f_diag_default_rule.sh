#!/bin/sh
# 关键取证：自动「Default allow LAN to any」规则从哪来、排在哪
set -u
echo "########## 1. config.xml 里有这条规则吗 ##########"
grep -c 'Default allow' /conf/config.xml 2>/dev/null | sed 's/^/  /'
grep -n 'Default allow' /conf/config.xml 2>/dev/null | head -3 | sed 's/^/  /'

echo
echo "########## 2. 系统里哪段代码生成它 ##########"
grep -rln 'Default allow' /usr/local/etc/inc/ /usr/local/opnsense/ /usr/local/www/ 2>/dev/null | head -8 | sed 's/^/  /'

echo
echo "########## 3. pf 里 igb0 全部规则的顺序（带 @编号） ##########"
pfctl -sr 2>/dev/null | grep -n 'on igb0' | sed 's/^/  /' | tail -12

echo
echo "########## 4. 该默认规则的 label 在 config.xml 里能查到吗 ##########"
LBL=$(pfctl -sr 2>/dev/null | grep 'on igb0' | grep -v 'route-to' | grep 'to any' | head -1 | sed -n 's/.*label "\([^"]*\)".*/\1/p')
echo "  默认放行规则的 label: $LBL"
grep -c "$LBL" /conf/config.xml 2>/dev/null | sed 's/^/  在 config.xml 中出现次数: /'

echo
echo "########## 5. 我们规则的 label（哈希）在 config.xml 里能查到吗 ##########"
grep -c 'db8330058668e6ef26e238953f13ae6a' /conf/config.xml 2>/dev/null | sed 's/^/  /'
