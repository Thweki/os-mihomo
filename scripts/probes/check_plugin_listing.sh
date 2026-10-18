#!/bin/sh
# 取证 5：插件页面枚举插件的确切逻辑
set -u
F=/usr/local/opnsense/mvc/app/models/OPNsense/Core/Firmware.php
echo "=== Firmware.php 中与 plugins 相关的函数 ==="
awk '/function [a-zA-Z]*[Pp]lugin/,/^    }/' "$F" | head -60
echo
echo "=== 搜索 plugins/repositories 相关调用 ==="
grep -n 'plugins\|repositories\|configd' "$F" | head -30
echo
echo "=== 仓库注册文件（repositories/*.xml）==="
ls -la /usr/local/opnsense/mvc/app/models/OPNsense/Core/repositories/ 2>/dev/null
for f in /usr/local/opnsense/mvc/app/models/OPNsense/Core/repositories/*.xml; do
    [ -f "$f" ] || continue
    echo "--- $f ---"; cat "$f"
done
