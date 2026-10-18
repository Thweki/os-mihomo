#!/usr/bin/env python3
"""把路由策略页第二轮改版的词条从 i18n_translate.py 里替换掉（说人话版）"""
import io
import re

path = 'tools/i18n_translate.py'
text = io.open(path, encoding='utf-8').read()

old_block_start = text.find("    'TUN off': 'TUN 未启用',")
old_block_end = text.find("    'nothing to do'", old_block_start)
if old_block_start == -1 or old_block_end == -1:
    print('未找到待替换区块，改为逐条替换')
    old_block_end = old_block_start

new_block = """    'TUN off': 'TUN 未启用',
    'apply to take effect': '应用后生效',
    'nothing bound': '未绑定任何接口',
    'mihomo rules': 'mihomo 规则',
    'OPNsense changes': 'OPNsense 变更',
    'Undo network changes': '撤销网络配置',
    'Undo': '撤销',
    'Restores the most recent config.xml backup created by this plugin and reloads the firewall.':
        '将还原本插件最近一次创建的 config.xml 备份，并重新加载防火墙。',
    'Writes the mihomo configuration and, where needed, creates the interface, gateway and firewall rule on OPNsense. config.xml is backed up first.':
        '写入 mihomo 配置；需要时在 OPNsense 上创建接口、网关和防火墙规则（先备份 config.xml）。',
    'Proxy group': '代理组',
    'Traffic exits through this group. Ignored for the direct scope.':
        '流量从该代理组出去；范围为「直连」时忽略。',
    'Firewall rule': '防火墙规则',
    'Create: the plugin creates the interface, gateway and firewall rule for this interface. Keep: you route the traffic yourself.':
        '创建：由插件创建该接口对应的接口、网关与防火墙规则；不创建：路由由你自己处理。',
    'Create': '创建',
    'Do not create': '不创建',
    'Foreign: domestic traffic stays direct. All: everything through the proxy group.':
        '仅国外：国内直连，国外走代理组；全部：所有流量都走代理组。',
    'Interface whose traffic goes through mihomo.': '流量进入 mihomo 的物理接口。',
"""

if old_block_end > old_block_start:
    text = text[:old_block_start] + new_block + text[old_block_end:]
    io.open(path, 'w', encoding='utf-8', newline='\n').write(text)
    print('已替换旧区块')
else:
    print('未替换')
