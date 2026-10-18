#!/bin/sh
# 回滚演练 · 阶段一（单次调用完成：快照 → 暂存配置 → 回滚 → 校验）
# 依赖：/tmp/mihomo-managed-files.txt（由 tools/rollback_drill.ps1 先推送）
set -u

BAK=/usr/local/opnsense/_bak/os-mihomo/20261018_102822
ASIDE=/tmp/mihomo-drill-aside
LIST=/tmp/mihomo-managed-files.txt
LATEST=/tmp/drill-latest.txt
ROLLED=/tmp/drill-rolledback.txt

[ -f "$LIST" ] || { echo "缺少 $LIST"; exit 2; }

echo "########## 1. 快照当前状态（LATEST）##########"
: > "$LATEST"
while read -r f; do
    [ -z "$f" ] && continue
    if [ -f "/$f" ]; then
        printf '%s %s\n' "$f" "$(sha256 -q "/$f")" >> "$LATEST"
    else
        printf '%s MISSING\n' "$f" >> "$LATEST"
    fi
done < "$LIST"
echo "  受管文件数: $(wc -l < "$LATEST")"
grep -c MISSING "$LATEST" | sed 's/^/  缺失: /'

echo
echo "########## 2. 暂存 config.yaml 与 rc.conf.d（配置数据不参与回滚）##########"
mkdir -p "$ASIDE"
cp -a /usr/local/etc/mihomo/config.yaml "$ASIDE/config.yaml"
cp -a /etc/rc.conf.d/mihomo "$ASIDE/rc.conf.d-mihomo"
ls -la "$ASIDE"

echo
echo "########## 3. 从备份集回滚代码文件：$BAK ##########"
restored=0
while read -r f; do
    [ -z "$f" ] && continue
    if [ -f "$BAK/$f" ]; then
        mkdir -p "$(dirname "/$f")"
        cp -a "$BAK/$f" "/$f"
        restored=$((restored + 1))
    fi
done < "$LIST"
echo "  恢复 $restored 个文件"

echo
echo "########## 4. 校验回滚结果 ##########"
: > "$ROLLED"
while read -r f; do
    [ -z "$f" ] && continue
    if [ -f "/$f" ]; then
        printf '%s %s\n' "$f" "$(sha256 -q "/$f")" >> "$ROLLED"
    else
        printf '%s MISSING\n' "$f" >> "$ROLLED"
    fi
done < "$LIST"

echo "  与 LATEST 不同的文件（期望 > 0）："
diff "$LATEST" "$ROLLED" | grep '^<' | awk '{print "    - " $2}' | head -14
CHANGED=$(diff "$LATEST" "$ROLLED" | grep -c '^<' || true)
echo "  差异文件数: $CHANGED"

echo
echo "  与备份集逐字节比对（期望 0 处不一致）："
ok=0; bad=0
while read -r f; do
    [ -z "$f" ] && continue
    if [ -f "$BAK/$f" ] && [ -f "/$f" ]; then
        if [ "$(sha256 -q "$BAK/$f")" = "$(sha256 -q "/$f")" ]; then
            ok=$((ok + 1))
        else
            bad=$((bad + 1)); echo "    MISMATCH $f"
        fi
    fi
done < "$LIST"
echo "    一致 $ok / 不一致 $bad"

echo
echo "  回滚后页面可用性（未登录 302 = 正常响应）："
for p in /ui/mihomo /ui/mihomo/settings /ui/mihomo/subscription /ui/mihomo/log /mihomo.php; do
    printf '    %-30s %s\n' "$p" "$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1$p")"
done

echo
echo "  版本标记（期望呈现旧版特征）："
printf '    valuesEqual（新）: '; grep -q valuesEqual /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php && echo YES || echo "no -> 已回滚到旧版"
printf '    checkbox（新）   : '; grep -q '<type>checkbox</type>' /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml && echo YES || echo "no -> 已回滚到旧版"
printf '    菜单项数量       : '; grep -c 'url="/ui/mihomo' /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml

echo
echo "########## 阶段一完成（脚本语法自检）##########"
php -l /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php
php -l /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SettingsController.php
echo "########## PHASE1 DONE ##########"
