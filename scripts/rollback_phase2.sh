#!/bin/sh
# 回滚演练 · 阶段二（重新部署之后：校验回到 LATEST → 恢复配置数据）
set -u

ASIDE=/tmp/mihomo-drill-aside
LIST=/tmp/mihomo-managed-files.txt
LATEST=/tmp/drill-latest.txt
REDEP=/tmp/drill-redeployed.txt

FAIL=0

echo "########## 5. 快照重新部署后的状态 ##########"
: > "$REDEP"
while read -r f; do
    [ -z "$f" ] && continue
    if [ -f "/$f" ]; then
        printf '%s %s\n' "$f" "$(sha256 -q "/$f")" >> "$REDEP"
    else
        printf '%s MISSING\n' "$f" >> "$REDEP"
        FAIL=$((FAIL + 1))
        echo "    MISSING $f"
    fi
done < "$LIST"
echo "  受管文件数: $(wc -l < "$REDEP")"

echo
echo "########## 6. 与回滚前（LATEST）比对 ##########"
if diff -q "$LATEST" "$REDEP" > /dev/null 2>&1; then
    echo "  PASS：重新部署后与回滚前逐字节一致"
else
    echo "  FAIL：存在差异"
    diff "$LATEST" "$REDEP" | grep '^[<>]' | head -20
    FAIL=$((FAIL + 1))
fi

echo
echo "  版本标记（期望全部为新版特征）："
printf '    valuesEqual（新）: '; grep -q valuesEqual /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php && echo YES || { echo no; FAIL=$((FAIL+1)); }
printf '    Safety.shorten    : '; grep -q 'function shorten' /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Safety.php && echo YES || { echo no; FAIL=$((FAIL+1)); }
printf '    checkbox          : '; grep -q '<type>checkbox</type>' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml && echo YES || { echo no; FAIL=$((FAIL+1)); }
printf '    fail()写stdout    : '; grep -q "echo 'ERROR: '" /usr/local/opnsense/scripts/mihomo/config_apply.php && echo YES || { echo no; FAIL=$((FAIL+1)); }
printf '    菜单项数量        : '; grep -c 'url="/ui/mihomo' /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml

echo
echo "  页面可用性："
for p in /ui/mihomo /ui/mihomo/settings /ui/mihomo/subscription /ui/mihomo/log; do
    printf '    %-30s %s\n' "$p" "$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1$p")"
done

echo
echo "########## 7. 恢复 config.yaml 与 rc.conf.d ##########"
if [ -f "$ASIDE/config.yaml" ]; then
    cp -a "$ASIDE/config.yaml" /usr/local/etc/mihomo/config.yaml
    chmod 0644 /usr/local/etc/mihomo/config.yaml
    chown root:wheel /usr/local/etc/mihomo/config.yaml
    cp -a "$ASIDE/rc.conf.d-mihomo" /etc/rc.conf.d/mihomo
    chmod 0644 /etc/rc.conf.d/mihomo
    echo "  配置数据已恢复："
else
    echo "  !! 找不到暂存副本"
    FAIL=$((FAIL + 1))
fi
grep -nE '^(log-level|external-controller):' /usr/local/etc/mihomo/config.yaml
cat /etc/rc.conf.d/mihomo
service mihomo status

echo
echo "  清理演练临时文件"
rm -rf "$ASIDE"
rm -f /tmp/drill-latest.txt /tmp/drill-rolledback.txt /tmp/drill-redeployed.txt /tmp/mihomo-managed-files.txt
ls -d /tmp/drill-* /tmp/mihomo-* 2>/dev/null || echo "  (clean)"

echo
echo "########## ROLLBACK DRILL RESULT: $FAIL failures ##########"
exit $FAIL
