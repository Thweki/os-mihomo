#!/bin/sh
# os-mihomo —— 启动/停止「隔离 demo 实例」
#
# 用途：让 WebUI 仪表盘拥有真实的控制器数据用于截图与联调。
#
# 安全边界（与 AGENTS.md 一致）：
#   · 不带 TUN（不创建 tun 设备、不修改任何路由）
#   · 不做 DNS 劫持（dns.enable=false，只监听 loopback 的 1054 且不启用）
#   · allow-lan=false，mixed-port 只绑 127.0.0.1
#   · 控制器只绑 127.0.0.1:9090（与插件默认配置一致）
#   · 与系统服务互不干扰：不使用 /var/run/mihomo.pid，不 enable 服务
set -u

DEMO_DIR=/tmp/mihomo-demo
PIDFILE=/var/run/mihomo-demo.pid
LOGFILE=/var/log/mihomo.log
BIN=/usr/local/bin/mihomo

ACTION="${1:-start}"

stop_demo() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE" 2>/dev/null || echo '')
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$PIDFILE"
        echo "demo instance stopped"
    else
        echo "demo instance not running"
    fi
    pkill -f "$DEMO_DIR" 2>/dev/null || true
}

case "$ACTION" in
    stop)
        stop_demo
        exit 0
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "demo instance running (pid $(cat "$PIDFILE"))"
            curl -s -m 3 -H 'Authorization: Bearer CHANGE_ME' http://127.0.0.1:9090/version
            echo
        else
            echo "demo instance not running"
        fi
        exit 0
        ;;
    start) ;;
    *) echo "usage: demo_instance.sh {start|stop|status}"; exit 2 ;;
esac

mkdir -p "$DEMO_DIR"

cat > "$DEMO_DIR/config.yaml" <<'YAML'
# 隔离演示配置 —— 无 tun / 无 dns 劫持 / 仅 loopback 监听
mixed-port: 17890
socks-port: 17891
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true
external-controller: 127.0.0.1:9090
secret: "CHANGE_ME"
profile:
  store-selected: true
  store-fake-ip: false
dns:
  enable: false
proxies:
  - name: "🇭🇰 香港 IEPL 01"
    type: trojan
    server: demo-hk01.example.invalid
    port: 443
    password: demo-password
    skip-cert-verify: true
  - name: "🇯🇵 日本 BGP 01"
    type: trojan
    server: demo-jp01.example.invalid
    port: 443
    password: demo-password
    skip-cert-verify: true
  - name: "🇸🇬 新加坡 CN2 01"
    type: trojan
    server: demo-sg01.example.invalid
    port: 443
    password: demo-password
    skip-cert-verify: true
  - name: "🇺🇸 美国 9929 01"
    type: trojan
    server: demo-us01.example.invalid
    port: 443
    password: demo-password
    skip-cert-verify: true
proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "♻️ 自动选择"
      - "🇭🇰 香港 IEPL 01"
      - "🇯🇵 日本 BGP 01"
      - "🇸🇬 新加坡 CN2 01"
      - "🇺🇸 美国 9929 01"
      - DIRECT
  - name: "♻️ 自动选择"
    type: url-test
    url: http://192.168.1.1/
    interval: 300
    tolerance: 50
    proxies:
      - DIRECT
  - name: "🤖 AI 服务"
    type: select
    proxies:
      - "🚀 节点选择"
      - "🇺🇸 美国 9929 01"
      - DIRECT
  - name: "📺 流媒体"
    type: select
    proxies:
      - "🚀 节点选择"
      - "🇭🇰 香港 IEPL 01"
      - DIRECT
rules:
  - DOMAIN-SUFFIX,cn,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - MATCH,DIRECT
YAML

stop_demo

# 日志复用插件自己的日志文件，这样「日志」页面截图展示的是真实内核输出
touch "$LOGFILE"
chmod 0640 "$LOGFILE"
chown root:wheel "$LOGFILE"

/usr/sbin/daemon -p "$PIDFILE" -o "$LOGFILE" "$BIN" -d "$DEMO_DIR"
sleep 2

if curl -s -m 3 -H 'Authorization: Bearer CHANGE_ME' http://127.0.0.1:9090/version > /dev/null; then
    echo "demo instance started: $(cat "$PIDFILE")"
    curl -s -m 3 -H 'Authorization: Bearer CHANGE_ME' http://127.0.0.1:9090/version
    echo
else
    echo "demo instance failed to answer on 127.0.0.1:9090"
    tail -20 "$LOGFILE"
    exit 1
fi
