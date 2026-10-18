#!/bin/sh
# 取证 2：cron 的 command 字段取值格式 + 模板如何渲染 + description 字段
set -u
B=/usr/local/opnsense/mvc/app
echo "########## 1. Cron.xml 剩余部分（description 等） ##########"
sed -n '60,110p' $B/models/OPNsense/Cron/Cron.xml | sed 's/^/  /'

echo
echo "########## 2. ConfigdActionsField 的取值格式 ##########"
find $B/models/OPNsense/Cron -name '*.php' | sed 's/^/  /'
sed -n '1,80p' $B/models/OPNsense/Cron/FieldTypes/ConfigdActionsField.php 2>/dev/null | grep -n 'getNodeData\|configd\|function\|=>' | head -20 | sed 's/^/  /'

echo
echo "########## 3. cron 模板如何渲染 job（找 configctl 调用） ##########"
find /usr/local/opnsense/service/templates -ipath '*Cron*' 2>/dev/null | sed 's/^/  /'
for f in $(find /usr/local/opnsense/service/templates -ipath '*Cron*' -type f 2>/dev/null | head -3); do
    echo "  --- $f ---"
    grep -n 'configctl\|command\|parameters\|who' "$f" | head -8 | sed 's/^/    /'
done

echo
echo "########## 4. Cron 的 reconfigure（改完怎么生效） ##########"
grep -n -A10 'function reconfigureAction' $B/controllers/OPNsense/Cron/Api/SettingsController.php | sed 's/^/  /'
grep -n 'function .*Action' $B/controllers/OPNsense/Cron/Api/SettingsController.php | head -8 | sed 's/^/  /'

echo
echo "########## 5. 已安装的 cron 任务（当前 config.xml） ##########"
python3 - <<'PY'
import xml.etree.ElementTree as ET
r = ET.parse('/conf/config.xml').getroot()
cron = r.find('cron')
if cron is None or len(cron) == 0:
    print('  (无 cron 任务)')
else:
    for job in cron.findall('job'):
        print('  ', {c.tag: (c.text or '') for c in job})
PY
