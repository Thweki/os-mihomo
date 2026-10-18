#!/bin/sh
# 弄清两件事：Volt 编译缓存如何处理 lang._()，以及 WebGUI 正确的重启方式
set -u

echo "=== 1. Mihomo 视图的 Volt 编译缓存 ==="
ls -la /var/lib/php/cache/ 2>/dev/null | grep -i mihomo

echo
echo "=== 2. 取一个编译后的视图，看 lang._ 是怎么编译的 ==="
F=$(ls -1 /var/lib/php/cache/*Mihomo*index* 2>/dev/null | head -1)
if [ -n "$F" ]; then
    echo "file: $F"
    grep -n "translator\|_(" "$F" | head -12
else
    echo "(未找到编译缓存文件，可能缓存在别处)"
    ls -la /var/lib/php/cache/ | head -20
fi

echo
echo "=== 3. webgui 的 configd 动作 ==="
cat /usr/local/opnsense/service/conf/actions.d/actions_webgui.conf 2>/dev/null

echo
echo "=== 4. php-cgi 的父进程 ==="
for pid in $(ps -ax -o pid,command 2>/dev/null | awk '/[p]hp-cgi/{print $1}' | head -3); do
    printf '  php-cgi %s -> ppid %s\n' "$pid" "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
done
echo "--- lighttpd 进程 ---"
ps -ax -o pid,ppid,etime,command 2>/dev/null | grep '[l]ighttpd'

echo
echo "=== 5. php-cgi 是从哪启动的（lighttpd fastcgi 配置）==="
grep -rn 'bin-path\|php-cgi\|fastcgi.server' /usr/local/etc/lighttpd_webgui/lighttpd.conf /usr/local/etc/lighttpd_webgui/conf.d/*.conf 2>/dev/null | head -10
