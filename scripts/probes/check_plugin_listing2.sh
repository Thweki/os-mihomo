#!/bin/sh
# 取证 6：固件/插件页面用的动作与脚本
set -u

echo "=== actions_firmware.conf 的动作名 ==="
grep -o '^\[[a-z]*\]' /usr/local/opnsense/service/conf/actions.d/actions_firmware.conf | tr '\n' ' '
echo
echo
echo "=== 各动作对应的命令（前 25 行）==="
grep -E '^\[|^command:' /usr/local/opnsense/service/conf/actions.d/actions_firmware.conf | head -50

echo
echo "=== Core 控制器/视图中 plugins 相关 ==="
grep -rn 'plugins' /usr/local/opnsense/mvc/app/controllers/OPNsense/Core/ /usr/local/opnsense/mvc/app/views/OPNsense/Core/ 2>/dev/null | head -12

echo
echo "=== firmware 脚本目录 ==="
ls -1 /usr/local/opnsense/scripts/firmware/

echo
echo "=== 已安装插件查询（health.sh 用的方式）==="
pkg query -g '%n %v' 'os-*'
