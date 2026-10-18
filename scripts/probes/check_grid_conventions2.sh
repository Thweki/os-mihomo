#!/bin/sh
# 找 UIBootgrid 的标准用法与 ApiMutableModelControllerBase 的可用助手
set -u
B=/usr/local/opnsense/mvc/app

echo "########## 1. 谁在用 UIBootgrid（核心） ##########"
grep -rl 'UIBootgrid(' $B/views 2>/dev/null | head -8

echo
echo "########## 2. 一个标准页面的写法（取第一个） ##########"
EX=$(grep -rl 'UIBootgrid(' $B/views 2>/dev/null | head -1)
echo "文件: $EX"
grep -n -A14 'UIBootgrid(' "$EX" | head -45

echo
echo "########## 3. 该页面的表格标记（base_bootgrid_table 用法） ##########"
grep -n -B2 -A6 'base_bootgrid_table\|table id="grid' "$EX" | head -30

echo
echo "########## 4. ApiMutableModelControllerBase 提供的 Base 助手 ##########"
grep -n 'public function .*Action\|protected function .*Base' $B/controllers/OPNsense/Base/ApiMutableModelControllerBase.php | head -40

echo
echo "########## 5. 核心防火墙 MVC 目录（看表单/视图命名） ##########"
ls -1 $B/controllers/OPNsense/Firewall/ $B/controllers/OPNsense/Firewall/forms/ $B/views/OPNsense/Firewall/ 2>/dev/null | head -30
