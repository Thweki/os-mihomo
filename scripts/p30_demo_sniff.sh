#!/bin/sh
# 隔离取证：/configs 的 sniffing 字段是否等于 sniffer.enable（用独立 demo 实例，不碰线上服务）
# 安全：无 tun、无 dns-hijack、allow-lan:false、控制器绑 127.0.0.1:9098/9099、混合端口 0
set -u
D=/tmp/mihomo-demo-sniff
mkdir -p "$D"
cd "$D"

mk() {
    cat > "$1" <<EOF
mixed-port: 0
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: silent
external-controller: 127.0.0.1:$2
secret: ''
sniffer:
  enable: $3
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
}

try() {
    enable="$1"; port="$2"
    mk "$D/config.yaml" "$port" "$enable"
    /usr/local/bin/mihomo -d "$D" -f "$D/config.yaml" >/dev/null 2>&1 &
    pid=$!
    sleep 2
    out=$(curl -s -m 3 "http://127.0.0.1:$port/configs")
    echo "  sniffer.enable=$enable → $(printf '%s' "$out" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print('sniffing=%s  ' % d.get('sniffing'), end='')
except Exception as e:
    print('(读不到) ', end='')
")"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    sleep 1
}

echo "########## 隔离 demo：sniffing 字段与 sniffer.enable 的关系 ##########"
try true 9098
try false 9099

echo
echo "########## 清理 ##########"
rm -rf "$D"
echo "  已清理 $D"
echo "  线上服务: $(service mihomo status 2>&1 | head -1)"
