#!/bin/sh
# 取全：tunables 页的表格/对话框标记 + API 动作 + Base 助手位置
set -u
B=/usr/local/opnsense/mvc/app

echo "########## 1. tunables.volt 的标记部分（第 90 行之后） ##########"
sed -n '90,200p' $B/views/OPNsense/Core/tunables.volt 2>/dev/null

echo
echo "########## 2. API 控制器里的动作名 ##########"
grep -n 'function .*Action' $B/controllers/OPNsense/Core/Api/TunablesController.php 2>/dev/null | head -12
echo "--- 三个动作的实现（search/set/add） ---"
grep -n -A5 'function searchItemAction\|function setItemAction\|function addItemAction\|function delItemAction' $B/controllers/OPNsense/Core/Api/TunablesController.php 2>/dev/null | head -40

echo
echo "########## 3. Base 助手（searchBase/setBase/…）定义位置 ##########"
grep -rn 'function setBase\|function searchBase' $B/controllers/OPNsense/Base/ 2>/dev/null | head -5
grep -rn 'trait ' $B/controllers/OPNsense/Base/ApiMutableModelControllerBase.php 2>/dev/null | head -5
grep -n 'class ApiMutableModelControllerBase' $B/controllers/OPNsense/Base/ApiMutableModelControllerBase.php
