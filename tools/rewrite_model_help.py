#!/usr/bin/env python3
"""把模型里的校验提示与视图里的长说明改成短句"""
import io
import re
from pathlib import Path

model = Path('src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Mihomo.xml')
text = io.open(model, encoding='utf-8').read()

val = {
    'Enable the mihomo service at boot time.': 'Start the service at boot.',
    'Enter an IP address, e.g. 127.0.0.1 (loopback only, recommended) or 0.0.0.0 (all interfaces).':
        'Enter an IP address, e.g. 127.0.0.1 or 0.0.0.0.',
    'Use up to 128 characters: letters, digits, ".", "-" and "_".':
        'Up to 128 characters: letters, digits, ".", "-" and "_".',
    'Interface name is limited to 15 characters (letters, digits, underscore).':
        'Up to 15 characters: letters, digits, underscore.',
    'Enter a listen address including port, e.g. 127.0.0.1:1053.':
        'Enter address and port, e.g. 127.0.0.1:1053.',
    'Enter an http(s) subscription URL, or leave empty.': 'Enter an http(s) URL, or leave empty.',
    'Restart mihomo right after a successful subscription update.': 'Restart the service after a successful update.',
    'Pick an interface, e.g. lan or opt2.': 'Pick an interface, e.g. lan or opt2.',
    'Optional. Leave empty to use the interface network, or enter a CIDR like 192.168.1.0/24.':
        'Optional. Empty uses the interface network.',
    'Proxy group name, e.g. 🇺🇸United States. Ignored when the scope is "direct".':
        'Proxy group name.',
}
for old, new in val.items():
    if old != new and old in text:
        text = text.replace(old, new)
io.open(model, 'w', encoding='utf-8', newline='\n').write(text)
print('model 已更新')

view = Path('src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt')
vtext = io.open(view, encoding='utf-8').read()
long_strings = re.findall(r"lang\._\('([^']{60,})'\)", vtext)
for item in long_strings:
    print('view 长句:', item[:120])
