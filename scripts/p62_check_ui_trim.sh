#!/bin/sh
# 核对：设置页那段提示/按钮/状态行已消失，开关机制仍工作
set -u
BASE=https://127.0.0.1
JAR=/tmp/p62_jar.txt
PASS='${OPN_PW}'
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" -o /tmp/p62-settings.html

echo "########## 1. 应当消失的元素 ##########"
for kw in 'changed-summary' 'managedAllAct' 'managedNoneAct' '每一项前面都有一条' '全部取消勾选' '全部勾上' '将写入' '现在点「应用」不会改动配置文件'; do
    C=$(grep -c "$kw" /tmp/p62-settings.html || true)
    echo "  $([ "$C" = "0" ] && echo '已去掉 ✅' || echo "仍在 ❌ ($C)")  $kw"
done

echo
echo "########## 2. 应当保留的东西 ##########"
for kw in 'mihomo-managed-switch' 'leave alone' '不修改' 'id="mihomo\.' 'applyAct' 'restart-after-apply'; do
    C=$(grep -c "$kw" /tmp/p62-settings.html || true)
    echo "  $([ "$C" != "0" ] && echo '在 ✅' || echo '不见了 ❌')  $kw ($C)"
done

echo
echo "########## 3. 页面报错 ##########"
grep -c -E 'Fatal error|Parse error|Uncaught' /tmp/p62-settings.html | sed 's/^/  PHP 报错: /'

echo
echo "########## 4. 接口仍按「不修改」工作（后端语义没动） ##########"
TOKEN=$(curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | sed -n 's/.*X-CSRFToken", "\([^"]*\)".*/\1/p' | head -1)
BEFORE=$(md5 -q /usr/local/etc/mihomo/config.yaml)
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' \
     --data '{"mihomo":{"managed":""}}' "$BASE/api/mihomo/settings/set" > /dev/null
curl -sk -b "$JAR" -H "X-CSRFToken: $TOKEN" -H 'Content-Type: application/json' \
     --data '{"restart":0}' "$BASE/api/mihomo/settings/apply" | python3 -c "
import json,sys
d=json.load(sys.stdin); print('  status:', d.get('status')); [print('   ', m) for m in d.get('messages',[])]"
AFTER=$(md5 -q /usr/local/etc/mihomo/config.yaml)
echo "  config.yaml md5 不变: $([ "$BEFORE" = "$AFTER" ] && echo '是 ✅' || echo '否 ❌')"
rm -f "$JAR"
