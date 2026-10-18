#!/bin/sh
# 诊断：为什么部分页面没有翻译
set -u
BASE=https://127.0.0.1
JAR=/tmp/i18n_jar2.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$N=$V" "$BASE/index.php"

echo "=== 1. 订阅页里到底渲染了什么（中文/英文都找）==="
html=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/subscription")
for s in '订阅管理' 'Subscription Management' '开始订阅' 'Start Subscription' '订阅地址' 'Subscription URL'; do
    c=$(printf '%s' "$html" | grep -c "$s" || true)
    printf '  %-24s 出现 %s 次\n' "$s" "$c"
done

echo
echo "=== 2. Volt 编译缓存目录 ==="
ls -la /var/lib/php/cache/ 2>/dev/null | head
find /var/lib/php /tmp -maxdepth 3 -type d -name '*volt*' 2>/dev/null | head
ls -la /usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/ 2>/dev/null | head -3

echo
echo "=== 3. php-cgi 进程启动时间（是否比合并更早，即缓存了旧词库）==="
ps -ax -o pid,etime,command 2>/dev/null | grep '[p]hp-cgi' | head -8
echo "  合并时间:"
ls -la --time-style=full-iso /usr/local/share/locale/zh_CN/LC_MESSAGES/OPNsense.mo 2>/dev/null || stat -f '%Sm %N' /usr/local/share/locale/zh_CN/LC_MESSAGES/OPNsense.mo

echo
echo "=== 4. 直接验证 .mo 里词条可读 ==="
/usr/local/bin/python3 /tmp/os-mihomo-mo_editor.py dump /usr/local/share/locale/zh_CN/LC_MESSAGES/OPNsense.mo --filter 'Subscription Management' | head -3

rm -f "$JAR"
