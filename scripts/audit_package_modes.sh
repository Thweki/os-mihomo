#!/bin/sh
# 包内权限审计：列出所有非 0644 的文件，确认可执行位正确
set -u
PKG=/usr/local/opnsense/_bak/pkgbuild/dist/os-mihomo.pkg

echo "=== 包内所有非 0644 的条目 ==="
tar -tvf "$PKG" 2>/dev/null | grep -v '^+MANIFEST\|^+COMPACT_MANIFEST' | awk '{print $1, $NF}' | grep -v '^-rw-r--r--' | sort -k2

echo
echo "=== 期望可执行清单核对 ==="
for f in /usr/local/bin/mihomo /usr/bin/mihomo_sub /usr/local/etc/rc.d/mihomo \
         /usr/local/etc/mihomo/sub/sub.sh /usr/local/opnsense/scripts/mihomo/setup_unbound.php \
         /usr/local/opnsense/scripts/mihomo/config_apply.php /usr/local/opnsense/scripts/mihomo/env.php \
         /usr/local/opnsense/scripts/mihomo/logclear.php /usr/local/opnsense/scripts/mihomo/logtail.php \
         /usr/local/opnsense/scripts/mihomo/service_enable.php \
         /usr/local/opnsense/scripts/mihomo/subscription_run.sh ; do
    mode=$(tar -tvf "$PKG" 2>/dev/null | awk -v f="$f" '$NF==f {print $1}')
    if [ "$mode" = "-rwxr-xr-x" ]; then
        printf '  OK    %-60s %s\n' "$f" "$mode"
    else
        printf '  FAIL  %-60s %s\n' "$f" "${mode:-（缺失）}"
    fi
done

echo
echo "=== 期望 0600 的敏感文件 ==="
for f in /usr/local/etc/mihomo/sub/env /usr/local/etc/mihomo/sub/template_config.yaml ; do
    mode=$(tar -tvf "$PKG" 2>/dev/null | awk -v f="$f" '$NF==f {print $1}')
    printf '  %-55s %s\n' "$f" "${mode:-（缺失）}"
done

echo
echo "=== 包内 +MANIFEST 的安装脚本 ==="
tar -xOf "$PKG" +MANIFEST 2>/dev/null | grep -A3 '^scripts:' | head -12
