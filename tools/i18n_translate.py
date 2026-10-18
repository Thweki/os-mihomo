#!/usr/bin/env python3
"""
os-mihomo —— zh_CN 翻译词条（本插件的英文串 -> 中文）

约定
  · 这里的英文串必须与源码里 gettext()/lang._() 的**完全一致**（含标点、空格、省略号）。
  · `%s` 占位符必须原样保留，且顺序一致。
  · 已在 OPNsense 核心 zh_CN 词库中存在并恰当的条目**不在此列**（复用之，避免重复维护）。

`python tools/i18n_translate.py --strings refs/plugin-strings.json --out locales/zh_CN.po`
会生成标准 GNU .po，并在发现「词条不在插件字符串里」时直接报错（防手误）。
"""

TRANSLATIONS: dict[str, str] = {
    # ---- 页面/区块标题 ----
    'Active Connections': '活动连接',
    'Access Secret': '访问密钥',
    'Configuration File': '配置文件',
    'Core log': '内核日志',
    'Download / Upload': '下载 / 上传',
    'Log Viewer': '日志视图',
    'Memory / Core Version': '内存 / 内核版本',
    'Proxy Groups': '代理分组',
    'Subscription Management': '订阅管理',
    'Subscription URL': '订阅地址',
    'Subscription log': '订阅日志',
    'Total Downloaded / Uploaded': '累计下载 / 上传',
    'Traffic only enters the TUN device when firewall or policy routing sends it there.':
        '仅当防火墙或策略路由把流量送入 TUN 设备时才会走代理。',

    # ---- 按钮/动作 ----
    'Clear Log': '清空日志',
    'Clear log?': '清空日志？',
    'Close all': '全部断开',
    'Import from configuration file': '从配置文件导入',
    'Start Subscription': '开始订阅',
    'Test Active Configuration': '校验当前配置',
    'Validate': '校验',
    'Restart the service after applying': '应用后重启服务',
    'Restart service after a successful update': '更新成功后重启服务',
    'Restart service?': '重启服务？',

    # ---- 通用词 ----
    'bytes': '字节',
    'not running': '未运行',
    'Chain': '链路',
    'Loading …': '加载中 …',
    '…': '未知',
    '(no output)': '（无输出）',

    # ---- 提示/消息 ----
    '%s does not exist, the service cannot start.': '%s 不存在，服务无法启动。',
    'A node name is required.': '需要提供节点名称。',
    'Active configuration is invalid': '当前配置无效',
    'Active configuration is valid': '当前配置有效',
    'All connections closed.': '已关闭全部连接。',
    'Apply failed': '应用失败',
    'Configuration content must not be empty.': '配置内容不能为空。',
    'Configuration file %s is missing. Install the plugin first.': '配置文件 %s 不存在，请先安装插件。',
    'Configuration file is missing': '配置文件缺失',
    'Configuration file not found.': '未找到配置文件。',
    'Configuration file updated and validated.': '配置文件已更新并通过校验。',
    'Configuration saved': '配置已保存',
    'Configuration syntax is invalid': '配置语法无效',
    'Configuration syntax is valid': '配置语法有效',
    'Connection closed.': '连接已断开。',
    'Controller responded with HTTP code %s.': '控制器返回 HTTP 状态码 %s。',
    'DNS hijacking is configured': '已配置 DNS 劫持',
    'Enter HTTP or HTTPS subscription URL': '输入 HTTP 或 HTTPS 订阅地址',
    'Enter dashboard access secret': '输入控制面板访问密钥',
    'External controller has no secret': '外部控制器未设置密钥',
    'External controller is not configured in the mihomo configuration file.':
        'mihomo 配置文件中未设置外部控制器。',
    'External controller is reachable from the network': '外部控制器可从网络访问',
    'Failed to save the subscription settings.': '保存订阅设置失败。',
    'Group and member are required.': '需要提供分组与节点名称。',
    'Import failed': '导入失败',
    'Invalid log level.': '无效的日志层级。',
    'Invalid mode.': '无效的模式。',
    'Log file cleared.': '日志已清空。',
    'Mode switched to %s.': '已切换到 %s 模式。',
    'No output from the configuration test.': '配置校验没有输出。',
    'No proxy groups are defined in the configuration.': '配置中未定义代理分组。',
    'Only HTTP or HTTPS subscription URLs are allowed.': '订阅地址仅允许使用 HTTP 或 HTTPS。',
    'POST required.': '需要 POST 请求。',
    'Placeholder proxy nodes detected': '检测到占位节点',
    'Please review before starting the service': '启动服务前请先确认以下风险',
    'Save failed': '保存失败',
    'Service is enabled at boot but not running': '已设置为开机自启，但当前未运行',
    'Service is not enabled; nothing to restart.': '服务未启用，无需重启。',
    'Service is running and enabled at boot': '服务正在运行且已开机自启',
    'Service restart requested.': '已请求重启服务。',
    'Service will not start automatically on boot.': '服务不会在开机时自动启动。',
    'Service will start automatically on boot.': '服务将在开机时自动启动。',
    'Set a secret in the configuration, otherwise the API is unauthenticated.':
        '请在配置中设置密钥，否则 API 将无需认证。',
    'Set a subscription URL before starting an update.': '请先设置订阅地址再执行更新。',
    'Settings applied': '设置已应用',
    'Settings imported': '设置已导入',
    'Settings imported from the active configuration.': '已从当前配置导入设置。',
    'Settings saved': '设置已保存',
    'Strict route is enabled': '已启用严格路由',
    'Subscription settings saved.': '订阅设置已保存。',
    'Subscription task submitted; follow the log for progress.': '订阅任务已提交，请查看日志了解进度。',
    'Subscription update failed': '订阅更新失败',
    'Subscription update started': '订阅更新已开始',
    'Switched "%s" to "%s".': '已将 "%s" 切换到 "%s"。',
    'TUN mode is enabled (automatic route takeover off)': '已启用 TUN 模式（未自动接管路由）',
    'TUN with automatic route takeover is enabled': '已启用 TUN 且自动接管路由',
    'The TUN device is guaranteed to win over other default routes while the service runs.':
        '服务运行时，TUN 设备将优先于其它默认路由。',
    'The configuration file was not written. mihomo rejected it:%s':
        '配置文件未写入，mihomo 校验未通过：%s',
    'The controller is not reachable. Start the service to see proxy groups.':
        '控制器不可达；启动服务后可查看代理分组。',
    'The full mihomo configuration. It is validated with "mihomo -t" before it replaces the active file, and the previous file is kept as a timestamped backup.':
        '完整的 mihomo 配置。落盘前会先用 "mihomo -t" 校验，并保留带时间戳的备份。',
    'The running service keeps its current in-memory configuration until it is restarted.':
        '运行中的服务在重启前仍使用内存中的旧配置。',
    'The selected log file will be emptied.': '选中的日志文件将被清空。',
    'The service is not enabled at boot.': '服务未设置为开机自启。',
    'The service is stopped. Use the start button in the page header to bring it up.':
        '服务已停止，可用页面右上角的启动按钮将其拉起。',
    'The service will be restarted right after the update, which rebuilds the TUN device and its routes. Make sure the new nodes work, otherwise clients behind this firewall may lose connectivity.':
        '更新后会立即重启服务，这会重建 TUN 设备及其路由。请确认新节点可用，否则本机后面的客户端可能断网。',
    'The subscription script is not installed; subscription updates are unavailable.':
        '未安装订阅脚本，无法执行订阅更新。',
    'Unable to create a staging file in /tmp.': '无法在 /tmp 创建临时文件。',
    'Unable to reach the mihomo external controller.': '无法连接 mihomo 外部控制器。',
    'Unable to write the staging file.': '无法写入临时文件。',
    'Unknown log file.': '未知的日志文件。',
    'Use %sSettings%s to enable it, then start it from the controls in the page header.':
        '请到 %s设置%s 中启用，然后使用页面右上角的控件启动。',
    'Validation failed': '校验未通过',
    'Validation passed': '校验通过',
    'mihomo is active and will start again after a reboot.':
        'mihomo 正在运行，并会在重启后自动启动。',

    # ---- 表单 XML 的标签与帮助（由 ControllerBase::parseFormNode 统一 gettext）----
    'Enable mihomo': '启用 mihomo',
    'Enable the mihomo service at boot time.': '开机时启动 mihomo 服务。',
    'Start the mihomo service at boot time. It is deliberately disabled by default:':
        '开机时启动 mihomo 服务。默认刻意关闭：在开启 TUN 自动接管路由的情况下，'
        '未配置好就启动代理会让整个网络断网。',
    'Port of the RESTful controller.': 'RESTful 控制器的端口。',
    'Bind Address': '绑定地址',
    'Address the RESTful controller listens on. Keep 127.0.0.1 so that only this firewall':
        '控制器监听的地址。保持 127.0.0.1，使只有本机可以访问 —— '
        '本 WebGUI 通过回环接口与控制器通信。',
    'Shared secret for the controller API. Leave empty only if the controller is bound':
        '控制器 API 的共享密钥。只有当控制器绑定在回环地址时才可留空。',
    'Allow LAN': '允许局域网',
    'Allow clients from the local network to use the SOCKS/HTTP proxy ports directly.':
        '允许局域网客户端直接使用 SOCKS/HTTP 代理端口。',
    'Create a virtual network device so that traffic can be routed into mihomo without':
        '创建虚拟网络设备，无需改动客户端配置即可把流量导入 mihomo。',
    'Interface name of the TUN device. It must match the interface that the firewall rules':
        'TUN 设备的接口名。必须与防火墙规则引用的接口一致（默认 tun_mihomo）。',
    'Stack': '协议栈',
    'gvisor is the most compatible option on FreeBSD; system may fail under some conditions; mixed combines both.':
        'gvisor 在 FreeBSD 上兼容性最好；system 在某些环境下可能失败；mixed 两者兼用。',
    'Automatically insert routes for all traffic into the TUN device. This is what makes':
        '自动把所有流量的路由指向 TUN 设备。这是 mihomo 成为透明网关的关键 —— '
        '也正因如此，节点未配置好就启动会导致断网。',
    'Make sure the TUN device wins over other default routes while the service is running.':
        '服务运行时，确保 TUN 设备优先于其它默认路由。',
    'Maximum transmission unit of the TUN device.': 'TUN 设备的最大传输单元。',
    'DNS Module': 'DNS 模块',
    'Let mihomo answer DNS queries itself (needed for fake-ip mode and rule based resolution).':
        '由 mihomo 自行应答 DNS 查询（fake-ip 模式与基于规则的解析需要）。',
    'Loopback address and port mihomo listens on for DNS, e.g. 127.0.0.1:1053.':
        'mihomo 监听 DNS 的回环地址与端口，例如 127.0.0.1:1053。',
    'Enhanced Mode': '增强模式',
    'fake-ip returns a synthetic address and resolves on connection; redir-host resolves up front and reports real addresses.':
        'fake-ip 返回合成地址、在建立连接时才解析；redir-host 提前解析并返回真实地址。',
    'Restart After Update': '更新后重启',
    'Restart mihomo automatically once a subscription update finished successfully. Keep this off until you have verified the new nodes.':
        '订阅更新成功后自动重启 mihomo。在确认新节点可用之前请保持关闭。',
    'Secret that the subscription updater writes into the generated configuration.':
        '订阅更新器写入生成配置的密钥。',
    'Enter an http(s) subscription URL, or leave empty.': '输入 http(s) 订阅地址，也可以留空。',
    'Enter a listen address including port, e.g. 127.0.0.1:1053.':
        '输入监听地址（含端口），例如 127.0.0.1:1053。',
    'Enter an IP address, e.g. 127.0.0.1 (loopback only, recommended) or 0.0.0.0 (all interfaces).':
        '输入 IP 地址，例如 127.0.0.1（仅回环，推荐）或 0.0.0.0（所有接口）。',
    'Use up to 128 characters: letters, digits, ".", "-" and "_".':
        '最多 128 个字符：字母、数字、"."、"-" 和 "_"。',
    'Interface name is limited to 15 characters (letters, digits, underscore).':
        '接口名最多 15 个字符（字母、数字、下划线）。',
    'Verbosity of the mihomo log file. Use "error" or "silent" for long term operation':
        'mihomo 日志的详细程度。长期运行时建议用 "error" 或 "silent" 以免日志过大。',
    'rule: follow the routing rules (normal operation)':
        'rule：按分流规则处理（常规用法）；global：全部走所选节点；direct：全部直连。',
    'HTTP(S) URL of your subscription. It is stored in the plugin environment file and used by the subscription updater.':
        '订阅的 HTTP(S) 地址。它保存在插件的环境文件中，供订阅更新器使用。',
    'External Controller': '外部控制器',
    'TUN Device': 'TUN 设备',
    'TUN Mode': 'TUN 模式',
    'Automatic Route': '自动路由',
    'Strict Route': '严格路由',
    'Restart mihomo right after a successful subscription update.':
        '订阅更新成功后立即重启 mihomo。',

    # ---- 安全体检的长句详情（原为跨行拼接，已并成单字面量以便提取）----
    'Starting the service will insert routes for all IPv4 traffic into the TUN device.':
        '启动服务会把所有 IPv4 流量的路由指向 TUN 设备。若节点不可达或尚未配置，'
        '本机后面所有设备都会失去网络。',
    'The configuration still contains the placeholder server 88.88.88.88 shipped with the plugin.':
        '配置里仍是随包分发的占位服务器 88.88.88.88。请在启动服务前换成真实订阅或真实节点。',
    'external-controller is bound to %s. Anyone who can reach that address and knows the secret':
        'external-controller 绑定在 %s。任何能访问该地址并知道密钥的人都能改代理配置。'
        '建议改为 127.0.0.1 —— 本 WebGUI 只通过回环接口与控制器通信。',
    'DNS queries on port 53 are redirected into mihomo while the service runs. If the proxy is broken':
        '服务运行期间，53 端口的 DNS 查询会被重定向到 mihomo。'
        '若代理失效，本机后面所有客户端的域名解析也会随之失效。',
    'On the next reboot mihomo will take over routing as soon as it starts. Verify the configuration':
        '下次重启后 mihomo 一启动就会接管路由。重启前请先确认配置无误。',
}


def main() -> int:
    import argparse
    import json
    import sys
    from pathlib import Path

    parser = argparse.ArgumentParser()
    parser.add_argument('--strings', required=True, help='extract_strings.py --out 生成的 JSON')
    parser.add_argument('--out', required=True, help='输出的 .po 路径')
    parser.add_argument('--missing', default='', help='待补清单（只允许翻译其中的词条，避免覆盖核心译文）')
    parser.add_argument('--force', action='store_true', help='覆盖已存在的 .po')
    args = parser.parse_args()

    out = Path(args.out)
    if out.exists() and not args.force:
        print(f'{out} 已存在；如需覆盖请加 --force（翻译应以 .po 为准继续演进）')
        return 0

    known = set(json.loads(Path(args.strings).read_text(encoding='utf-8')))

    # 宽松解析：允许用「前 50 字符」唯一匹配，规避控制台复制长句时标点（如破折号）失真
    resolved: dict[str, str] = {}
    unresolved: list[str] = []
    for key, value in TRANSLATIONS.items():
        if key in known:
            resolved[key] = value
            continue
        prefix = key[:50]
        candidates = [k for k in known if k.startswith(prefix)]
        if len(candidates) == 1:
            print(f'  (前缀匹配) {prefix!r}... -> {candidates[0][50:]!r}')
            resolved[candidates[0]] = value
        else:
            unresolved.append(key)

    if unresolved:
        print('错误：以下词条无法匹配到插件字符串（拼写/标点不一致，或前缀不唯一）：', file=sys.stderr)
        for item in unresolved:
            print(f'  {item!r}', file=sys.stderr)
        return 1

    # 只允许翻译「核心没有译文」的词条，避免覆盖系统翻译
    if args.missing:
        allowed = {line.rstrip('\n') for line in Path(args.missing).read_text(encoding='utf-8').splitlines() if line}
        overlap = sorted(set(resolved) & (known - allowed))
        if overlap:
            print('错误：以下词条在核心 zh_CN 词库中已有译文，不应覆盖：', file=sys.stderr)
            for item in overlap:
                print(f'  {item!r}', file=sys.stderr)
            return 1

    TRANSLATIONS_RESOLVED = resolved

    lines = [
        '# os-mihomo 插件中文（简体）翻译',
        '# 由 tools/i18n_translate.py 生成；词条与源码严格一致，%s 占位符保持顺序不变。',
        '# 用法（设备上）：tools/i18n.ps1 会调用 tools/mo_editor.py 合并进系统 OPNsense.mo',
        '#',
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: os-mihomo 1.1.0\\n"',
        '"Language: zh_CN\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        '',
    ]
    for msgid in sorted(TRANSLATIONS_RESOLVED):
        lines.append(f'msgid "{po_escape(msgid)}"')
        lines.append(f'msgstr "{po_escape(TRANSLATIONS_RESOLVED[msgid])}"')
        lines.append('')

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('\n'.join(lines), encoding='utf-8', newline='\n')
    print(f'生成 {out}：{len(TRANSLATIONS_RESOLVED)} 条词条')
    return 0


def po_escape(text: str) -> str:
    return text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


if __name__ == '__main__':
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
