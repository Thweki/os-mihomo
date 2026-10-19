#!/bin/sh
# os-mihomo —— 安全部署脚本（在目标机以 root 运行）
#
# 前提：源码已由 tools/deploy.ps1 通过 scp 暂存到 /tmp/mihomo-stage/src
#
# 本脚本严格遵守 AGENTS.md 的红线：
#   · 不执行上游 packaging/freebsd/+POST_INSTALL（不改 config.xml / 防火墙 / Unbound）
#   · 不 enable 服务（首装写 mihomo_enable="NO"）
#   · 不产生任何路由/TUN/DNS 变更
#   · 只写：/usr/local/opnsense/mvc/**, /usr/local/etc/mihomo/**, /usr/local/www/mihomo*.php,
#           /usr/local/etc/rc.d/mihomo, /usr/local/opnsense/scripts/mihomo/**,
#           /usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf,
#           /usr/local/opnsense/version/mihomo, /usr/local/etc/inc/plugins.inc.d/mihomo.inc,
#           /usr/local/etc/newsyslog.conf.d/mihomo.conf, /usr/bin/mihomo_sub
set -eu

STAGE=/tmp/mihomo-stage/src
BAK_ROOT=/usr/local/opnsense/_bak/os-mihomo
TS=$(date '+%Y%m%d_%H%M%S')
BAK="$BAK_ROOT/$TS"

log() { printf '%s\n' "$*"; }

[ -d "$STAGE" ] || { echo "staging tree missing: $STAGE" >&2; exit 2; }

log "=== os-mihomo deploy @ $TS ==="

# ---------------------------------------------------------------- 0. 净化
# 去掉可能混入的 BOM 与 CRLF（本地已做一次，这里兜底）
find "$STAGE" -type f \( -name '*.php' -o -name '*.sh' -o -name '*.conf' -o -name '*.xml' -o -name '*.yaml' \) -exec \
    sed -i '' -e '1s/^\xef\xbb\xbf//' {} \; 2>/dev/null || true

# ---------------------------------------------------------------- 1. 备份
mkdir -p "$BAK"
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
    /usr/bin/mihomo_sub \
    /usr/local/www/mihomo.php \
    /usr/local/www/mihomo_sub.php \
    /usr/local/www/mihomo_logs.php \
    /usr/local/www/mihomo_sub_log.php \
    /etc/rc.conf.d/mihomo \
    /conf/config.xml ; do
    if [ -e "$path" ]; then
        mkdir -p "$BAK$(dirname "$path")"
        cp -a "$path" "$BAK$path" 2>/dev/null || true
    fi
done
cp -a /conf/config.xml "$BAK/config.xml" 2>/dev/null || true
sh /usr/local/opnsense/scripts/mihomo/snapshot_state.sh "$BAK/pre-deploy-snapshot.txt" 2>/dev/null || \
    echo "(pre-deploy snapshot skipped: script not installed yet)"
log "backup: $BAK"

# ---------------------------------------------------------------- 2. 安装文件
install_file() {
    src="$1"; dst="$2"; mode="$3"
    mkdir -p "$(dirname "$dst")"
    /usr/bin/install -m "$mode" -o root -g wheel "$src" "$dst"
}

# 2.1 PHP / 网页
for rel in \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.xml \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Controller.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Inspector.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Logs.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/RequestParamsTrait.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Safety.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Subscription.php \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/ACL/ACL.xml \
    usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Menu/Menu.xml \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/IndexController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/SettingsController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/SubscriptionController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/LogController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/RoutingController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/policy_rule.xml \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/DashboardController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/ServiceController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SettingsController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/SubscriptionController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/LogController.php \
    usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/Api/RoutingController.php \
    usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/index.volt \
    usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt \
    usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/subscription.volt \
    usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/log.volt \
    usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/routing.volt \
    usr/local/www/mihomo.php \
    usr/local/www/mihomo_sub.php \
    usr/local/www/mihomo_logs.php \
    usr/local/www/mihomo_sub_log.php \
    usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf \
    usr/local/opnsense/version/mihomo \
    usr/local/etc/inc/plugins.inc.d/mihomo.inc \
    usr/local/etc/newsyslog.conf.d/mihomo.conf ; do
    if [ -f "$STAGE/$rel" ]; then
        install_file "$STAGE/$rel" "/$rel" 0644
    else
        log "  (skip, not in tree) $rel"
    fi
done

# 2.2 可执行脚本
for rel in \
    usr/local/opnsense/scripts/mihomo/config_apply.php \
    usr/local/opnsense/scripts/mihomo/env.php \
    usr/local/opnsense/scripts/mihomo/logclear.php \
    usr/local/opnsense/scripts/mihomo/logtail.php \
    usr/local/opnsense/scripts/mihomo/service_enable.php \
    usr/local/opnsense/scripts/mihomo/setup_unbound.php \
    usr/local/opnsense/scripts/mihomo/subscription_run.sh \
    usr/local/opnsense/scripts/mihomo/policy_net.php \
    usr/local/opnsense/scripts/mihomo/selftest.php \
    usr/local/opnsense/scripts/mihomo/policy_apply.php \
    usr/local/etc/rc.d/mihomo \
    usr/bin/mihomo_sub \
    usr/local/etc/mihomo/sub/sub.sh ; do
    if [ -f "$STAGE/$rel" ]; then
        install_file "$STAGE/$rel" "/$rel" 0755
    fi
done

# 2.3 配置文件（仅在不存在时安装，避免覆盖用户配置）
if [ ! -f /usr/local/etc/mihomo/config.yaml ] && [ -f "$STAGE/usr/local/etc/mihomo/config.yaml" ]; then
    install_file "$STAGE/usr/local/etc/mihomo/config.yaml" /usr/local/etc/mihomo/config.yaml 0644
    log "  installed default config.yaml"
elif [ -f "$STAGE/usr/local/etc/mihomo/config.yaml" ]; then
    log "  kept existing config.yaml (not overwritten)"
fi

if [ ! -f /usr/local/etc/mihomo/sub/template_config.yaml ] && [ -f "$STAGE/usr/local/etc/mihomo/sub/template_config.yaml" ]; then
    install_file "$STAGE/usr/local/etc/mihomo/sub/template_config.yaml" /usr/local/etc/mihomo/sub/template_config.yaml 0600
fi

if [ ! -f /usr/local/etc/mihomo/sub/env ] && [ -f "$STAGE/usr/local/etc/mihomo/sub/env" ]; then
    install_file "$STAGE/usr/local/etc/mihomo/sub/env" /usr/local/etc/mihomo/sub/env 0600
fi

for geo in GeoIP.dat GeoSite.dat; do
    if [ ! -f "/usr/local/etc/mihomo/$geo" ] && [ -f "$STAGE/usr/local/etc/mihomo/$geo" ]; then
        install_file "$STAGE/usr/local/etc/mihomo/$geo" "/usr/local/etc/mihomo/$geo" 0644
    fi
done

# 2.4 内核（可选：--with-binary 时安装）
if [ "${1:-}" = "--with-binary" ] && [ -f "$STAGE/usr/local/bin/clash-meta-freebsd-amd64.xz" ]; then
    if [ ! -f /usr/local/bin/mihomo ]; then
        log "  unpacking mihomo core"
        xz -dc "$STAGE/usr/local/bin/clash-meta-freebsd-amd64.xz" > /usr/local/bin/mihomo
        chmod 0755 /usr/local/bin/mihomo
        chown root:wheel /usr/local/bin/mihomo
    fi
fi

# 2.5 服务默认不 enable（安全默认）
if [ ! -f /etc/rc.conf.d/mihomo ]; then
    printf 'mihomo_enable="NO"\n' > /etc/rc.conf.d/mihomo
    chmod 0644 /etc/rc.conf.d/mihomo
    chown root:wheel /etc/rc.conf.d/mihomo
    log "  created /etc/rc.conf.d/mihomo (mihomo_enable=NO)"
fi

chmod 0644 /usr/local/etc/mihomo/config.yaml 2>/dev/null || true
chmod 0755 /usr/local/etc/mihomo/sub/sub.sh 2>/dev/null || true
mkdir -p /usr/local/etc/mihomo/sub/temp

# ---------------------------------------------------------------- 3. 语法检查
log "== php -l =="
PHP_ERRORS=0
PHP_FILES="$(find /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo \
                  /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo \
                  /usr/local/opnsense/scripts/mihomo -name '*.php' 2>/dev/null | sort -u)
$(ls /usr/local/www/mihomo*.php 2>/dev/null)"
for f in $PHP_FILES; do
    if ! out=$(php -l "$f" 2>&1); then
        echo "SYNTAX ERROR: $f"
        echo "$out"
        PHP_ERRORS=$((PHP_ERRORS + 1))
    fi
done
log "  php files checked: $(printf '%s\n' $PHP_FILES | grep -c . ) / syntax errors: $PHP_ERRORS"

log "== sh -n =="
for f in /usr/local/opnsense/scripts/mihomo/*.sh /usr/local/etc/rc.d/mihomo /usr/bin/mihomo_sub; do
    sh -n "$f" 2>&1 && true || echo "SYNTAX ERROR: $f"
done

# ---------------------------------------------------------------- 4. 缓存与后端
rm -f /var/lib/php/tmp/opnsense_menu_cache.xml /var/lib/php/tmp/opnsense_acl_cache.json
rm -f /var/lib/php/tmp/mdl_cache_OPNsense_Mihomo*.json
log "  cleared menu/ACL/model caches"

if command -v configctl >/dev/null 2>&1; then
    # 必须用 rc.d 重启：`configctl configd restart` 不会重新加载 actions.d
    service configd restart >/dev/null 2>&1 || true
    log "  configd restarted (to register new actions)"
fi
skip_count=$(configctl configd actions 2>/dev/null | grep -c '^mihomo ' || true)
log "  registered mihomo actions: $skip_count (expected 21)"

log "== installed file inventory =="
find /usr/local/opnsense/mvc/app/models/OPNsense/Mihomo \
     /usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo \
     /usr/local/opnsense/mvc/app/views/OPNsense/Mihomo \
     /usr/local/opnsense/scripts/mihomo -type f | sort

log "=== deploy done (backup: $BAK) ==="
