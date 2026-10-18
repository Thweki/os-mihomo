#!/bin/sh
# 还原到实验前的有效配置并恢复服务
set -u
CFG=/usr/local/etc/mihomo/config.yaml
BAK=/tmp/cfg-before-sniffer.yaml

echo "########## 1. 现状 ##########"
echo -n "  服务: "; service mihomo status 2>&1 | head -1
echo "  重复的 sniffer 键: $(grep -c '^sniffer:' "$CFG")"

echo
echo "########## 2. 还原 ##########"
if [ -f "$BAK" ]; then
    STAGE=$(mktemp /tmp/mihomo-XXXXXX)
    cp "$BAK" "$STAGE"; chmod 0600 "$STAGE"
    echo "  staging: $STAGE ($(grep -c . "$BAK") 行)"
    configctl mihomo config-install "$STAGE" 2>&1 | head -3 | sed 's/^/  /'
else
    echo "  备份不存在，改用最近的时间戳备份"
    LAST=$(ls -1t /usr/local/etc/mihomo/config.yaml.bak.* | head -1)
    echo "  使用: $LAST"
    cp "$LAST" "$CFG"
fi
echo "  还原后 sniffer 键数: $(grep -c '^sniffer:' "$CFG")"

echo
echo "########## 3. 重启服务 ##########"
service mihomo restart >/dev/null 2>&1
sleep 12
echo -n "  服务: "; service mihomo status 2>&1 | head -1
echo "  TUN: $(ifconfig tun_mihomo 2>/dev/null | awk '/inet /{print $2" "$4}' || echo '(无)')"
echo "  pf route-to: $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo')"
echo -n "  控制器: "; curl -s --max-time 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9090/ 2>/dev/null || echo "FAIL"

echo
echo "########## 4. 受管块仍在 ##########"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/  /'

echo
echo "########## 5. 链路自检 ##########"
echo -n "  出网: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 https://www.freebsd.org/ || echo FAIL
