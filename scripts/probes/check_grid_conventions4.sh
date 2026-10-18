#!/bin/sh
# 最小完整范例：核心「可调参数(tunables)」页 —— 表格+对话框+应用 的标准骨架
set -u
B=/usr/local/opnsense/mvc/app

echo "########## 1. 视图：views/OPNsense/Core/tunables.volt（全文，约 60 行） ##########"
cat -n $B/views/OPNsense/Core/tunables.volt 2>/dev/null | head -70

echo
echo "########## 2. 页面控制器：Core/TunablesController.php ##########"
cat -n $B/controllers/OPNsense/Core/TunablesController.php 2>/dev/null | head -40

echo
echo "########## 3. API 控制器：CRUD 动作 ##########"
grep -n -A6 'function searchAction\|function setAction\|function addAction\|function delAction\|function toggleAction' $B/controllers/OPNsense/Core/Api/TunablesController.php 2>/dev/null | head -45

echo
echo "########## 4. 对话框表单：forms/tunable.xml（全文，看 grid_view 写法） ##########"
cat -n $B/controllers/OPNsense/Core/forms/tunable.xml 2>/dev/null | head -60

echo
echo "########## 5. setBase/searchBase 这些助手定义在哪 ##########"
grep -rn 'function setBase\|function searchBase\|function delBase\|function toggleBase\|function addBase' $B/controllers/OPNsense/Base/ 2>/dev/null | head -8
