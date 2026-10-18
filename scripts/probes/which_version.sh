#!/bin/sh
# 判定当前安装的是哪个版本（新版特征 vs 旧版特征）
set -u

echo "=== 新版特征检查（应全部 YES）==="
printf 'config.yaml 含 valuesEqual（补丁器最小化）: '
grep -q 'valuesEqual' /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php && echo YES || echo "no"
printf 'Safety.php 含 shorten()                      : '
grep -q 'function shorten' /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Safety.php && echo YES || echo "no"
printf 'index.volt 含原生统计卡 stat-rate-down        : '
grep -q 'stat-rate-down' /usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/index.volt && echo YES || echo "no"
printf 'Menu.xml 为 3 层（Mihomo 与 Settings 同级）   : '
grep -q '<MihomoVisibleName="Mihomo"\|<Mihomo VisibleName="Mihomo" order="10" url="/ui/mihomo"' /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml && echo YES || echo "no"
printf 'settings.xml 用 checkbox（非 boolean）       : '
grep -q '<type>checkbox</type>' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml && ! grep -q '<type>boolean</type>' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml && echo YES || echo "no"
printf 'config_apply.php 的 fail() 写 stdout         : '
grep -q "echo 'ERROR: '" /usr/local/opnsense/scripts/mihomo/config_apply.php && echo YES || echo "no"

echo
echo "=== Menu.xml 全文 ==="
cat /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml

echo
echo "=== config.yaml 受管键 ==="
grep -nE '^(log-level|external-controller|secret):' /usr/local/etc/mihomo/config.yaml

echo
echo "=== 自启开关 / 服务 ==="
cat /etc/rc.conf.d/mihomo
service mihomo status

echo
echo "=== 临时演练文件 ==="
ls -la /tmp/drill-* /tmp/mihomo-drill-aside 2>/dev/null || echo "(none)"
