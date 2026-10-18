#!/bin/sh
# 精简版：只做「产生流量 + 测速」，不做 pkill / 长连接管理
set -u

echo "=== 1. 经 demo 代理发几个请求 ==="
for url in http://192.168.1.1/favicon.ico http://192.168.1.1/; do
    code=$(curl -s -o /dev/null -m 6 -x http://127.0.0.1:17890 -w '%{http_code}' "$url" || echo timeout)
    echo "  $code  $url"
done

echo
echo "=== 2. 延时测速（给节点卡上真实数字）==="
curl -s -m 8 -H 'Authorization: Bearer CHANGE_ME' \
     "http://127.0.0.1:9090/proxies/DIRECT/delay?timeout=5000&url=http://cp.cloudflare.com/generate_204"
echo
GROUP=$(python3 -c "import urllib.parse; print(urllib.parse.quote('♻️ 自动选择'))")
curl -s -m 10 -H 'Authorization: Bearer CHANGE_ME' \
     "http://127.0.0.1:9090/proxies/${GROUP}/delay?timeout=5000&url=http://cp.cloudflare.com/generate_204"
echo

echo
echo "=== 3. 连接快照 ==="
curl -s -m 5 -H 'Authorization: Bearer CHANGE_ME' http://127.0.0.1:9090/connections \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('connections:', len(d.get('connections',[])), 'down:', d.get('downloadTotal'), 'up:', d.get('uploadTotal'))"
