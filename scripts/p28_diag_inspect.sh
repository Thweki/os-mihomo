#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 诊断 inspect 接口失败原因
set -u
BASE=https://127.0.0.1
JAR=/tmp/p28_jar.txt
rm -f "$JAR"

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"

echo "########## 1. 原始返回 ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/settings/inspect" | head -c 600; echo

echo
echo "########## 2. 控制器方法是否存在 ##########"
grep -n 'function .*Action' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SettingsController.php | sed 's/^/  /'

echo
echo "########## 3. PHP 错误日志尾部 ##########"
tail -12 /var/lib/php/tmp/PHP_errors.log 2>/dev/null | sed 's/^/  /'

echo
echo "########## 4. 单独跑 Inspector（CLI） ##########"
php -r '
require_once "/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php";
require_once "/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Inspector.php";
$y = \OPNsense\Mihomo\Config::rawText();
$rows = \OPNsense\Mihomo\Inspector::compare($y, ["log-level" => "info", "mode" => "rule", "secret" => ""], null);
echo "  compare rows: ", count($rows), "\n";
foreach (array_slice($rows, 0, 3) as $r) { echo "   ", $r["label"], " | ", $r["file"], " | ", $r["state"], "\n"; }
echo "  handwritten: ", var_export(\OPNsense\Mihomo\Inspector::looksHandwritten($y), true), "\n";
echo "  ipv6Allowed: ", var_export(\OPNsense\Mihomo\Inspector::ipv6Allowed($y), true), "\n";
' 2>&1 | sed 's/^/  /'
rm -f "$JAR"
