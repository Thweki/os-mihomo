#!/bin/sh
# 取证：OPNsense 自带插件管理器管理的插件包长什么样
set -u

echo "########## 1. 已安装的 os-* 包 ##########"
pkg info -a 2>/dev/null | grep -E '^os-' || echo "(无)"
echo "--- /var/db/pkg 下的 os-* 目录 ---"
ls -1 /var/db/pkg/ 2>/dev/null | grep '^os-' || echo "(无)"

echo
echo "########## 2. 一个真实插件的 +MANIFEST 全文 ##########"
M=$(ls -d /var/db/pkg/os-ddns-go-* 2>/dev/null | head -1)
if [ -n "$M" ]; then
    echo "=== $M/+MANIFEST ==="
    cat "$M/+MANIFEST"
else
    echo "(未找到 os-ddns-go)"
fi

echo
echo "########## 3. 该插件安装的文件清单（看目录约定） ##########"
if [ -n "$M" ]; then
    sed -n '/^files:/,/^[a-z]/p' "$M/+MANIFEST" | head -40
fi

echo
echo "########## 4. 版本文件约定 ##########"
ls -la /usr/local/opnsense/version/ 2>/dev/null | head -20
echo "--- os-ddns-go 的版本文件 ---"
cat /usr/local/opnsense/version/os-ddns-go 2>/dev/null || echo "(无)"

echo
echo "########## 5. pkg 仓库与签名配置 ##########"
echo "--- /usr/local/etc/pkg.conf（关键项）---"
grep -vE '^\s*#|^\s*$' /usr/local/etc/pkg.conf 2>/dev/null | head -20
echo "--- 仓库配置 ---"
ls -1 /usr/local/etc/pkg/repos/ 2>/dev/null
for f in /usr/local/etc/pkg/repos/*.conf; do
    [ -f "$f" ] || continue
    echo "=== $f ==="
    grep -vE '^\s*#' "$f" | head -20
done
echo "--- 信任的签名密钥 ---"
ls -1 /usr/share/keys/pkg/trusted/ 2>/dev/null | head
ls -1 /usr/local/etc/pkg/keys/ 2>/dev/null | head

echo
echo "########## 6. 插件页面是怎么枚举插件的 ##########"
grep -rn "os-" /usr/local/opnsense/scripts/firmware/*.sh 2>/dev/null | head -10
ls -1 /usr/local/opnsense/scripts/firmware/ 2>/dev/null | head -20
