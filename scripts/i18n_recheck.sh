#!/bin/sh
# 复查：重启后页面中文是否全部生效，并看编译模板里翻译的形态
set -u

echo "=== 1. 编译后的订阅页视图（前 40 行）==="
sed -n '1,40p' /var/lib/php/cache/_usr_local_opnsense_mvc_app_views_opnsense_mihomo_subscription.volt.php

echo
echo "=== 2. 里面出现的翻译相关片段 ==="
grep -n "Subscription Management\|订阅管理\|_('" /var/lib/php/cache/_usr_local_opnsense_mvc_app_views_opnsense_mihomo_subscription.volt.php | head -10

echo
echo "=== 3. 登录并复查全部页面 ==="
BASE=https://127.0.0.1
JAR=/tmp/i18n_jar4.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$N=$V" "$BASE/index.php"

check() {
    url="$1"; shift
    html=$(curl -sk -b "$JAR" "$BASE$url")
    printf '%-30s ' "$url"
    for pat in "$@"; do
        if printf '%s' "$html" | grep -q "$pat"; then printf '[%s] ' "$pat"; else printf '[-] '; fi
    done
    echo
}

check /ui/mihomo '代理分组' '活动连接' '全部断开'
check /ui/mihomo/settings '配置文件' '访问密钥' '订阅地址' '校验'
check /ui/mihomo/subscription '订阅管理' '开始订阅' '日志视图'
check /ui/mihomo/log '内核日志' '订阅日志' '清空日志' '字节'
check /ui/unbound/overview '概况' '详细'

rm -f "$JAR"
