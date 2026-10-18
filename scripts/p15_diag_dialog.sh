#!/bin/sh
# 诊断：路由策略对话框里接口/代理组下拉的真实 DOM
set -u
BASE=https://127.0.0.1
JAR=/tmp/dlg_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

HTML=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/routing")

echo "########## 1. 对话框里 interface / target 字段的原始 HTML ##########"
printf '%s' "$HTML" | grep -n -A3 -B1 'mihomo\.interface\|mihomo\.target\|mihomo\.scope' | head -40 | sed 's/^/  /'

echo
echo "########## 2. 是否有 selectpicker / select 元素 ##########"
printf '%s' "$HTML" | grep -c 'selectpicker' | sed 's/^/  selectpicker 出现次数: /'
printf '%s' "$HTML" | grep -o '<select[^>]*id="mihomo\.[a-zA-Z]*"' | sed 's/^/  /'
printf '%s' "$HTML" | grep -o 'id="mihomo\.\(interface\|target\|scope\|firewall\|enabled\)"' | sed 's/^/  /'

echo
echo "########## 3. options 接口现在返回什么 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/routing/options" | head -c 400 | sed 's/^/  /'
echo
rm -f "$JAR"
