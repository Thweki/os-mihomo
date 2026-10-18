#!/bin/sh
# 应用按钮的响应约定 + 表格局部模板要求
set -u
B=/usr/local/opnsense/mvc/app/views
echo "########## 1. base_apply_button.volt ##########"
sed -n '25,90p' $B/layout_partials/base_apply_button.volt

echo
echo "########## 2. base_bootgrid_table.volt 的入参说明 ##########"
sed -n '25,70p' $B/layout_partials/base_bootgrid_table.volt

echo
echo "########## 3. getFormGrid / getForm 在 IndexController 里的定义 ##########"
grep -n -A12 'function getFormGrid\|function getForm\b' /usr/local/opnsense/mvc/app/controllers/OPNsense/Base/IndexController.php | head -40
