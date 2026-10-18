#!/bin/sh
# P12-2 · 步骤 4：Routing(网关) / Interfaces(接口分配) 的原生 API
set -u
echo "########## 1. Routing 的 API 控制器 ##########"
ls -1 /usr/local/opnsense/mvc/app/controllers/OPNsense/Routing/Api/ 2>/dev/null | sed 's/^/  /'
for f in /usr/local/opnsense/mvc/app/controllers/OPNsense/Routing/Api/*.php; do
    [ -f "$f" ] || continue
    echo "--- $(basename $f) ---"
    grep -n 'function .*Action\|internalModel' "$f" | head -12 | sed 's/^/  /'
done

echo
echo "########## 2. Routing 模型结构（网关条目字段） ##########"
sed -n '1,60p' /usr/local/opnsense/mvc/app/models/OPNsense/Routing/Gateways.xml 2>/dev/null | sed 's/^/  /'

echo
echo "########## 3. Interfaces 的 API 控制器 ##########"
ls -1 /usr/local/opnsense/mvc/app/controllers/OPNsense/Interfaces/Api/ 2>/dev/null | sed 's/^/  /'
for f in /usr/local/opnsense/mvc/app/controllers/OPNsense/Interfaces/Api/*.php; do
    [ -f "$f" ] || continue
    echo "--- $(basename $f) ---"
    grep -n 'function .*Action\|internalModel' "$f" | head -10 | sed 's/^/  /'
done

echo
echo "########## 4. Interfaces 模型（接口分配字段） ##########"
ls -1 /usr/local/opnsense/mvc/app/models/OPNsense/Interfaces/ 2>/dev/null | sed 's/^/  /'
sed -n '1,40p' /usr/local/opnsense/mvc/app/models/OPNsense/Interfaces/Interfaces.xml 2>/dev/null | sed 's/^/  /'

echo
echo "########## 5. relay 相关动作（如有 reconfigure） ##########"
grep -o '^\[[a-z.]*\]' /usr/local/opnsense/service/conf/actions.d/actions_interface*.conf 2>/dev/null | head -12 | tr '\n' ' '
echo
grep -rn 'gateway' /usr/local/opnsense/mvc/app/models/OPNsense/Routing/Gateways.xml 2>/dev/null | head -8 | sed 's/^/  /'
