#!/usr/bin/env python3
"""P19：配置对照页去掉说明段落与提示框（用户要求），后端也不再生成 notes"""
import io
import re

# ---------------- 1. Inspector::report()：不再生成 notes ----------------
p = 'src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Inspector.php'
t = io.open(p, encoding='utf-8').read()

start = t.find("        $notes = [];\n")
end = t.find("        return [\n            'status' => 'ok',\n            'rows' => $rows,\n            'notes' => $notes,")
if start < 0 or end < 0 or end < start:
    raise SystemExit('Inspector 的 notes 段落没匹配上')

t = t[:start] + t[end:]
t = t.replace(
    "        return [\n            'status' => 'ok',\n            'rows' => $rows,\n            'notes' => $notes,",
    "        return [\n            'status' => 'ok',\n            'rows' => $rows,",
    1
)
t = t.replace(
    "     * @return array{status: string, rows: array, notes: array, differs: int, missing: int, runtime: bool}",
    "     * @return array{status: string, rows: array, differs: int, missing: int, runtime: bool}",
    1
)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('Inspector::report() 已不再生成 notes')

# 确认没有残留的 $notes 引用
left = [l for l in io.open(p, encoding='utf-8').read().splitlines() if '$notes' in l]
print('  残留 $notes 行:', len(left))

# ---------------- 2. settings.volt：去掉段落、提示框容器、渲染循环 ----------------
p = 'src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo/settings.volt'
t = io.open(p, encoding='utf-8').read()

old_js = """        function renderCompare(data) {
            const $notes = $('#compare-notes').empty();
            const $body = $('#compare-body').empty();

            (data['notes'] || []).forEach(function (note) {
                const warn = note['level'] === 'warning';
                $('<div>')
                    .addClass('alert ' + (warn ? 'alert-warning' : 'alert-info'))
                    .css({ 'margin-bottom': '8px' })
                    .html('<i class="fa ' + (warn ? 'fa-exclamation-triangle' : 'fa-info-circle') + ' fa-fw"></i> '
                        + escapeHtml(note['text']))
                    .appendTo($notes);
            });

"""
new_js = """        function renderCompare(data) {
            const $body = $('#compare-body').empty();

"""
if old_js in t:
    t = t.replace(old_js, new_js, 1)
    print('renderCompare 的 notes 渲染已去掉')
else:
    raise SystemExit('renderCompare 段落没匹配上')

m = re.search(r'            <p class="text-muted" style="margin-bottom: 10px;">\n(?:.*\n)*?            </p>\n            <div id="compare-notes"></div>\n', t)
if m:
    t = t[:m.start()] + t[m.end():]
    print('对照页的说明段落 + 提示框容器已去掉')
else:
    raise SystemExit('对照页标记没匹配上')

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)

# ---------------- 3. 词条：删掉不再出现的 ----------------
p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()
drop = [
    "    'The same setting can live in three places. This table shows all three: what the WebGUI remembers, what the file says, and what the running core actually uses.':\n"
    "        '同一个设置可能同时存在于三个地方。下表把它们列在一起：页面的记忆、文件里写的、内核此刻真正在用的。',\n",
    "    'Rows marked with a \"leave alone\" tag are items this plugin does not write: whatever you put in the file stays as it is.':\n"
    "        '带「不修改」标记的项：本插件不会写它 —— 文件里你写的是什么，就还是什么。',\n",
    "    'The running service cannot be read right now (stopped, or the secret does not match), so only the page and the file are compared here.':\n"
    "        '现在读不到运行中的服务（可能是没启动，或密钥对不上），所以这里只对比页面和文件。',\n",
    "    'The \"Running\" column is what the core is using right now. Change the file and you still have to restart the service before it shows up here.':\n"
    "        '「运行中」那一列是内核现在真的在用的值。改完文件还得重启服务，这里才会变。',\n",
    "    'A few items are not reported by the core at all (strict route, DNS mode, ...), so their \"Running\" cell stays empty — only the file and the core log can tell.':\n"
    "        '有几项内核不对外报告（严格路由、DNS 模式等），它们那格只能空着；要确认得看文件和内核日志。',\n",
    "    'The page and the file disagree on some items: press Apply to write what the page says into the file, or press Import to load what the file says into the page.':\n"
    "        '有几项页面和文件对不上：点「应用」就是把页面里的值写进文件；点「从配置导入」则相反，用文件里的值刷新页面。',\n",
    "    'This config.yaml is hand-written, not generated from the subscription template. Updating the subscription replaces the whole file, so your own edits would be gone — do not use it, or take a backup first.':\n"
    "        '你这份 config.yaml 是自己写的（不是订阅生成的）。点「更新订阅」会把整份文件换成订阅模板的内容，自己写的就没了 —— 想保留就别点它，或者先备份。',\n",
    "    'The file contains a block of rules that the plugin keeps up to date (from the Policy Routing page). Do not edit inside that block: it gets replaced as a whole.':\n"
    "        '文件里有一段是插件替你维护的规则（来自「路由策略」页）。别手动改这一段，它会被整段替换。',\n",
    "    'No interface is bound to mihomo right now, so the file contains no plugin-managed rules.':\n"
    "        '现在没有任何接口走 mihomo，所以文件里也没有插件替你维护的规则。',\n",
    "    'IPv6 traffic does not go through the proxy: the mihomo tunnel only handles IPv4. Add ipv6: false in the configuration if you want IPv6 handled by the normal route, or ignore this.':\n"
    "        'IPv6 流量不会走代理（mihomo 这条通道只管 IPv4）。想让它按普通线路走就在配置里写 ipv6: false；不在意也可以不管。',\n",
]
removed = 0
for item in drop:
    if item in t:
        t = t.replace(item, '', 1)
        removed += 1
    else:
        print('  !! 词条未匹配:', item.split("':")[0][:80])
print('清理词条:', removed, '/', len(drop))
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
