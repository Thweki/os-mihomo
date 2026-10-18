#!/bin/sh
# 检查 Apply 后的 config.yaml 差异
set -u

echo "=== 受管键当前值 ==="
grep -nE '^(log-level|mode|allow-lan|external-controller|secret|socks-port):' /usr/local/etc/mihomo/config.yaml
echo "--- tun.* ---"
awk '/^tun:/{f=1} f&&/^[a-z]/{if($0!~/^tun:/)f=0} f' /usr/local/etc/mihomo/config.yaml | grep -E 'enable|device|stack|auto-route|strict-route|mtu'
echo "--- dns.* ---"
awk '/^dns:/{f=1} f&&/^[a-z]/{if($0!~/^dns:/)f=0} f' /usr/local/etc/mihomo/config.yaml | grep -E '^\s+(enable|listen|enhanced-mode):'

echo
echo "=== 备份文件 ==="
ls -la /usr/local/etc/mihomo/config.yaml.bak.* 2>/dev/null | tail -3

echo
echo "=== 与"部署时原始文件"的差异 ==="
ORIG=$(ls -1t /usr/local/opnsense/_bak/os-mihomo/*/usr/local/etc/mihomo/config.yaml 2>/dev/null | tail -1)
echo "原始: $ORIG"
if [ -n "$ORIG" ]; then
    diff -u "$ORIG" /usr/local/etc/mihomo/config.yaml && echo "(无差异)"
else
    echo "(未找到原始备份，与 /tmp 里的副本比较)"
fi

echo
echo "=== 结构完整性：proxies / proxy-groups / rules 是否完好 ==="
echo "proxies 节点数: $(awk '/^proxies:/{f=1;next} f&&/^[a-z]/{f=0} f&&/^  - name:/{c++} END{print c+0}' /usr/local/etc/mihomo/config.yaml)"
echo "rules 条数:     $(awk '/^rules:/{f=1;next} f&&/^[a-z]/{f=0} f&&/^  - /{c++} END{print c+0}' /usr/local/etc/mihomo/config.yaml)"
echo "中文注释保留:   $(grep -c '在调试结果后' /usr/local/etc/mihomo/config.yaml)"
echo "行数:           $(wc -l < /usr/local/etc/mihomo/config.yaml)"

echo
echo "=== 语法校验 ==="
/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f /usr/local/etc/mihomo/config.yaml 2>&1 | tail -2
