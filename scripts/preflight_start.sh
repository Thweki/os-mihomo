#!/bin/sh
# 启动前安全检查：如果现在启动 mihomo，会碰网络吗？
set -u
C=/usr/local/etc/mihomo/config.yaml

echo "########## 1. 端口与内核监听 ##########"
grep -nE '^(port|socks-port|redir-port|tproxy-port|mixed-port|allow-lan|bind-address|external-controller|secret):' "$C"

echo
echo "########## 2. TUN 段 ##########"
sed -n '/^tun:/,/^[a-z]/p' "$C" | head -20

echo
echo "########## 3. DNS 段 ##########"
sed -n '/^dns:/,/^[a-z]/p' "$C" | head -28

echo
echo "########## 4. 有没有会碰网络的开关 ##########"
for k in 'dns-hijack' 'auto-redirect' 'auto-detect-interface' 'route-address' 'redirect-to-tun'; do
    printf '  %-24s %s\n' "$k" "$(grep -n "$k" "$C" | head -2 | tr '\n' ' ')"
done

echo
echo "########## 5. 订阅环境文件 ##########"
echo "--- 文件与权限 ---"
ls -la /usr/local/etc/mihomo/sub/env
echo "--- 内容（值用长度代替）---"
sed -e 's/\(=.\{0,3\}\).*/\1***/' /usr/local/etc/mihomo/sub/env 2>/dev/null | head -12

echo
echo "########## 6. 代理节点（前几个名字与服务器） ##########"
grep -nE '^\s+-\s+\{?\s*name:|^\s+server:' "$C" | head -12
echo "--- 占位节点检查 ---"
grep -c '88\.88\.88\.88' "$C"
