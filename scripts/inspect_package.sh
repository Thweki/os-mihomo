#!/bin/sh
# 检查构建出的包：元数据 + 文件清单 + 关键文件是否齐全
set -u
BUILD=/usr/local/opnsense/_bak/pkgbuild
PKG="$BUILD/dist/os-mihomo.pkg"

echo "=== 1. 包元数据 ==="
pkg info -F "$PKG"

echo
echo "=== 2. 文件总数 ==="
tar -tf "$PKG" | grep -v '^+MANIFEST$\|^+COMPACT_MANIFEST$' | wc -l

echo
echo "=== 3. 关键新增文件（本次二次开发）==="
for f in \
    /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.xml \
    /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php \
    /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Safety.php \
    /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/DashboardController.php \
    /usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/index.volt \
    /usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt \
    /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml \
    /usr/local/opnsense/scripts/mihomo/config_apply.php \
    /usr/local/etc/mihomo/config.yaml \
    /usr/local/bin/mihomo \
    /usr/local/www/mihomo.php \
    /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml \
    /usr/local/opnsense/version/mihomo ; do
    if tar -tf "$PKG" | grep -qx "$f"; then
        printf '  OK    %s\n' "$f"
    else
        printf '  MISS  %s\n' "$f"
    fi
done

echo
echo "=== 4. 内核二进制是否进包（权限应为 0755）==="
tar -tvf "$PKG" 2>/dev/null | grep 'usr/local/bin/mihomo$' || echo "(没找到)"

echo
echo "=== 5. 可执行脚本权限抽查 ==="
tar -tvf "$PKG" 2>/dev/null | egrep 'config_apply.php|subscription_run.sh|rc.d/mihomo|mihomo_sub$'
