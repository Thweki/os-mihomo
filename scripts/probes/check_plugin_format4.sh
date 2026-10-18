#!/bin/sh
# 取证 4：插件页面到底调用什么命令 + 仓库数据库状态
set -u

echo "########## 1. 固件页面的实现位置 ##########"
ls -1 /usr/local/opnsense/mvc/app/controllers/OPNsense/Core/ 2>/dev/null
echo "--- 找 plugins 关键字 ---"
grep -rln 'plugins' /usr/local/opnsense/mvc/app/controllers/OPNsense/Core/ /usr/local/opnsense/mvc/app/models/OPNsense/Core/ 2>/dev/null | head

echo
echo "########## 2. 插件列表是怎么生成的 ##########"
grep -rn 'rquery\|pkg search\|pkg query\|repositories' /usr/local/opnsense/mvc/app/models/OPNsense/Core/Firmware.php 2>/dev/null | head -20
echo "--- 相关 configd 动作全文 ---"
sed -n '/^\[plugins\]/,/^$/p;/^\[search\]/,/^$/p;/^\[repositories\]/,/^$/p' /usr/local/opnsense/service/conf/actions.d/actions_firmware.conf 2>/dev/null

echo
echo "########## 3. 本地仓库数据库 ##########"
ls -la /var/db/pkg/repo-* 2>/dev/null || echo "(无 repo-*.sqlite)"

echo
echo "########## 4. 刷新仓库元数据（只下载索引，不安装/不升级） ##########"
pkg update 2>&1 | tail -12

echo
echo "########## 5. 刷新后：opnwall 仓库是否有 os-* ##########"
pkg rquery -r opnwall '%n %v' 2>&1 | sort | head -20

echo
echo "########## 6. 仓库列表与优先级 ##########"
pkg -vv 2>/dev/null | sed -n '/^Repositories:/,/^$/p' | head -30

echo
echo "########## 7. 清理临时仓库测试目录 ##########"
rm -rf /tmp/repo-test && echo cleaned
