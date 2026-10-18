#!/bin/sh
# 照抄对象：核心防火墙页的「表格 + 对话框 + 应用」实现惯例
set -u
FWC=/usr/local/opnsense/mvc/app/controllers/OPNsense/Firewall
echo "########## 1. 核心：规则 API 控制器的 CRUD 惯例（FilterBaseController 片段） ##########"
grep -n 'searchBase\|getBase\|setBase\|addBase\|delBase\|toggleBase\|protected function\|use OPNsense' \
    "$FWC/Api/FilterBaseController.php" 2>/dev/null | head -30

echo
echo "########## 2. 核心：规则对话框表单（filter_rule.xml 片段） ##########"
sed -n '1,45p' "$FWC/forms/filter_rule.xml" 2>/dev/null

echo
echo "########## 3. 核心：页面里表格 + 对话框 + 应用按钮的写法（filter.volt 片段） ##########"
grep -n 'UIBootgrid\|bootgrid\|base_form\|apply\|BootstrapDialog\|dialog\|jsonLint\|id="grid\|table id' \
    /usr/local/opnsense/mvc/app/views/OPNsense/Firewall/filter.volt 2>/dev/null | head -25

echo
echo "########## 4. 现网 config.yaml 的 rules 段（前 25 行） ##########"
awk '/^rules:/{f=1} f{print; n++} n>24{exit}' /usr/local/etc/mihomo/config.yaml

echo
echo "########## 5. 模板里的 rules 段（前 15 行） ##########"
awk '/^rules:/{f=1} f{print; n++} n>14{exit}' /usr/local/etc/mihomo/sub/template_config.yaml

echo
echo "########## 6. 代理组名字（给下拉用） ##########"
awk '/^proxy-groups:/{f=1;next} f&&/^- |^  - /{print} f&&/^[a-z]/&&!/^proxy-groups/{exit}' /usr/local/etc/mihomo/config.yaml | grep -o 'name:.*' | head -12

echo
echo "########## 7. 模板里的代理组（同上） ##########"
grep -n 'name:' /usr/local/etc/mihomo/sub/template_config.yaml | head -12
