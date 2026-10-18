#!/bin/sh
# 精确照抄对象：FilterController 的 CRUD 动作 + filter_rule.volt 的表格接线 + dialog 表单
set -u
FWC=/usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall
B=/usr/local/opnsense/mvc/app

echo "########## 1. FilterController 的 CRUD 动作（照抄这一套） ##########"
grep -n -A12 'function searchRuleAction' "$FWC/Api/FilterController.php" | head -30
echo "--- set/add/del/toggle ---"
grep -n -A8 'function setRuleAction\|function addRuleAction\|function delRuleAction\|function toggleRuleAction' "$FWC/Api/FilterController.php" | head -50

echo
echo "########## 2. 表格接线（filter_rule.volt 里 UIBootgrid 的完整参数） ##########"
grep -n -A22 'UIBootgrid(' $B/views/OPNsense/Firewall/filter_rule.volt | head -40

echo
echo "########## 3. 表格标记（含命令列/复选框列的写法） ##########"
grep -n -B3 -A30 'table id="grid-rule' $B/views/OPNsense/Firewall/filter_rule.volt | head -55

echo
echo "########## 4. 对话框表单样例（dialogFilterRule.xml 前 40 行） ##########"
sed -n '1,40p' "$FWC/forms/dialogFilterRule.xml"

echo
echo "########## 5. 对话框与命令列按钮的 HTML（filter_rule.volt 片段） ##########"
grep -n 'command-edit\|command-delete\|command-clone\|bootgrid-header\|dialog-form\|btn-xs' $B/views/OPNsense/Firewall/filter_rule.volt | head -15
