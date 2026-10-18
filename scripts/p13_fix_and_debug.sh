#!/bin/sh
# 1) 撤回误还原（用还原动作自己产生的 190901 备份）
# 2) 排查自检脚本的报错
set -u
BASE=https://127.0.0.1
JAR=/tmp/fix_jar.txt
PASS='${OPN_PW}'
CFG=/usr/local/etc/mihomo/config.yaml
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
POST() { curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' --data "$2" "$BASE$1"; }

echo "########## 1. 当前 config.yaml 的 TUN 设置（误还原后的状态） ##########"
awk '/^tun:/{f=1} f{print "  "$0} f&&/^[a-z]/&&!/^tun:/{exit}' "$CFG" | head -8

echo
echo "########## 2. 用 190901 备份撤回（= 还原前的状态） ##########"
POST /api/mihomo/routing/history_restore '{"ts":"20261018_190901"}' | head -c 200; echo
echo "  --- 撤回后的 TUN 设置 ---"
awk '/^tun:/{f=1} f{print "  "$0} f&&/^[a-z]/&&!/^tun:/{exit}' "$CFG" | head -8
echo "  --- 受管块是否还在 ---"
sed -n '/# >>> os-mihomo:policy-routing/,/# <<< os-mihomo:policy-routing/p' "$CFG" | sed 's/^/    /'

echo
echo "########## 3. 重启服务让内存配置与文件一致 ##########"
POST /api/mihomo/service/restart '{}' >/dev/null
sleep 12
service mihomo status 2>&1 | head -1 | sed 's/^/  /'
echo "  TUN: $(ifconfig tun_mihomo 2>/dev/null | awk '/inet /{print $2" "$4}' || echo '(无)')"
echo "  pf route-to: $(pfctl -sr 2>/dev/null | grep -c 'route-to.*tun_mihomo')"

echo
echo "########## 4. 自检脚本排查 ##########"
echo "  --- php -l ---"
php -l /usr/local/opnsense/scripts/mihomo/selftest.php 2>&1 | head -3 | sed 's/^/    /'
echo "  --- 手工造一份 staging 直接跑 ---"
STAGE=$(mktemp /tmp/mihomo-XXXXXX)
cat > "$STAGE" <<'EOF'
{"tests":[{"interface":"lan","source":"192.168.1.0/24","src_ip":"192.168.1.1","target":"🇺🇸 United States"}]}
EOF
chmod 0600 "$STAGE"
php /usr/local/opnsense/scripts/mihomo/selftest.php run "$STAGE" 2>&1 | head -c 1200 | sed 's/^/    /'
echo
echo "  --- configd 动作 ---"
STAGE2=$(mktemp /tmp/mihomo-XXXXXX)
cat > "$STAGE2" <<'EOF'
{"tests":[{"interface":"lan","source":"192.168.1.0/24","src_ip":"192.168.1.1","target":"🇺🇸 United States"}]}
EOF
chmod 0600 "$STAGE2"
configctl mihomo selftest "$STAGE2" 2>&1 | head -c 900 | sed 's/^/    /'
echo
echo "  --- 临时路由是否残留 ---"
netstat -rn -f inet | grep tun_mihomo | sed 's/^/    /'
rm -f "$JAR"
