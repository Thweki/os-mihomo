#!/usr/bin/env python3
"""第三轮用词精简：把新增的短句补进 i18n 词条表，旧的长句自动失效（之后用 --prune 清掉）"""
import io

path = 'tools/i18n_translate.py'
text = io.open(path, encoding='utf-8').read()

anchor = "    'TUN off': 'TUN 未启用',"
if anchor not in text:
    raise SystemExit('anchor not found')

new = """    'TUN off': 'TUN 未启用',
    # ---- 表单短句（设置页 / 模型校验）----
    'Start the service at boot.': '开机时启动服务。',
    'Log verbosity. Use error or silent for long term operation.': '日志级别；长期运行建议 error 或 silent。',
    'rule: follow the routing rules. global: everything through the selected proxy. direct: no proxy.':
        'rule：按规则分流；global：全部走所选节点；direct：全部直连。',
    'Let local clients use the proxy ports directly.': '允许局域网客户端直接使用代理端口。',
    'Controller listen address. Keep 127.0.0.1 unless you really need remote access.':
        '控制器监听地址，一般保持 127.0.0.1。',
    'Controller port.': '控制器端口。',
    'Controller API secret.': '控制器 API 密钥。',
    'Route traffic into mihomo through a virtual device.': '用虚拟网卡把流量导入 mihomo。',
    'Device name, must match the firewall rules (default tun_mihomo).': '设备名，需与防火墙规则一致（默认 tun_mihomo）。',
    'gvisor is recommended on FreeBSD.': 'FreeBSD 下建议 gvisor。',
    'Take over the default route. Without working proxy nodes this cuts the network off.':
        '接管默认路由；节点不可用时会断网。',
    'Keep the TUN device above other default routes.': '保持 TUN 设备优先于其它默认路由。',
    'Device MTU.': '设备 MTU。',
    'Let mihomo resolve DNS itself (required for fake-ip).': '由 mihomo 解析 DNS（fake-ip 需要）。',
    'DNS listen address, e.g. 127.0.0.1:1053.': 'DNS 监听地址，如 127.0.0.1:1053。',
    'fake-ip returns synthetic addresses, redir-host returns real ones.': 'fake-ip 返回合成地址；redir-host 返回真实地址。',
    'Subscription URL, stored in the plugin environment file.': '订阅地址，保存在插件环境文件中。',
    'Secret written into the generated configuration.': '写入生成配置的密钥。',
    'Restart the service after a successful update.': '更新成功后重启服务。',
    'Enter an IP address, e.g. 127.0.0.1 or 0.0.0.0.': '请输入 IP，如 127.0.0.1 或 0.0.0.0。',
    'Up to 128 characters: letters, digits, ".", "-" and "_".': '最多 128 字符：字母、数字与 . - _。',
    'Up to 15 characters: letters, digits, underscore.': '最多 15 字符：字母、数字、下划线。',
    'Enter address and port, e.g. 127.0.0.1:1053.': '请输入地址与端口，如 127.0.0.1:1053。',
    'Enter an http(s) URL, or leave empty.': '请输入 http(s) 地址，可留空。',
    'Pick an interface, e.g. lan or opt2.': '请选择接口，如 lan 或 opt2。',
    'Proxy group name.': '代理组名。',
    'Optional. Empty uses the interface network.': '可留空，使用接口网段。',
    'Validated with mihomo -t before it replaces the active file; the previous file is kept as a backup.':
        '保存前用 mihomo -t 校验；原文件保留为备份。',
"""

text = text.replace(anchor, new, 1)
io.open(path, 'w', encoding='utf-8', newline='\n').write(text)
print('i18n 短句已写入')
