#!/usr/bin/env python3
"""把 settings.xml 的帮助文本与校验提示改成短句（OPNsense 风格）"""
import io
import re

path = 'src/usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml'
text = io.open(path, encoding='utf-8').read()

# (label, 新 help) —— 用 <label> 定位，替换其后第一个 <help>…</help>
repl = {
    'Enable mihomo': 'Start the service at boot.',
    'Log Level': 'Log verbosity. Use error or silent for long term operation.',
    'Mode': 'rule: follow the routing rules. global: everything through the selected proxy. direct: no proxy.',
    'Allow LAN': 'Let local clients use the proxy ports directly.',
    'Bind Address': 'Controller listen address. Keep 127.0.0.1 unless you really need remote access.',
    'Port': 'Controller port.',
    'Secret': 'Controller API secret.',
    'TUN Mode': 'Route traffic into mihomo through a virtual device.',
    'Device Name': 'Device name, must match the firewall rules (default tun_mihomo).',
    'Stack': 'gvisor is recommended on FreeBSD.',
    'Automatic Route': 'Take over the default route. Without working proxy nodes this cuts the network off.',
    'Strict Route': 'Keep the TUN device above other default routes.',
    'MTU': 'Device MTU.',
    'DNS Module': 'Let mihomo resolve DNS itself (required for fake-ip).',
    'Listen Address': 'DNS listen address, e.g. 127.0.0.1:1053.',
    'Enhanced Mode': 'fake-ip returns synthetic addresses, redir-host returns real ones.',
    'Subscription URL': 'Subscription URL, stored in the plugin environment file.',
    'Access Secret': 'Secret written into the generated configuration.',
    'Restart After Update': 'Restart the service after a successful update.',
}

for label, help_text in repl.items():
    pattern = re.compile(
        r'(<label>' + re.escape(label) + r'</label>\s*<type>[^<]*</type>\s*)<help>.*?</help>',
        re.S
    )
    text, count = pattern.subn(lambda m: m.group(1) + '<help>' + help_text + '</help>', text, count=1)
    if count == 0:
        print('MISS  ', label)

# 校验提示也一并缩短
val = {
    '<ValidationMessage>Enable the mihomo service at boot time.</ValidationMessage>':
        '<ValidationMessage>Start the service at boot.</ValidationMessage>',
    '<ValidationMessage>Enter an IP address, e.g. 127.0.0.1 (loopback only, recommended) or 0.0.0.0 (all interfaces).</ValidationMessage>':
        '<ValidationMessage>Enter an IP address, e.g. 127.0.0.1 or 0.0.0.0.</ValidationMessage>',
    '<ValidationMessage>Use up to 128 characters: letters, digits, ".", "-" and "_".</ValidationMessage>':
        '<ValidationMessage>Up to 128 characters: letters, digits, ".", "-" and "_".</ValidationMessage>',
    '<ValidationMessage>Interface name is limited to 15 characters (letters, digits, underscore).</ValidationMessage>':
        '<ValidationMessage>Up to 15 characters: letters, digits, underscore.</ValidationMessage>',
    '<ValidationMessage>Enter a listen address including port, e.g. 127.0.0.1:1053.</ValidationMessage>':
        '<ValidationMessage>Enter address and port, e.g. 127.0.0.1:1053.</ValidationMessage>',
    '<ValidationMessage>Enter an http(s) subscription URL, or leave empty.</ValidationMessage>':
        '<ValidationMessage>Enter an http(s) URL, or leave empty.</ValidationMessage>',
}
for old, new in val.items():
    if old in text:
        text = text.replace(old, new)
    else:
        print('MISS  ', old[:60])

io.open(path, 'w', encoding='utf-8', newline='\n').write(text)
print('settings.xml 已更新')
