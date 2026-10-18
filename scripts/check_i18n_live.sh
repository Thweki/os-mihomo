#!/bin/sh
# 用已登录会话抓取页面，确认插件词条已生效（中文）
set -u
BASE=https://127.0.0.1
JAR=/tmp/i18n_jar.txt
rm -f "$JAR"

LOGIN_PAGE=$(curl -sk -c "$JAR" "$BASE/index.php")
NAME=$(printf '%s' "$LOGIN_PAGE" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
VALUE=$(printf '%s' "$LOGIN_PAGE" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=${OPN_PW}&$NAME=$VALUE" "$BASE/index.php"

echo "=== 各页面命中插件中文词条的情况 ==="
check() {
    url="$1"; shift
    html=$(curl -sk -b "$JAR" "$BASE$url")
    printf '%-30s ' "$url"
    for pat in "$@"; do
        if printf '%s' "$html" | grep -q "$pat"; then printf '[%s OK] ' "$pat"; else printf '[%s -] ' "$pat"; fi
    done
    echo
}

check /ui/mihomo '代理分组' '活动连接' '流量图表' '未运行'
check /ui/mihomo/settings '配置文件' '访问密钥' '订阅地址' '通信'
check /ui/mihomo/subscription '订阅管理' '开始订阅' '日志视图'
check /ui/mihomo/log '内核日志' '订阅日志' '清空日志' '字节'

echo
echo "=== 抽样：设置页里「设置 / 配置文件」两个标签 ==="
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" | grep -o '>[^<]*</a>' | grep -E '设置|配置' | head -5

echo
echo "=== 对照：核心页面（Unbound）仍为中文（说明核心词条未被破坏）==="
curl -sk -b "$JAR" "$BASE/ui/unbound/overview" | grep -o '概况\|详细\|设置\|黑名单数量' | sort -u | head -5

rm -f "$JAR"
