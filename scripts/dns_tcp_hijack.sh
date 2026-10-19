#!/bin/sh
# os-mihomo —— 给运行中的 config.yaml 补上 TCP DNS 劫持（幂等、可回滚）
#
# 背景：mihomo 的 tun.dns-hijack 里没有协议前缀的条目按 udp:// 处理；
#       只写 any:53 时，客户端退到 TCP 53 的 DNS 查询不会被劫持。
#
# 流程：
#   1) tun 块里已有 dns-hijack 就不动（幂等）
#   2) awk 在 tun 块末尾插入 any:53 + tcp://any:53
#   3) 交给 config_apply.php install：mihomo -t 校验 + 时间戳备份 + 原子替换
#   4) configctl mihomo restart 生效（会短暂中断被策略路由接口的出网）
#
# 用法：tools/remote.ps1 -Script scripts/dns_tcp_hijack.sh
set -eu

CONFIG=/usr/local/etc/mihomo/config.yaml
TEMPLATE=/usr/local/etc/mihomo/sub/template_config.yaml
APPLY=/usr/local/opnsense/scripts/mihomo/config_apply.php

[ -f "$CONFIG" ] || { echo "missing $CONFIG"; exit 2; }

echo "== 现状：config.yaml tun 块 =="
awk '/^tun:/{f=1} f{print} /^[A-Za-z0-9_-]+:/{if(f && $0 !~ /^tun:/) exit}' "$CONFIG" | sed 's/^/  /'
echo "== 现状：模板里的 dns-hijack =="
grep -n 'dns-hijack' "$TEMPLATE" || echo "  (模板里没有)"

if awk '
    /^tun:/ { f=1 }
    f && /^  dns-hijack:/ { found=1 }
    /^[A-Za-z0-9_-]+:/ { if (f && $0 !~ /^tun:/) exit }
    END { exit found ? 0 : 1 }
' "$CONFIG"; then
    echo "config.yaml 的 tun 块已有 dns-hijack，无需修改"
else
    TMP=$(mktemp /tmp/mihomo-XXXXXX)
    chmod 0600 "$TMP"
    awk '
      BEGIN { intun=0; inserted=0 }
      /^tun:[ \t]*$/ { intun=1; print; next }
      intun && /^[^ \t]/ {
          if (!inserted) {
              print "  dns-hijack:"
              print "    - any:53"
              print "    - tcp://any:53"
              inserted=1
          }
          intun=0
      }
      { print }
      END {
          if (intun && !inserted) {
              print "  dns-hijack:"
              print "    - any:53"
              print "    - tcp://any:53"
          }
      }
    ' "$CONFIG" > "$TMP"

    echo "== 新 tun 块 =="
    awk '/^tun:/{f=1} f{print} /^[A-Za-z0-9_-]+:/{if(f && $0 !~ /^tun:/) exit}' "$TMP" | sed 's/^/  /'

    echo "== 校验并安装（mihomo -t + 备份 + 原子替换）=="
    /usr/local/bin/php "$APPLY" install "$TMP"
fi

echo "== 重启服务 =="
configctl mihomo restart
sleep 4

echo "== 运行态 dns-hijack =="
curl -s --max-time 3 http://127.0.0.1:9090/configs | tr ',' '\n' | grep -i 'dns-hijack' || true
echo "== 服务状态 =="
service mihomo status || true
