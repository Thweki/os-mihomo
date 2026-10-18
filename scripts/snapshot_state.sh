#!/bin/sh
# os-mihomo —— 目标机状态指纹
#
# 用途：在部署前后各取一次，用来证明本插件没有触碰任何网络配置。
#
#   sh snapshot_state.sh [输出文件]
#
# 记录内容（全部只读）：
#   · /conf/config.xml 的 SHA256（防火墙/接口/DNS 等所有配置都在这里）
#   · 防火墙运行规则集 / NAT / 路由表 / 接口列表 的 SHA256
#   · Unbound 生效配置与转发设置的 SHA256
#   · 监听端口列表
#   · rc.conf.d/mihomo 内容
#   · 本插件管理的文件清单（路径 + 大小 + mtime）
set -u

OUT="${1:-}"

emit() {
    echo "### $1"
    shift
    "$@"
    echo
}

snapshot() {
    echo "== snapshot @ $(date '+%Y-%m-%d %H:%M:%S') =="
    echo "host: $(hostname) / $(opnsense-version 2>/dev/null)"

    echo
    echo "## 网络配置指纹（部署前后必须完全一致）"
    if [ -f /conf/config.xml ]; then
        printf 'config.xml            %s\n' "$(sha256 -q /conf/config.xml)"
    else
        printf 'config.xml            (missing)\n'
    fi
    printf 'pf rules              %s\n' "$(pfctl -sr 2>/dev/null | sha256 -q)"
    printf 'pf nat rules          %s\n' "$(pfctl -sn 2>/dev/null | sha256 -q)"
    printf 'routing table         %s\n' "$(netstat -rn 2>/dev/null | sha256 -q)"
    printf 'interfaces            %s\n' "$(ifconfig -a 2>/dev/null | sha256 -q)"
    printf 'unbound.conf          %s\n' "$(sha256 -q /var/unbound/unbound.conf 2>/dev/null || echo n/a)"
    printf 'unbound forward conf  %s\n' "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
    printf 'resolv.conf           %s\n' "$(sha256 -q /etc/resolv.conf 2>/dev/null || echo n/a)"

    echo
    echo "## config.xml 中与本插件相关的内容（应为空或仅系统项）"
    grep -n -i -E 'tun_mihomo|mihomo' /conf/config.xml 2>/dev/null | head -20 || echo "(none)"

    echo
    echo "## 监听端口"
    sockstat -4 -l 2>/dev/null | egrep ':53|:1053|:7891|:9090' || echo "(none matching)"

    echo
    echo "## TUN 接口"
    ifconfig tun_mihomo 2>&1 | head -3 || true

    echo
    echo "## 自启开关"
    if [ -f /etc/rc.conf.d/mihomo ]; then
        cat /etc/rc.conf.d/mihomo
    else
        echo "(missing)"
    fi

    echo
    echo "## 本插件管理的文件清单"
    for path in \
        /usr/local/bin/mihomo \
        /usr/local/etc/mihomo \
        /usr/local/etc/rc.d/mihomo \
        /usr/local/etc/inc/plugins.inc.d/mihomo.inc \
        /usr/local/etc/newsyslog.conf.d/mihomo.conf \
        /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo \
        /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo \
        /usr/local/opnsense/mvc/app/views/OPNsense/Mihomo \
        /usr/local/opnsense/scripts/mihomo \
        /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf \
        /usr/local/opnsense/version/mihomo \
        /usr/local/www/mihomo.php \
        /usr/bin/mihomo_sub ; do
        if [ -e "$path" ]; then
            find "$path" -type f -exec ls -la {} \; 2>/dev/null
        else
            echo "MISSING $path"
        fi
    done
}

if [ -n "$OUT" ]; then
    snapshot > "$OUT"
    echo "written: $OUT"
else
    snapshot
fi
