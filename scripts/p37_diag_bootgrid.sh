#!/bin/sh
# 找出 UIBootgrid 的实现在哪儿，看它怎么填编辑对话框
set -u
echo "########## 1. 谁定义了 UIBootgrid ##########"
grep -rln 'UIBootgrid' /usr/local/opnsense/www/js/ 2>/dev/null | sed 's/^/  /'
grep -rln 'UIBootgrid' /usr/local/www/*.js /usr/local/opnsense/mvc/app/views/layout_partials/*.volt 2>/dev/null | sed 's/^/  /'

echo
echo "########## 2. 填对话框的代码 ##########"
F=$(grep -rln 'UIBootgrid' /usr/local/opnsense/www/js/ 2>/dev/null | head -1)
echo "  文件: $F"
if [ -n "$F" ]; then
    grep -n 'setFormData\|data\[.*\]\|dialog_form\|edit_dialog\|toForm' "$F" | head -30 | sed 's/^/    /'
fi

echo
echo "########## 3. 核心页面用同款模式的例子（防火墙规则） ##########"
grep -n 'getRuleAction\|searchRuleAction' /usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall/Api/*.php 2>/dev/null | head -5 | sed 's/^/  /'
ls /usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall/forms/ 2>/dev/null | head -10 | sed 's/^/  /'

echo
echo "########## 4. 防火墙规则对话框表单里 OptionField 的写法 ##########"
F2=/usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall/forms/dialogRule.xml
if [ -f "$F2" ]; then
    grep -A8 '<id>rule.ipprotocol</id>\|<id>ipprotocol</id>' "$F2" | head -16 | sed 's/^/  /'
else
    ls /usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall/forms/ | sed 's/^/  /'
fi
