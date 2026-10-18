#!/bin/sh
# 证明「写模型」只影响 <OPNsense><mihomo> 节点
set -u

BAK=/usr/local/opnsense/_bak/os-mihomo
LATEST=$(ls -1d "$BAK"/* 2>/dev/null | tail -1)
echo "backup set: $LATEST"

pre=""
[ -f "$LATEST/config.xml" ] && pre="$LATEST/config.xml"
[ -f /tmp/pre-deploy-config.xml ] && pre=/tmp/pre-deploy-config.xml

echo
echo "=== 当前 config.xml 中 mihomo 节点 ==="
python3 - <<'PY'
import xml.etree.ElementTree as ET
t = ET.parse('/conf/config.xml')
r = t.getroot()
node = r.find('OPNsense/mihomo')
if node is None:
    print("(no <OPNsense><mihomo> node)")
else:
    ET.dump(node)
PY

echo
echo "=== 与部署前备份做结构化 diff（忽略 mihomo 节点）==="
python3 - "$pre" <<'PY'
import sys, xml.etree.ElementTree as ET

def flatten(node, path=""):
    out = {}
    for child in node:
        p = f"{path}/{child.tag}"
        text = (child.text or "").strip()
        if len(child) == 0:
            out[p] = text
        else:
            out.update(flatten(child, p))
    return out

def strip_mihomo(root):
    # 返回去掉 OPNsense/mihomo 之后的规范化文本
    import copy
    r = copy.deepcopy(root)
    p = r.find('OPNsense')
    if p is not None:
        m = p.find('mihomo')
        if m is not None:
            p.remove(m)
    return ET.tostring(r, encoding='utf-8').decode()

pre = sys.argv[1]
if not pre:
    print("(no pre-deploy config.xml backup found; nothing to compare)")
    sys.exit(0)

old = ET.parse(pre).getroot()
new = ET.parse('/conf/config.xml').getroot()

a = strip_mihomo(old)
b = strip_mihomo(new)
print("config.xml 去掉 mihomo 节点后完全相同:", a == b)
if a != b:
    fa, fb = flatten(old), flatten(new)
    keys = sorted(set(fa) | set(fb))
    diffs = [(k, fa.get(k), fb.get(k)) for k in keys if fa.get(k) != fb.get(k)]
    print("差异条目数:", len(diffs))
    for k, v1, v2 in diffs[:40]:
        print(f"  {k}\n    before: {v1}\n    after : {v2}")
PY

echo
echo "=== 无关网络配置的指纹复核 ==="
printf 'pf rules     %s\n' "$(pfctl -sr 2>/dev/null | sha256 -q)"
printf 'pf nat       %s\n' "$(pfctl -sn 2>/dev/null | sha256 -q)"
printf 'routes       %s\n' "$(netstat -rn 2>/dev/null | sha256 -q)"
printf 'ifconfig     %s\n' "$(ifconfig -a 2>/dev/null | sha256 -q)"
printf 'unbound conf %s\n' "$(find /var/unbound -name '*.conf' -exec cat {} \; 2>/dev/null | sha256 -q)"
