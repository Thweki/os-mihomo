#!/bin/sh
# Debug: compare what the remote copy of the staging script looks like.
set -u
echo "=== size / hash ==="
wc -c /tmp/__remote.sh
sha256 -q /tmp/__remote.sh
echo
echo "=== lines 54-62 with escapes ==="
awk 'NR>=54 && NR<=62' /tmp/__remote.sh | cat -v
echo
echo "=== sh -n ==="
sh -n /tmp/__remote.sh && echo "SYNTAX OK" || echo "SYNTAX BAD"
echo
echo "=== locale ==="
locale 2>/dev/null | head -3
echo "LANG=${LANG:-unset}"
echo
echo "=== which sh / dash? ==="
ls -l /bin/sh
