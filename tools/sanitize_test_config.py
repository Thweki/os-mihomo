#!/usr/bin/env python3
"""
把 tests/config.yaml 脱敏成可安全跑在路由器上的版本：
  · bind-address: '*' → 127.0.0.1      （只监听回环，不在 LAN 上开代理端口）
  · 其余原样保留（allow-lan / dns.listen / external-controller 稍后由插件的「应用」统一写入受管键）
输出：/tmp/mihomo-test/config-sanitized.yaml（本机）
"""
import io
import re
import sys
from pathlib import Path

src = Path('tests/config.yaml')
dst = Path(sys.argv[1] if len(sys.argv) > 1 else 'logs/config-sanitized.yaml')
dst.parent.mkdir(parents=True, exist_ok=True)

text = io.open(src, encoding='utf-8').read()
before = text

text = re.sub(r"^bind-address:.*$", "bind-address: 127.0.0.1", text, flags=re.M)
text = re.sub(r"^allow-lan:.*$", "allow-lan: false", text, flags=re.M)
text = re.sub(r"^(\s+listen:\s*)'?0\.0\.0\.0:1053'?", r"\g<1>'127.0.0.1:1053'", text, flags=re.M)
text = re.sub(r"^external-controller:.*$", "external-controller: 127.0.0.1:9090", text, flags=re.M) if re.search(r"^external-controller:", text, re.M) else text

dst.write_text(text, encoding='utf-8', newline='\n')

print('脱敏写入:', dst)
print('  bind-address :', re.findall(r'^bind-address:.*', text, re.M))
print('  allow-lan    :', re.findall(r'^allow-lan:.*', text, re.M))
print('  dns.listen   :', re.findall(r'^\s+listen:.*', text, re.M))
print('  mixed-port   :', re.findall(r'^mixed-port:.*', text, re.M))
print('  改动行数     :', sum(1 for a, b in zip(before.splitlines(), text.splitlines()) if a != b))
