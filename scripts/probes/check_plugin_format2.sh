#!/bin/sh
# 取证 2：真实插件的 manifest / 目录 / 版本文件 / 固件系统如何管理 os-* 包
set -u

echo "########## 1. 真实插件的原始 manifest ##########"
for p in os-ttyd os-ddns-go os-caddy; do
    echo "===== $p ====="
    pkg info -R "$p" 2>&1 | head -60
    echo
done

echo "########## 2. os-* 包的 name/origin/version ##########"
pkg query -g '%n|%o|%v|%q' 'os-*' 2>&1 | head -20

echo
echo "########## 3. ABI / 签名配置 ##########"
echo -n "ABI: "; pkg config abi 2>/dev/null
grep -E 'SIGNATURE_TYPE|FINGERPRINTS|IMMUTABLE' /usr/local/etc/pkg.conf 2>/dev/null || echo "(pkg.conf 无 SIGNATURE_TYPE)"

echo
echo "########## 4. 固件系统对 os-* 包的特殊处理（install.sh） ##########"
sed -n '20,80p' /usr/local/opnsense/scripts/firmware/install.sh

echo
echo "########## 5. 插件版本文件内容 ##########"
echo "--- ddns-go ---"; cat /usr/local/opnsense/version/ddns-go 2>/dev/null
echo "--- ttyd ---";    cat /usr/local/opnsense/version/ttyd 2>/dev/null
echo "--- 我们的 mihomo ---"; cat /usr/local/opnsense/version/mihomo 2>/dev/null

echo
echo "########## 6. 受管插件的文件布局（os-ttyd 为例） ##########"
pkg info -l os-ttyd 2>/dev/null | head -30

echo
echo "########## 7. 同族插件的 MVC 目录约定 ##########"
ls -1 /usr/local/opnsense/mvc/app/models/OPNsense/ 2>/dev/null
echo "--- ddns-go 的模型目录 ---"
find /usr/local/opnsense/mvc/app/models/OPNsense/DDNSGo /usr/local/opnsense/mvc/app/models/OPNsense/Ddnsgo /usr/local/opnsense/mvc/app/models/OPNsense/Ttyd 2>/dev/null | head -20

echo
echo "########## 8. 插件页面/固件页用的 configd 动作 ##########"
grep -n 'plugins\|query' /usr/local/opnsense/service/conf/actions.d/actions_firmware.conf 2>/dev/null | head -20
