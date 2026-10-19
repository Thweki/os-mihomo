#!/usr/bin/env python3
"""P17 词条：IPv6 选项 + "只写入我改过的项" + 说人话的对照页提示；并清掉废弃词条"""
import io

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

# ---------- 1. 清掉源码里已不存在的旧词条 ----------
drop = [
    "    'Runtime values come from the mihomo external controller, i.e. the configuration currently held in memory.':\n        '运行值来自 mihomo 的外部控制器，也就是进程内存里正在用的那份配置。',\n",
    "    'The running service cannot be reached, so only the WebUI and the file are compared. Start the service to see the values that are actually in use.':\n        '读不到正在运行的服务，因此只对照页面与文件。启动服务后才能看到真正在用的值。',\n",
    "    'Some values differ between the WebUI and the file. Press Apply on this page to write the WebUI values into the file, or press Import to load the file values into the WebGUI.':\n        '页面与文件有不一致的值：点本页「应用」会把页面里的值写进文件；点「从配置导入」则是反过来，用文件里的值更新页面。',\n",
    "    'The configuration file looks hand-written. A subscription update would replace it completely; edit the file by hand instead (or back it up first).':\n        '这份 config.yaml 看起来是手写的：点「更新订阅」会用订阅模板整份重写它。要继续手写就别点更新订阅（或先备份）。',\n",
    "    'A managed policy-routing block is present: the routing policy page replaces this block as a whole and leaves everything else untouched.':\n        '文件里有策略路由的受管区块：路由策略页只会整块替换这一段，其余内容不动。',\n",
    "    'No managed policy-routing block in the file (no interface is bound).':\n        '文件里没有受管区块（当前没有任何接口被绑定）。',\n",
    "    'IPv6 is enabled, but the TUN device only carries IPv4: IPv6 traffic bypasses mihomo. Set ipv6: false to turn IPv6 off on the proxy side, or add IPv6 handling separately.':\n        'IPv6 是开着的，而 TUN 设备只有 IPv4 地址：IPv6 流量会绕过 mihomo。可在配置里设 ipv6: false 关掉它，或单独为 v6 做分流。',\n",
    "    'Configuration file updated and validated.': '配置文件已更新并通过校验。',\n",
    "    'IPv6 traffic bypasses the proxy': 'IPv6 流量不经过代理',\n",
    "    'The TUN device only carries IPv4, so IPv6 traffic leaves this firewall without going through mihomo. Set ipv6: false in the configuration to stop that, or add IPv6 handling separately.':\n        'TUN 设备只有 IPv4 地址，IPv6 流量会不经过 mihomo 直接出去。可在配置里设 ipv6: false 阻止它，或单独处理 v6。',\n",
]
removed = 0
for item in drop:
    if item in t:
        t = t.replace(item, '', 1)
        removed += 1
print('清理旧词条:', removed, '/', len(drop))

# ---------- 2. 新增 ----------
anchor = "    'IPv6': 'IPv6',\n"
block = """    # ---- IPv6 选项（P17）----
    'IPv6 handling': 'IPv6 处理',
    'DNS over IPv6': 'DNS 返回 IPv6',
    'Let the core handle IPv6. Off = IPv6 traffic stays on the normal route (current design).':
        '让内核处理 IPv6 流量。关闭 = IPv6 照常走普通线路（当前设计如此）。',
    'Answer AAAA records. Turn off if the tunnel only carries IPv4.':
        '是否回答 AAAA（IPv6）解析。隧道只有 IPv4 时建议关闭。',
    'Answer AAAA (IPv6) records too.': '是否同时回答 AAAA（IPv6）解析。',
    'Let the core handle IPv6 traffic.': '是否让内核处理 IPv6 流量。',
    # ---- 「只写入我改过的项」（P17）----
    'Write only what I changed (recommended)': '只写入我改过的项（推荐）',
    'Write all page settings into the file': '以页面为准，全部写入文件',
    'All page settings will be written into the file.': '将把页面上的全部设置写入文件。',
    'You have not changed anything yet — pressing Apply will not write to the file.':
        '你还没改任何项 —— 现在点「应用」不会写文件。',
    'Will be written': '将写入',
    'Nothing was changed on this page, so the file was left alone.': '本次没有改动任何设置，文件保持原样。',
    'Configuration file updated: %d item(s) written — %s': '配置文件已更新，写入了 %d 项：%s',
    'The page and the file disagree on %d item(s), but you did not touch them, so they were left as they are: %s — press Import to use the file values in the page, or pick "takes precedence" to write them.':
        '还有 %d 项页面和文件对不上，但你这次没改，所以文件里没动它们：%s —— 想用文件里的值刷新页面就点「从配置导入」；想以页面为准就选「全部写入文件」。',
    # ---- 对照页：说人话（P17）----
    'The "Running" column is what the core is using right now. Change the file and you still have to restart the service before it shows up here.':
        '「运行中」那一列是内核现在真的在用的值。改完文件还得重启服务，这里才会变。',
    'A few items are not reported by the core at all (strict route, DNS mode, ...), so their "Running" cell stays empty — only the file and the core log can tell.':
        '有几项内核不对外报告（严格路由、DNS 模式等），它们那格只能空着；要确认得看文件和内核日志。',
    'The running service cannot be read right now (stopped, or the secret does not match), so only the page and the file are compared here.':
        '现在读不到运行中的服务（可能是没启动，或密钥对不上），所以这里只对比页面和文件。',
    'The page and the file disagree on some items: press Apply to write what the page says into the file, or press Import to load what the file says into the page.':
        '有几项页面和文件对不上：点「应用」就是把页面里的值写进文件；点「从配置导入」则相反，用文件里的值刷新页面。',
    'This config.yaml is hand-written, not generated from the subscription template. Updating the subscription replaces the whole file, so your own edits would be gone — do not use it, or take a backup first.':
        '你这份 config.yaml 是自己写的（不是订阅生成的）。点「更新订阅」会把整份文件换成订阅模板的内容，自己写的就没了 —— 想保留就别点它，或者先备份。',
    'The file contains a block of rules that the plugin keeps up to date (from the Policy Routing page). Do not edit inside that block: it gets replaced as a whole.':
        '文件里有一段是插件替你维护的规则（来自「路由策略」页）。别手动改这一段，它会被整段替换。',
    'No interface is bound to mihomo right now, so the file contains no plugin-managed rules.':
        '现在没有任何接口走 mihomo，所以文件里也没有插件替你维护的规则。',
    'IPv6 traffic does not go through the proxy: the mihomo tunnel only handles IPv4. Add ipv6: false in the configuration if you want IPv6 handled by the normal route, or ignore this.':
        'IPv6 流量不会走代理（mihomo 这条通道只管 IPv4）。想让它按普通线路走就在配置里写 ipv6: false；不在意也可以不管。',
    'checked by the core': '内核会校验密钥',
    'not checked (no secret)': '没设密钥，内核不校验',
    '%s (answering)': '%s（有应答）',
    '%s (no answer)': '%s（没应答）',
    # ---- 首绑顺序修复相关（P17）----
    'The firewall rules written by this attempt have been removed, so nothing is bound.':
        '本次写入的防火墙规则已撤销，当前没有任何接口被绑定。',
    'IPv6 traffic bypasses the proxy': 'IPv6 流量不经过代理',
"""
if anchor in t:
    t = t.replace(anchor, block, 1)
else:
    # 之前可能没有 'IPv6' 词条，退而用另一个锚点
    anchor2 = "    'Configuration comparison': '配置对照',\n"
    if anchor2 not in t:
        raise SystemExit('锚点未找到')
    t = t.replace(anchor2, block + anchor2, 1)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('新增词条完成')
