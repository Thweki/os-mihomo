#!/bin/sh
# 诊断：policy_net.php 现在为什么没有输出
set -u
S=/usr/local/opnsense/scripts/mihomo/policy_net.php

echo "########## 1. 设备上的脚本是否含新逻辑 ##########"
grep -c 'verify_only\|verifyOnly\|first stage' "$S" | sed 's/^/  匹配数: /'
php -l "$S" 2>&1 | sed 's/^/  /'

echo
echo "########## 2. 直接手动跑（空 interfaces，第一段） ##########"
cat > /tmp/mihomo-manual.json <<'EOF'
{"interfaces": [], "gateway": "", "verify": false}
EOF
chmod 600 /tmp/mihomo-manual.json
cp /tmp/mihomo-manual.json /tmp/mihomo-manual2.json 2>/dev/null || true
echo "  --- 输出 ---"
php "$S" apply /tmp/mihomo-manual.json 2>&1 | sed 's/^/    /'
echo "  --- 退出码: $? ---"

echo
echo "########## 3. 通过 configctl（和 WebGUI 同一条路） ##########"
configctl mihomo policy-net-apply /tmp/mihomo-manual.json 2>&1 | sed 's/^/    /'

echo
echo "########## 4. configd 动作定义 ##########"
grep -A6 '^\[policy-net-apply\]' /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf | sed 's/^/  /'

echo
echo "########## 5. 日志里的线索 ##########"
tail -5 /var/log/configd.log 2>/dev/null | sed 's/^/  /'
tail -3 /var/lib/php/tmp/PHP_errors.log 2>/dev/null | sed 's/^/  /'
rm -f /tmp/mihomo-manual.json
