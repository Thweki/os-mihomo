#!/bin/sh

PASS="${OPN_PW:-${1:-}}"
if [ -z "$PASS" ]; then echo "缺少 WebGUI 口令：export OPN_PW=... 或 tools/remote.ps1 -ScriptArgs '<口令>'"; exit 2; fi
export OPN_PW="${PASS}"
# 确认 .mo 路径与已装翻译、以及空状态提示在页面里的最终文本
set -u
BASE=https://127.0.0.1
JAR=/tmp/p24_jar.txt
rm -f "$JAR"

echo "########## 1. 已安装的中文语言包位置 ##########"
find /usr/local/share /usr/share -name 'OPNsense.mo' -path '*zh_CN*' 2>/dev/null | sed 's/^/  /'

LP=$(curl -sk -c "$JAR" "$BASE/index.php")
N=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\1/p' | head -1)
V=$(printf '%s' "$LP" | sed -n 's/.*<input type="hidden" name="\([^"]*\)" value="\([^"]*\)".*/\2/p' | head -1)
curl -sk -b "$JAR" -c "$JAR" -o /dev/null -d "login=1&usernamefld=root&passwordfld=$PASS&$N=$V" "$BASE/index.php"
curl -sk -b "$JAR" "$BASE/ui/mihomo/routing" -o /tmp/p24-routing.html

echo
echo "########## 2. 空状态提示的实际文本 ##########"
python3 - <<'PY'
import re
t = open('/tmp/p24-routing.html', encoding='utf-8').read()
m = re.search(r'<div id="policyEmptyHint".{0,400}?</div>', t, re.S)
print('  ' + (re.sub(r'\s+', ' ', m.group(0)) if m else '(没找到 hint 容器)'))
PY

echo
echo "########## 3. .mo 里的新词条 ##########"
python3 - <<'PY'
import glob
for p in glob.glob('/usr/local/share/**/zh_CN/**/OPNsense.mo', recursive=True) + glob.glob('/usr/share/**/zh_CN/**/OPNsense.mo', recursive=True):
    data = open(p, 'rb').read()
    hit = [kw for kw in ('还没有绑定接口', '启动服务前请先修正以下问题', '启动服务前请先确认以下事项', '外部控制器未设置密钥（仅监听本机）') if kw.encode('utf-8') in data]
    print('  %-70s %d 项命中: %s' % (p, len(hit), hit))
PY

echo
echo "########## 4. 首页体检（横幅是否会出现） ##########"
curl -sk -b "$JAR" "$BASE/api/mihomo/service/safety" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  status:', d.get('status'), '（info = 横幅整块不显示）')
"
rm -f "$JAR"
