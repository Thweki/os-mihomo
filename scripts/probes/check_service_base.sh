#!/bin/sh
# 看 OPNsense 基类 ApiMutableServiceControllerBase 的 status/start 逻辑
set -u
F=$(find /usr/local/opnsense/mvc/app -name 'ApiMutableServiceControllerBase.php' 2>/dev/null | head -1)
echo "文件: $F"
echo
echo "=== statusAction / startAction / reconfigureAction === "
awk '/function startAction|function stopAction|function restartAction|function statusAction|function reconfigureAction/,/^    }/' "$F" | head -80

echo
echo "=== 与 internalServiceEnabled 相关的判断 ==="
grep -n 'internalServiceEnabled\|disabled\|isEnabled' "$F" | head -20
