#!/bin/sh
# P12-2 · 步骤 5：接口分配 / DNAT / 过滤规则 的 API 用法
set -u
B=/usr/local/opnsense/mvc/app

echo "########## 1. Interfaces/Assignment 控制器 ##########"
grep -n 'function .*Action\|internalModel\|use OPNsense' $B/controllers/OPNsense/Interfaces/Api/AssignmentController.php 2>/dev/null | head -20 | sed 's/^/  /'
echo "--- 它的 reconfigure 做什么 ---"
grep -n -A8 'function reconfigureAction' $B/controllers/OPNsense/Interfaces/Api/AssignmentController.php 2>/dev/null | sed 's/^/  /'

echo
echo "########## 2. Interfaces 模型 ##########"
ls -1 $B/models/OPNsense/Interfaces/ 2>/dev/null | sed 's/^/  /'
grep -n 'type="\|<mount>' $B/models/OPNsense/Interfaces/Interfaces.xml 2>/dev/null | head -20 | sed 's/^/  /'

echo
echo "########## 3. DNat 模型（DNS 重定向要用的字段） ##########"
ls -1 $B/models/OPNsense/Firewall/ 2>/dev/null | sed 's/^/  /'
grep -n '<[a-z_]* type="' $B/models/OPNsense/Firewall/DNat.xml 2>/dev/null | head -26 | sed 's/^/  /'

echo
echo "########## 4. filter 规则的字段（含 gateway） ##########"
grep -n '<gateway\|<interface\|<source\|<destination\|<type\|<ipprotocol\|<direction\|<quick\|<descr' $B/models/OPNsense/Firewall/Filter.xml 2>/dev/null | head -20 | sed 's/^/  /'

echo
echo "########## 5. configctl 里与接口/过滤相关的动作 ##########"
grep -o '^\[[a-z.]*\]' /usr/local/opnsense/service/conf/actions.d/actions_filter.conf 2>/dev/null | head -6 | tr '\n' ' '
echo
ls -1 /usr/local/opnsense/service/conf/actions.d/ | grep -i 'interface\|routing' | sed 's/^/  /'
grep -o '^\[[a-z.]*\]' /usr/local/opnsense/service/conf/actions.d/actions_routing.conf 2>/dev/null | tr '\n' ' '
