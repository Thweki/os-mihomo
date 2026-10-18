#!/bin/sh
# 查看各备份集覆盖的路径与文件数
set -u
BAK_ROOT=/usr/local/opnsense/_bak/os-mihomo

for d in "$BAK_ROOT"/*/; do
    echo "=== $d ==="
    if [ -d "$d/usr" ] || [ -d "$d/etc" ]; then
        find "$d" -type f 2>/dev/null | sed "s#^$d##" | sort | head -8
        echo "  ... 共 $(find "$d" -type f 2>/dev/null | wc -l) 个文件"
        echo "  config.xml: $([ -f "$d/config.xml" ] && echo yes || echo no)"
        echo "  快照文件   : $([ -f "$d/pre-deploy-snapshot.txt" ] && echo yes || echo no)"
    else
        echo "  (空备份集)"
    fi
    echo
done
