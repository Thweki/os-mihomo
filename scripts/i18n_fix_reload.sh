#!/bin/sh
# 1) 清理误启动的 lighttpd 实例
# 2) 查看 Volt 编译缓存里 lang._ 的形态
# 3) 用正确方式重启 WebGUI
set -u

echo "=== 1. 误启动的实例（/usr/local/etc/lighttpd/lighttpd.conf）==="
ps -ax -o pid,etime,command 2>/dev/null | grep '[l]ighttpd' 
echo "--- 它的监听端口 ---"
sockstat -4 -l 2>/dev/null | grep lighttpd || echo "(无监听，或已被占用而未绑定)"
echo "--- 停止它（只停 config 指向 /etc/lighttpd/ 的那个）---"
for pid in $(ps -ax -o pid,command 2>/dev/null | awk '/[l]ighttpd/ && /etc\/lighttpd\/lighttpd.conf/ {print $1}'); do
    echo "  kill $pid"
    kill "$pid" 2>/dev/null || true
done
sleep 2
ps -ax -o pid,command 2>/dev/null | grep '[l]ighttpd'

echo
echo "=== 2. 编译缓存里的 lang._（看是否编译期翻译）==="
F=/var/lib/php/cache/_usr_local_opnsense_mvc_app_views_opnsense_mihomo_subscription.volt.php
ls -la "$F"
grep -o "lang\._([^)]*)\|translator[^;]*" "$F" | head -8

echo
echo "=== 3. 正确重启 WebGUI ==="
/usr/local/etc/rc.restart_webgui 2>&1 | head -5
sleep 4
curl -sk -o /dev/null -w 'webgui: %{http_code}\n' https://127.0.0.1/
echo "--- 新的 php-cgi（etime 应很短）---"
ps -ax -o pid,etime,command 2>/dev/null | grep '[p]hp-cgi' | head -5
