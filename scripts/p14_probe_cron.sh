#!/bin/sh
# 取证：Cron 模型字段 + 生效方式（④ 订阅自动更新要用）
set -u
B=/usr/local/opnsense/mvc/app
echo "########## 1. Cron 模型 ##########"
ls -1 $B/models/OPNsense/Cron/ 2>/dev/null | sed 's/^/  /'
sed -n '1,60p' $B/models/OPNsense/Cron/Cron.xml 2>/dev/null | sed 's/^/  /'

echo
echo "########## 2. Cron 的 API / reconfigure ##########"
ls -1 $B/controllers/OPNsense/Cron/Api/ 2>/dev/null | sed 's/^/  /'
grep -n -A12 'function reconfigureAction' $B/controllers/OPNsense/Cron/Api/SettingsController.php 2>/dev/null | sed 's/^/  /'
grep -n 'function .*Action' $B/controllers/OPNsense/Cron/Api/SettingsController.php 2>/dev/null | head -10 | sed 's/^/  /'

echo
echo "########## 3. 现有 cron 任务（config.xml） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
cron = r.find('cron')
if cron is None:
    print('  (无 cron 节点)')
else:
    for job in cron.findall('item') or []:
        print('  ', {c.tag: (c.text or '') for c in job})
    print('  子节点:', [c.tag for c in cron])
PY

echo
echo "########## 4. cron 动作文件（有哪些 configctl cron 动作） ##########"
grep -o '^\[[a-z.]*\]' /usr/local/opnsense/service/conf/actions.d/actions_cron.conf 2>/dev/null | tr '\n' ' '
echo
ls -1 /usr/local/etc/cron.d/ 2>/dev/null | head -5 | sed 's/^/  /'

echo
echo "########## 5. 订阅命令（我们的 sub-update 动作） ##########"
grep -A3 '^\[sub-update\]' /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf | sed 's/^/  /'
