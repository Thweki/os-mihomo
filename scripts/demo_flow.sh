#!/bin/sh
# 启动若干限速长连接，制造持续流量（用于仪表盘截图），并打印快照
set -u

echo "=== 清理旧的下载进程 ==="
pkill -f 'speed.cloudflare.com' 2>/dev/null || true
sleep 1

echo "=== 启动 4 条限速长连接（每条约 60KB/s，最长 20 分钟）==="
i=1
while [ "$i" -le 4 ]; do
    nohup curl -s -o /dev/null --limit-rate 60k -m 1200 \
        -x http://127.0.0.1:17890 \
        "https://speed.cloudflare.com/__down?bytes=80000000&seed=$i" \
        > /dev/null 2>&1 &
    i=$((i + 1))
done

sleep 8

echo
echo "=== 快照 ==="
curl -s -m 6 -H 'Authorization: Bearer CHANGE_ME' http://127.0.0.1:9090/connections > /tmp/conn.json
wc -c /tmp/conn.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/conn.json'))
print('connections:', len(d.get('connections', [])))
print('downloadTotal:', d.get('downloadTotal'))
print('uploadTotal:', d.get('uploadTotal'))
PY
