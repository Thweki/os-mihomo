#!/bin/sh
# 最后一轮：UIBootgrid 的 JS 如何把对话框数据发给 API（决定表单 id 命名）
set -u
B=/usr/local/opnsense/mvc/app
JS=/usr/local/opnsense/www/js

echo "########## 1. UIBootgrid JS 位置 ##########"
ls -la $JS/opnsense_bootgrid_plugin.js $JS/opnsense_ui.js 2>/dev/null | head -4
grep -n 'set:\|add:\|del:\|toggle:\|ajaxCall(.*this.options' $JS/opnsense_bootgrid_plugin.js 2>/dev/null | head -25

echo
echo "########## 2. 保存时的载荷构造（关键：id 如何处理） ##########"
grep -n -A25 'saveRow\|_save\|serializeForm' $JS/opnsense_bootgrid_plugin.js 2>/dev/null | head -60

echo
echo "########## 3. searchBase / setBase 的签名 ##########"
sed -n '419,432p;590,606p' $B/controllers/OPNsense/Base/ApiMutableModelControllerBase.php

echo
echo "########## 4. base_dialog 局部模板如何用字段 id ##########"
grep -n 'field\|id\|name' $B/views/layout_partials/base_dialog.volt 2>/dev/null | head -25
