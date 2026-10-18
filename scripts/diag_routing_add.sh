#!/bin/sh
# 诊断：ArrayField 声明方式 + add_rule 报错的真实原因
set -u

echo "########## 1. 核心 Filter 模型如何声明规则数组 ##########"
grep -n -A3 '<rule ' /usr/local/opnsense/mvc/app/models/OPNsense/Filter/Filter.xml | head -20
echo "--- 另一个例子：Core/Tunables ---"
grep -n -B2 -A4 'item' /usr/local/opnsense/mvc/app/models/OPNsense/Core/Sysctl.xml 2>/dev/null | head -20
echo "--- models 目录里所有 ArrayField 声明 ---"
grep -rn 'type="ArrayField"' /usr/local/opnsense/mvc/app/models/OPNsense/ 2>/dev/null | head -8

echo
echo "########## 2. add_rule 报错的真实原因（PHP 错误日志） ##########"
tail -30 /var/lib/php/tmp/PHP_errors.log 2>/dev/null || echo "  (无 PHP_errors.log)"
echo "--- lighttpd 错误日志尾部 ---"
tail -15 /var/log/lighttpd/error.log 2>/dev/null || echo "  (无)"

echo
echo "########## 3. 页面里 grid 局部模板渲染成了什么 ##########"
KH=/tmp/rt_jar.txt
LP=$(curl -sk -c "$KH" https://127.0.0.1/index.php)
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$KH" -c "$KH" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$N=$V" https://127.0.0.1/index.php
curl -sk -b "$KH" https://127.0.0.1/ui/mihomo/routing | grep -n -A6 'content-box __mb' | sed -n '1,40p'
rm -f "$KH"
