#!/bin/sh
# 摸清 OPNsense 的 gettext 装载方式与 zh_CN 目录结构
set -u

echo "=== ControllerRoot::setLang ==="
sed -n '55,105p' /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/ControllerRoot.php

echo
echo "=== 语言包目录 ==="
ls -la /usr/local/share/opnsense/locale/ 2>/dev/null | head -20
echo "--- zh_CN ---"
ls -la /usr/local/share/opnsense/locale/zh_CN/LC_MESSAGES/ 2>/dev/null | head -20

echo
echo "=== 系统 locale 目录里有没有 OPNsense 的 mo ==="
find /usr/local/share/locale -name '*.mo' 2>/dev/null | head -10
find /usr/local/share/locale -name '*.mo' 2>/dev/null | wc -l

echo
echo "=== 语言包插件 ==="
pkg info 2>/dev/null | grep -i lang || echo "(无 os-lang 包)"
ls -la /usr/local/opnsense/mvc/app/models/OPNsense/Lang 2>/dev/null | head -5 || echo "(无 Lang 模块)"

echo
echo "=== gettext 相关 php 函数可用性 ==="
php -r 'foreach (["gettext","bindtextdomain","textdomain","ngettext","dgettext"] as $f) printf("  %-16s %s\n", $f, function_exists($f) ? "yes" : "NO");'

echo
echo "=== 当前 config.xml 语言 ==="
grep -o '<language>[^<]*</language>' /conf/config.xml || echo "(未设置)"
