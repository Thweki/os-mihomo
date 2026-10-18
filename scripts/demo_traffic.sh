#!/bin/sh
# 确认 demo 实例没有触碰任何网络配置，并产生一些真实流量用于截图
set -u

echo "=== 1. 接口列表（不应出现 tun）==="
ifconfig -l
echo
echo "=== 2. 路由表指纹（应与基线一致）==="
netstat -rn | sha256 -q
echo "(baseline: 46676138fb379ef3d35734169a6d25b4be0aff73958bd853273260e1898c5619)"
echo
echo "=== 3. pf 规则指纹（应与基线一致）==="
pfctl -sr 2>/dev/null | sha256 -q
echo "(baseline: b85859445a7be9b8733e16393216dd7e8d06bebb6ec0438e068ce151ef95aaa6)"
echo
echo "=== 4. 监听端口 ==="
sockstat -4 -l 2>/dev/null | egrep ':9090|:17890|:17891'
echo
echo "=== 5. demo 进程 ==="
ps aux | grep -v grep | grep 'mihomo-demo' | head -3

echo
echo "=== 6. 产生流量（经 demo 代理抓取几个请求）==="
for url in http://192.168.1.1/ http://192.168.1.1/index.php; do
    code=$(curl -s -o /dev/null -m 8 -x http://127.0.0.1:17890 -w '%{http_code}' "$url" || echo fail)
    echo "  $url -> $code"
done

echo
echo "=== 7. 启动若干个长连接（限速下载，制造持续流量）==="
pkill -f 'speed.cloudflare.com' 2>/dev/null || true
pkill -f 'limit-rate' 2>/dev/null || true
for i in 1 2 3; do
    nohup curl -s -o /dev/null --limit-rate 60k -m 900 \
        -x http://127.0.0.1:17890 \
        "https://speed.cloudflare.com/__down?bytes=50000000&seed=$i" \
        > /dev/null 2>&1 &
done
sleep 6
echo
echo "=== 8. 连接快照（控制器）==="
curl -s -m 5 -H 'Authorization: Bearer CHANGE_ME' http://127.0.0.1:9090/connections \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('connections:', len(d.get('connections',[])), 'down:', d.get('downloadTotal'), 'up:', d.get('uploadTotal'), 'mem:', d.get('memory'))"
echo
echo "=== 9. 触发一次延迟测速（给节点卡上真实数字）==="
curl -s -m 8 -H 'Authorization: Bearer CHANGE_ME' "http://127.0.0.1:9090/proxies/DIRECT/delay?timeout=5000&url=http://192.168.1.1/"
echo
curl -s -m 8 -H 'Authorization: Bearer CHANGE_ME' "http://127.0.0.1:9090/proxies/%F0%9F%94%81%20%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9/delay?timeout=5000&url=http://192.168.1.1/"
echo
echo "=== DONE ==="
