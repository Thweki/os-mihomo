#!/bin/sh
# 交付验收：插件现在在目标机上到底是什么状态
set -u
BASE=https://127.0.0.1
JAR=/tmp/trial_jar.txt
rm -f "$JAR"

echo "########## 1. 文件是否就位 ##########"
for f in \
    /usr/local/bin/mihomo \
    /usr/local/etc/mihomo/config.yaml \
    /usr/local/etc/rc.d/mihomo \
    /usr/local/etc/inc/plugins.inc.d/mihomo.inc \
    /usr/local/opnsense/version/mihomo \
    /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf \
    /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.xml \
    /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/IndexController.php \
    /usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/index.volt \
    /usr/local/www/mihomo.php ; do
    if [ -f "$f" ]; then printf '  OK   %s\n' "$f"; else printf '  MISS %s\n' "$f"; fi
done
echo "  config: $(wc -l < /usr/local/etc/mihomo/config.yaml | tr -d ' ') 行, $(stat -f '%Sp %Su:%Sg' /usr/local/etc/mihomo/config.yaml)"

echo
echo "########## 2. 服务与自启 ##########"
cat /etc/rc.conf.d/mihomo
service mihomo status
echo "--- config.yaml 关键行 ---"
grep -nE '^(log-level|mode|allow-lan|mixed-port|external-controller|secret):|^tun:|^\s+(enable|auto-route|strict-route|stack|device):|^\s+enhanced-mode:' /usr/local/etc/mihomo/config.yaml | head -20

echo
echo "########## 3. configd 动作（14 个） ##########"
configctl mihomo status 2>&1 | head -3
echo "--- 动作数 ---"
grep -c '^\[' /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf

echo
echo "########## 4. WebGUI 页面（登录后） ##########"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$N=$V" "$BASE/index.php"
for p in /ui/mihomo /ui/mihomo/settings /ui/mihomo/subscription /ui/mihomo/log /mihomo.php; do
    printf '  %-28s %s\n' "$p" "$(curl -sk -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE$p")"
done
echo "--- 菜单项（页面里应出现 4 个入口）---"
curl -sk -b "$JAR" "$BASE/ui/mihomo" | grep -o 'href="/ui/mihomo[^"]*"' | sort -u | head -6

echo
echo "########## 5. 接口 ##########"
for a in "service/status" "service/safety" "settings/get" "dashboard/overview" "subscription/get" "log/tail?key=mihomo&lines=3"; do
    printf '  %-32s %s\n' "$a" "$(curl -sk -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/api/mihomo/$a")"
done
echo "--- 安全体检（页面横幅的数据源）---"
curl -sk -b "$JAR" "$BASE/api/mihomo/service/safety" | head -c 700
echo

echo
echo "########## 6. 中文界面 ##########"
curl -sk -b "$JAR" "$BASE/ui/mihomo" | grep -q '代理分组' && echo "  概览页：中文 OK" || echo "  概览页：未命中中文词条"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | grep -q '配置文件' && echo "  设置页：中文 OK" || echo "  设置页：未命中中文词条"

echo
echo "########## 7. 订阅配置现状 ##########"
echo "--- sub/env（敏感字段只显示是否为空）---"
awk -F= '/^[A-Z_]+=/{printf "  %s=%s\n", $1, (length($2)>0 ? "已设置(" length($2) " 字符)" : "空")}' /usr/local/etc/mihomo/sub/env 2>/dev/null

rm -f "$JAR"
