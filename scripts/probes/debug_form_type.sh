#!/bin/sh
set -u
echo "=== 核心表单里 BooleanField 对应什么 type ==="
grep -rn -A3 'unbound.general.enabled\|monit.general.enable' /usr/local/opnsense/mvc/app/controllers/OPNsense/Unbound/forms/general.xml /usr/local/opnsense/mvc/app/controllers/OPNsense/Monit/forms/general.xml 2>/dev/null | head -20
echo
echo "=== 统计各 type 用法 ==="
grep -rho '<type>[a-z_]*</type>' /usr/local/opnsense/mvc/app/controllers/OPNsense/*/forms/*.xml 2>/dev/null | sort | uniq -c | sort -rn | head -12
echo
echo "=== 我安装下去的表单里用的 type ==="
grep -ho '<type>[a-z_]*</type>' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml | sort | uniq -c
