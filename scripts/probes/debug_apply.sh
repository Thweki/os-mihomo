#!/bin/sh
set -u
echo "=== configd 日志中的脚本 stderr ==="
grep -i 'mihomo' /var/log/configd.log 2>/dev/null | tail -20
echo "--- system log ---"
grep -i 'Script action stderr' /var/log/system/latest.log 2>/dev/null | tail -5
grep -i 'mihomo' /var/log/system/latest.log 2>/dev/null | tail -10
echo
echo "=== 手动制造一个 staging 文件并直接调用脚本 ==="
F=$(mktemp /tmp/mihomo-XXXXXX)
echo "staging: $F  owner=$(stat -f '%Su' "$F")  mode=$(stat -f '%Lp' "$F")"
cp /usr/local/etc/mihomo/config.yaml "$F"
chmod 0600 "$F"
echo "--- 直接跑脚本 install ---"
/usr/local/bin/php /usr/local/opnsense/scripts/mihomo/config_apply.php install "$F"
echo "(exit=$?)"
echo
echo "=== 通过 configd 调用（新 staging 文件）==="
F2=$(mktemp /tmp/mihomo-XXXXXX)
cp /usr/local/etc/mihomo/config.yaml "$F2"
chmod 0600 "$F2"
chown nobody "$F2" 2>/dev/null || true
ls -la "$F2"
configctl mihomo config-install "$F2"
echo "(exit=$?)"
echo
echo "=== 路径正则自测 ==="
/usr/local/bin/php -r 'var_dump(preg_match("@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@", "/tmp/mihomo-Ab3xY9"), preg_match("@^/tmp/mihomo-[A-Za-z0-9.]{6,}$@", "/tmp/mihomo-Xy12Z9"));'
echo "--- 真实 tempnam 产物形态 ---"
/usr/local/bin/php -r '$p=tempnam("/tmp","mihomo-"); echo $p, " owner_uid=", fileowner($p), " mode=", substr(sprintf("%o", fileperms($p)), -4), PHP_EOL; unlink($p);'
