#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
set -u
BASE=https://127.0.0.1
JAR=/tmp/p58_jar.txt
rm -f "$JAR"
LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/ui/mihomo/settings" -o /tmp/p58.html
python3 - <<'PY'
import io, re
t = io.open('/tmp/p58.html', encoding='utf-8', errors='replace').read()
print('页面字节:', len(t))
print('mihomo. 形式的 id 数量:', len(re.findall(r'id="mihomo\.', t)))
ids = re.findall(r'id="(mihomo\.[^"]*)"', t)
print('前 8 个 id:', ids[:8])
print('form id:', re.findall(r'<form id="([^"]+)"', t))
print('control_label 数量:', len(re.findall(r'id="control_label_', t)))
print('PHP 报错/警告:', [w for w in ('Fatal error', 'Warning:', 'Notice:', 'Deprecated:') if w in t])
i = t.find('<form id="frm_Settings"')
print('---- 表单开头 900 字节 ----')
print(t[i:i+900] if i > 0 else '(没找到 frm_Settings)')
PY
