#!/bin/sh
set -u
echo "=== lighttpd 进程属主 ==="
ps -ax -o pid,user,command 2>/dev/null | grep '[l]ighttpd' | head -5
echo
echo "=== PHP 进程（全部形态）==="
ps -ax -o pid,user,command 2>/dev/null | grep -E '[p]hp' | head -10
echo
echo "=== lighttpd 配置里的用户/组 ==="
grep -nE 'server.username|server.groupname|user|group' /usr/local/etc/lighttpd_webgui/lighttpd.conf | head -10
grep -rn 'server.username\|server.groupname' /usr/local/etc/lighttpd_webgui/conf.d/*.conf 2>/dev/null | head -5
echo
echo "=== php-fpm 池配置（WebGUI 用哪个）==="
ls -la /usr/local/etc/php-fpm.d/
grep -nE '^\s*(user|group|listen)\s*=' /usr/local/etc/php-fpm.d/*.conf 2>/dev/null | head -10
echo
echo "=== 实测：Web 进程创建的文件属主与 umask ==="
/usr/local/bin/php -r '$p = tempnam("/tmp", "whoami-"); echo "file=$p owner_uid=" . fileowner($p) . " mode=" . substr(sprintf("%o", fileperms($p)), -4) . "\n"; echo "php getmyuid=" . getmyuid() . " posix=" . (function_exists("posix_geteuid") ? posix_geteuid() : "n/a") . "\n"; unlink($p);'
echo
echo "=== 通过 HTTP 触发同样的调用（用 WebUI 自身来证明）==="
echo "--- 用 configd 跑同一段（root 视角）---"
configctl mihomo log-tail mihomo 1 >/dev/null 2>&1 && echo "configd OK"
echo
echo "=== lighttpd 是否 root 启动后 drop 权限？看 /usr/local/www/index.php 里的调用者 ==="
grep -rn 'posix_geteuid\|getmyuid\|whoami' /usr/local/opnsense/mvc/app/controllers/OPNsense/Core/Api/*.php 2>/dev/null | head -3
