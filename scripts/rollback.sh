#!/bin/sh
# Restore a UI-only deployment. No configuration or service state is restored.
set -eu
backup=${1:?Usage: rollback.sh /usr/local/opnsense/_bak/os-mihomo/TIMESTAMP}
case "$backup" in /usr/local/opnsense/_bak/os-mihomo/[0-9]*_[0-9]*) ;; *) echo 'Invalid backup path' >&2; exit 2 ;; esac
[ -f "$backup/ui-files.txt" ] && [ -f "$backup/ui-existing.txt" ] || exit 2
# Validate every destination before the first write.
while IFS= read -r rel; do
    case "$rel" in *..*|/*) exit 2 ;; esac
    case "$rel" in
        usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/*|usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/*|usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/*|usr/local/www/js/mihomo/*|usr/local/opnsense/scripts/mihomo/runtime_status.php|usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf) ;;
        *) exit 2 ;;
    esac
    if grep -Fxq "$rel" "$backup/ui-existing.txt"; then [ -f "$backup/files/$rel" ] || exit 2; fi
done < "$backup/ui-files.txt"
while IFS= read -r rel; do
    if grep -Fxq "$rel" "$backup/ui-existing.txt"; then cp -p "$backup/files/$rel" "/$rel"; else rm -f "/$rel"; fi
done < "$backup/ui-files.txt"
if grep -Fxq usr/local/opnsense/service/conf/actions.d/actions_mihomo.conf "$backup/ui-files.txt"; then
    service configd restart >/dev/null
fi
echo 'UI files restored; network configuration and Mihomo state unchanged.'
