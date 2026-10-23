#!/bin/sh
# os-mihomo —— 订阅更新执行器（由 configd 以 root 身份调用）
#
# 用法: subscription_run.sh <yes|no>
#   yes -> 订阅成功后重启 mihomo 服务（危险：会按新配置重建 TUN/路由）
#   no  -> 只生成配置，不触碰运行中的服务（默认，安全）
#
# 之所以默认不重启：上游 sub.sh 结尾写死 `service mihomo restart`，
# 在未确认节点可用时自动重启可能让整网流量进入无效 TUN 路由。
set -u

LOG=/var/log/mihomo_sub.log
SCRIPT=/usr/local/etc/mihomo/sub/sub.sh
PIDFILE=/var/run/mihomo-sub-ui.pid

case "${1:-no}" in
    yes|1|true|YES|on)  SERVICE_CMD="service mihomo restart" ;;
    *)                  SERVICE_CMD="/usr/bin/true" ;;
esac

touch "$LOG" 2>/dev/null || true
chmod 0640 "$LOG" 2>/dev/null || true

now() { date '+%Y-%m-%d %H:%M:%S'; }

printf '[%s] Subscription task submitted (restart service after update: %s).\n' \
    "$(now)" "$( [ "$SERVICE_CMD" = "/usr/bin/true" ] && echo no || echo yes )" >> "$LOG"

if [ ! -f "$SCRIPT" ]; then
    printf '[%s] Subscription script is missing: %s\n' "$(now)" "$SCRIPT" >> "$LOG"
    exit 1
fi

/usr/sbin/daemon -p "$PIDFILE" /bin/sh -c '
    MIHOMO_SERVICE_CMD="'"$SERVICE_CMD"'" /bin/sh '"$SCRIPT"' >> '"$LOG"' 2>&1
    rc=$?
    printf "[%s] Subscription task finished (exit=%s).\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$rc" >> '"$LOG"'
'

echo "Subscription task submitted; follow the log for progress."
