#!/bin/sh
# P12-2 · 步骤 6：NetworkInterface 与 Filter 模型结构（写模型时用的字段名）
set -u
B=/usr/local/opnsense/mvc/app/models/OPNsense

echo "########## 1. NetworkInterface.xml ##########"
sed -n '1,55p' $B/Interfaces/NetworkInterface.xml | sed 's/^/  /'

echo
echo "########## 2. AssignmentController 的 add/set 实现 ##########"
sed -n '41,80p' /usr/local/opnsense/mvc/app/controllers/OPNsense/Interfaces/Api/AssignmentController.php | sed 's/^/  /'

echo
echo "########## 3. Filter.xml 的规则字段（外层 + 源/目标） ##########"
grep -n '<rule type\|<type\|<interface\|<ipprotocol\|<protocol\|<source type\|<destination type\|<network\|<any\|<port\|<gateway\|<direction\|<statetype\|<descr\|<quick' $B/Firewall/Filter.xml | head -30 | sed 's/^/  /'

echo
echo "########## 4. Filter 模型里 gateway 字段的类型/约束 ##########"
grep -n -A12 '<gateway' $B/Firewall/Filter.xml | head -30 | sed 's/^/  /'
