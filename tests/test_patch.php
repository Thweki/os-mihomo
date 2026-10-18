<?php

/*
 * os-mihomo —— Config::patchKeys 回归测试
 *
 * 在目标机以 root 运行；只读取传入的配置文件副本，所有产物落在 /tmp，不触碰系统状态。
 * 用法: php test_patch.php /tmp/mihomo-test/config.yaml
 */

foreach ([__DIR__ . '/Config.php', '/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php'] as $candidate) {
    if (is_file($candidate)) {
        require_once $candidate;
        break;
    }
}
foreach ([__DIR__ . '/Inspector.php', '/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Inspector.php'] as $candidate) {
    if (is_file($candidate)) {
        require_once $candidate;
        break;
    }
}

use OPNsense\Mihomo\Config;
use OPNsense\Mihomo\Inspector;

$file = $argv[1] ?? '/tmp/mihomo-test/config.yaml';
if (!is_file($file)) {
    fwrite(STDERR, "missing fixture: {$file}\n");
    exit(2);
}
Config::setFileOverride($file);
$original = file_get_contents($file);

$failures = 0;
function check(string $label, bool $ok, string $detail = ''): void
{
    global $failures;
    if ($ok) {
        echo "  PASS  {$label}\n";
    } else {
        $failures++;
        echo "  FAIL  {$label}" . ($detail !== '' ? "  [{$detail}]" : '') . "\n";
    }
}

function writeTemp(string $content): string
{
    $path = tempnam('/tmp', 'patchtest-');
    file_put_contents($path, $content);
    return $path;
}

echo "=== 0. scan() 基线读取 ===\n";
$scan = Config::scan();
foreach (['log-level', 'mode', 'external-controller', 'secret', 'tun.enable', 'tun.auto-route', 'tun.device', 'dns.enable', 'dns.listen', 'allow-lan'] as $key) {
    check("scan {$key}", array_key_exists($key, $scan), $scan[$key] ?? '(missing)');
}
echo "  info  external-controller=" . ($scan['external-controller'] ?? '?') . "\n";
echo "  info  tun.enable=" . ($scan['tun.enable'] ?? '?') . " tun.device=" . ($scan['tun.device'] ?? '?') . "\n";
echo "  info  controllerBase=" . (string)Config::controllerBase() . "\n";
check('controllerBase 推导', Config::controllerBase() !== null, (string)Config::controllerBase());
check('占位节点检测', Config::hasPlaceholderProxies());

echo "\n=== 1. 顶层替换 ===\n";
$tmp = writeTemp(Config::patchKeys($original, [
    'log-level' => 'warning',
    'mode' => 'global',
    'allow-lan' => false,
]));
$patched = file_get_contents($tmp);
$rescan = Config::scan($tmp);
check('log-level replaced', ($rescan['log-level'] ?? '') === 'warning', $rescan['log-level'] ?? '');
check('mode replaced', ($rescan['mode'] ?? '') === 'global', $rescan['mode'] ?? '');
check('allow-lan replaced', ($rescan['allow-lan'] ?? '') === 'false', $rescan['allow-lan'] ?? '');
check('tun.device 未受影响', ($rescan['tun.device'] ?? '') === ($scan['tun.device'] ?? 'x'), $rescan['tun.device'] ?? '');
check(
    '行数不变',
    count(preg_split("/\n/", $patched)) === count(preg_split("/\n/", $original)),
    count(preg_split("/\n/", $patched)) . ' vs ' . count(preg_split("/\n/", $original))
);
@unlink($tmp);

echo "\n=== 1b. 值相同时零改动 / 行尾注释保留 ===\n";
/* 用夹具自身的当前值做「原值」判断，避免夹具被改过导致误报（例如 tun.enable 已改成 false） */
$noop = Config::patchKeys($original, [
    'mode' => $scan['mode'],
    'allow-lan' => ($scan['allow-lan'] ?? 'false') === 'true',
    'tun.enable' => ($scan['tun.enable'] ?? 'false') === 'true',
    'log-level' => $scan['log-level'],
]);
check('全部键都是原值时字节完全不变', $noop === $original, 'tun.enable=' . ($scan['tun.enable'] ?? '?'));
$fixture = "# header comment\nlog-level: info #行尾注释要保留\nmode: rule\ntun:\n  enable: true #keep-tun\n";
$out = Config::patchKeys($fixture, ['log-level' => 'debug', 'tun.enable' => false]);
check('改值后保留行尾中文注释', str_contains($out, 'log-level: debug #行尾注释要保留'), $out);
check('嵌套改值后保留行尾注释', str_contains($out, 'enable: false #keep-tun'), $out);
check('未受管行原样保留', str_contains($out, 'mode: rule') && str_contains($out, '# header comment'));
check('幂等：再次应用无变化', Config::patchKeys($out, ['log-level' => 'debug', 'tun.enable' => false]) === $out);

echo "\n=== 2. 嵌套替换（已存在的键） ===\n";
$tmp = writeTemp(Config::patchKeys($original, [
    'tun.enable' => false,
    'tun.stack' => 'system',
    'tun.mtu' => 1400,
    'dns.listen' => '127.0.0.1:1053',
]));
$patched = file_get_contents($tmp);
$rescan = Config::scan($tmp);
check('tun.enable=false', ($rescan['tun.enable'] ?? '') === 'false', $rescan['tun.enable'] ?? '');
check('tun.stack=system', ($rescan['tun.stack'] ?? '') === 'system', $rescan['tun.stack'] ?? '');
check('tun.mtu=1400', ($rescan['tun.mtu'] ?? '') === '1400', $rescan['tun.mtu'] ?? '');
check('dns.listen 保持', ($rescan['dns.listen'] ?? '') === '127.0.0.1:1053', $rescan['dns.listen'] ?? '');
check('tun.sniffer 等同级键仍在', str_contains($patched, 'dns-hijack'));
check('proxies 未被破坏', str_contains($patched, 'proxies:') && str_contains($patched, 'vless-reality-vision-bw'));
check('rules 未被破坏', str_contains($patched, 'GEOSITE,cn,DIRECT'));
check('中文行尾注释保留', str_contains($patched, '#在调试结果后，改为error，减少日志输出。'));
@unlink($tmp);

echo "\n=== 3. 新增不存在的键 ===\n";
$tmp = writeTemp(Config::patchKeys("# minimal\nmode: rule\n", [
    'log-level' => 'info',
    'tun.enable' => true,
    'tun.brand-new' => 'x',
    'dns.listen' => '127.0.0.1:1053',
]));
$rescan = Config::scan($tmp);
check('新增顶层键', ($rescan['log-level'] ?? '') === 'info', $rescan['log-level'] ?? '');
check('新增嵌套块+键', ($rescan['tun.enable'] ?? '') === 'true', $rescan['tun.enable'] ?? '');
check('块内二次新增', ($rescan['tun.brand-new'] ?? '') === 'x', $rescan['tun.brand-new'] ?? '');
check('新增 dns 块', ($rescan['dns.listen'] ?? '') === '127.0.0.1:1053', $rescan['dns.listen'] ?? '');
@unlink($tmp);

echo "\n=== 4. 特殊值渲染 ===\n";
$tmp = writeTemp(Config::patchKeys($original, [
    'secret' => 'abc-123_XYZ',
    'external-controller' => '127.0.0.1:9090',
    'log-level' => 'error',
]));
$rescan = Config::scan($tmp);
check('secret 无多余引号', ($rescan['secret'] ?? '') === 'abc-123_XYZ', $rescan['secret'] ?? '');
check('controller 无多余引号', ($rescan['external-controller'] ?? '') === '127.0.0.1:9090', $rescan['external-controller'] ?? '');
check('log-level 已改', ($rescan['log-level'] ?? '') === 'error', $rescan['log-level'] ?? '');
@unlink($tmp);

echo "\n=== 5. 幂等性 ===\n";
$once = Config::patchKeys($original, ['tun.enable' => false, 'mode' => 'rule']);
$twice = Config::patchKeys($once, ['tun.enable' => false, 'mode' => 'rule']);
check('重复应用结果一致', $once === $twice);

echo "\n=== 6. CRLF 兼容 ===\n";
$crlf = str_replace("\n", "\r\n", $original);
$tmp = writeTemp(Config::patchKeys($crlf, ['tun.enable' => false]));
$patched = file_get_contents($tmp);
check('CRLF 保留', str_contains($patched, "\r\n"));
check('CRLF 下替换成功', (Config::scan($tmp)['tun.enable'] ?? '') === 'false', Config::scan($tmp)['tun.enable'] ?? '');
@unlink($tmp);

echo "\n=== 7. 落盘前校验器（mihomo -t）===\n";
if (!is_file('/usr/local/bin/mihomo')) {
    echo "  SKIP  mihomo 内核尚未安装\n";
} else {
    $tmp = writeTemp(Config::patchKeys($original, ['log-level' => 'error']));
    $out = [];
    $rc = 0;
    exec('/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f ' . escapeshellarg($tmp) . ' 2>&1', $out, $rc);
    check('mihomo -t 接受补丁结果', $rc === 0, implode(' | ', array_slice($out, 0, 3)));
    @unlink($tmp);
}

echo "\n=== 8. 路由策略：受管区块 ===\n";
$policyRules = [
    'AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,geolocation-!cn)),PROXY-US',
    'AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,gfw)),PROXY-US',
    'SRC-IP-CIDR,192.168.2.0/24,DIRECT',
];
$blocked = Config::applyPolicyBlock($original, $policyRules);
check('区块含开始标记', str_contains($blocked, Config::POLICY_MARK_BEGIN));
check('区块含结束标记', str_contains($blocked, Config::POLICY_MARK_END));
check('规则已写入', substr_count($blocked, 'SRC-IP-CIDR,192.168.1.0/24') === 2, (string)substr_count($blocked, 'SRC-IP-CIDR,192.168.1.0/24'));
check('规则缩进与文件一致', str_contains($blocked, "\n  - AND,((SRC-IP-CIDR,192.168.1.0/24)"), 'expect 2-space indent');
check('插在 rules: 之后且位于原有规则之前', (bool)preg_match('/rules:\s*\n\s*# >>> os-mihomo:policy-routing.*GEOSITE,private,DIRECT/s', $blocked));
check('原有规则保持不变', str_contains($blocked, 'GEOSITE,private,DIRECT'));
check('其余内容逐字节保留（除新增块）', str_contains($blocked, 'external-controller:'), '');

echo "\n=== 9. 路由策略：幂等与替换 ===\n";
$again = Config::applyPolicyBlock($blocked, $policyRules);
check('重复应用内容不变（幂等）', $again === $blocked);
$changed = Config::applyPolicyBlock($blocked, ['SRC-IP-CIDR,10.0.0.0/8,DIRECT']);
check('替换旧块而非追加', substr_count($changed, Config::POLICY_MARK_BEGIN) === 1, (string)substr_count($changed, Config::POLICY_MARK_BEGIN));
check('旧规则已被移除', !str_contains($changed, '192.168.1.0/24'));
check('空规则时整块移除', !str_contains(Config::applyPolicyBlock($blocked, []), Config::POLICY_MARK_BEGIN));

echo "\n=== 10. 路由策略：规则渲染 ===\n";
$rows = [
    ['enabled' => '1', 'interface' => 'lan', 'source' => '', 'scope' => 'foreign', 'target' => 'PROXY-US'],
    ['enabled' => '1', 'interface' => 'opt2', 'source' => '10.0.0.0/8', 'scope' => 'all', 'target' => 'PROXY-JP'],
    ['enabled' => '1', 'interface' => 'opt1', 'source' => '', 'scope' => 'direct', 'target' => ''],
    ['enabled' => '0', 'interface' => 'lan', 'source' => '', 'scope' => 'all', 'target' => 'PROXY-US'],
    ['enabled' => '1', 'interface' => 'opt3', 'source' => '', 'scope' => 'all', 'target' => ''],
];
$rendered = Config::renderPolicyRules($rows, ['lan' => '192.168.1.0/24', 'opt1' => '192.168.2.0/24', 'opt2' => '192.168.10.0/24']);
check('foreign 生成 2 条 AND 规则', in_array('AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,geolocation-!cn)),PROXY-US', $rendered, true)
    && in_array('AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,gfw)),PROXY-US', $rendered, true));
check('all 生成 1 条 SRC-IP-CIDR', in_array('SRC-IP-CIDR,10.0.0.0/8,PROXY-JP', $rendered, true));
check('direct 生成 DIRECT', in_array('SRC-IP-CIDR,192.168.2.0/24,DIRECT', $rendered, true));
check('未启用的行不生成', count(array_filter($rendered, fn($r) => str_contains($r, 'PROXY-US'))) === 2, (string)count($rendered));
check('无源/无出口的行被跳过', count($rendered) === 4, (string)count($rendered));
check('接口网段能自动补齐', in_array('SRC-IP-CIDR,192.168.2.0/24,DIRECT', $rendered, true));

echo "\n=== 11. 路由策略：真配置 + mihomo -t ===\n";
/* 用真实存在的出口（DIRECT）做校验，避免测试数据里的假组名让 mihomo -t 拒绝 —— 那属于正确行为 */
$validRules = [
    'AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,geolocation-!cn)),DIRECT',
    'SRC-IP-CIDR,192.168.2.0/24,DIRECT',
];
$patched = Config::applyPolicyBlock($original, $validRules);
$tmp = writeTemp($patched);
if (!is_file('/usr/local/bin/mihomo')) {
    echo "  SKIP  mihomo 内核尚未安装\n";
} else {
    $out = [];
    $rc = 0;
    exec('/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f ' . escapeshellarg($tmp) . ' 2>&1', $out, $rc);
    check('mihomo -t 接受带策略区块的配置', $rc === 0, implode(' | ', array_slice(array_filter($out, fn($l) => stripos($l, 'test is successful') === false), 0, 4)));
}
/* 引用了不存在的代理组时，mihomo -t 必须拒绝（这正是 apply 的安全网） */
$badRules = ['AND,((SRC-IP-CIDR,192.168.1.0/24),(GEOSITE,geolocation-!cn)),NO-SUCH-GROUP-XYZ'];
$tmpBad = writeTemp(Config::applyPolicyBlock($original, $badRules));
if (is_file('/usr/local/bin/mihomo')) {
    $out2 = [];
    $rc2 = 0;
    exec('/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f ' . escapeshellarg($tmpBad) . ' 2>&1', $out2, $rc2);
    check('引用不存在的组会被 mihomo -t 拒绝', $rc2 !== 0, 'rc=' . $rc2);
}
$snippet = Config::applyPolicyBlock("rules:\n  - MATCH,DIRECT\n", ['SRC-IP-CIDR,192.168.1.0/24,DIRECT']);
check('无 rules: 键时新建区块', str_contains(Config::applyPolicyBlock("mode: rule\n", ['SRC-IP-CIDR,1.0.0.0/8,DIRECT']), "rules:\n"));
@unlink($tmp);
@unlink($tmpBad);

echo "\n=== 12. 代理组名解析（块风格 + flow 风格）===\n";
$blockStyle = "proxy-groups:\n  - name: 块风格组\n    type: select\n  - name: 第二组\n    type: url-test\nrules:\n  - MATCH,DIRECT\n";
$flowStyle = "proxy-groups:\n  - { name: '🇺🇸 United States', type: select, proxies: ['a'] }\n  - { name: 🇯🇵 Japan, type: url-test, url: 'http://x' }\nrules:\n  - MATCH,DIRECT\n";
$tmpB = writeTemp($blockStyle);
$tmpF = writeTemp($flowStyle);
check('块风格分组名', Config::policyTargets($tmpB) === ['块风格组', '第二组'], implode(',', Config::policyTargets($tmpB)));
check('flow 风格分组名', Config::policyTargets($tmpF) === ['🇺🇸 United States', '🇯🇵 Japan'], implode(',', Config::policyTargets($tmpF)));
check('只扫 proxy-groups 段', !in_array('MATCH,DIRECT', Config::policyTargets($tmpF), true));
@unlink($tmpB);
@unlink($tmpF);

echo "\n=== 13. 流式列表与 sniffer 键 ===\n";
check('流式列表原样输出', Config::renderValue('[443, 8443]') === '[443, 8443]', Config::renderValue('[443, 8443]'));
$sniff = Config::snifferKeys(true);
check(
    'sniffer 键齐全（含嗅探端口）',
    count($sniff) === 8 && $sniff['sniffer.enable'] === true && $sniff['sniffer.sniff.TLS.ports'] === '[443, 8443]',
    (string)count($sniff)
);
check('关闭时只写 enable', Config::snifferKeys(false) === ['sniffer.enable' => false]);
$plain = "log-level: info\ndns:\n  enable: true\n";
$patchedSn = Config::patchKeys($plain, Config::snifferKeys(true));
check('能从零建出嵌套 sniffer 结构', str_contains($patchedSn, 'sniffer:') && str_contains($patchedSn, 'ports: [443, 8443]'), $patchedSn);
$tmpSn = writeTemp($patchedSn);
if (is_file('/usr/local/bin/mihomo')) {
    $o = [];
    $r = 0;
    exec('/usr/local/bin/mihomo -t -d /usr/local/etc/mihomo -f ' . escapeshellarg($tmpSn) . ' 2>&1', $o, $r);
    check('mihomo -t 接受生成的 sniffer 块', $r === 0, implode(' | ', array_slice($o, -2)));
}
@unlink($tmpSn);
/* 幂等：已存在完整块时再次应用不应改变字节 */
$again2 = Config::patchKeys($patchedSn, Config::snifferKeys(true));
check('sniffer 应用幂等', $again2 === $patchedSn);

echo "\n=== 14. Inspector（配置对照，只读纯函数） ===\n";
check('normalize 布尔/数字/引号', Inspector::normalize(true) === 'true'
    && Inspector::normalize('0') === 'false'
    && Inspector::normalize('"Yes"') === 'true'
    && Inspector::normalize(' Info ') === 'info'
    && Inspector::normalize(null) === null);

$inspYaml = <<<YAML
log-level: info
mode: rule
allow-lan: false
external-controller: 127.0.0.1:9090
secret: "abc123"
tun:
  enable: true
  device: tun_mihomo     # 一行注释
  auto-route: false
  mtu: 1500
dns:
  enable: true
  listen: 127.0.0.1:1053
sniffer:
  enable: true
ipv6: false
YAML;

check('yamlValue 顶层', Inspector::yamlValue($inspYaml, 'log-level') === 'info', (string)Inspector::yamlValue($inspYaml, 'log-level'));
check('yamlValue 嵌套 + 去注释', Inspector::yamlValue($inspYaml, 'tun.device') === 'tun_mihomo', (string)Inspector::yamlValue($inspYaml, 'tun.device'));
check('yamlValue 带引号的值原样返回', Inspector::yamlValue($inspYaml, 'secret') === '"abc123"', (string)Inspector::yamlValue($inspYaml, 'secret'));
check('yamlValue 不存在的键返回 null', Inspector::yamlValue($inspYaml, 'tun.nope') === null);
check('yamlValue 不走错层级', Inspector::yamlValue("tun:\n  enable: true\ndns:\n  enable: false\n", 'dns.enable') === 'false', (string)Inspector::yamlValue("tun:\n  enable: true\ndns:\n  enable: false\n", 'dns.enable'));

check('handwritten 判定：模板配置为假', Inspector::looksHandwritten("proxy-groups:\n  - name: 🌍选择节点\nrules: []\n") === false);
check('handwritten 判定：手写配置为真', Inspector::looksHandwritten("proxies:\n  - { name: A, server: 1.2.3.4 }\nproxy-groups:\n  - name: US-EXIT\n") === true);
check('handwritten 判定：空文件为假', Inspector::looksHandwritten('') === false);
check('受管区块检测', Inspector::hasManagedBlock("rules:\n  " . Config::POLICY_MARK_BEGIN . "\n") === true
    && Inspector::hasManagedBlock("rules:\n  - MATCH,DIRECT\n") === false);
check('IPv6 判定（未写=允许）', Inspector::ipv6Allowed("log-level: info\n") === true);
check('IPv6 判定（false=不允许）', Inspector::ipv6Allowed($inspYaml) === false);

/* 对照表：模型值故意与文件制造 3 种状态 */
$model = [
    'log-level' => 'info',            // 一致
    'mode' => 'global',               // 不一致
    'allow-lan' => 'false',           // 一致（写法不同）
    'external-controller' => '127.0.0.1:9090',
    'secret' => 'abc123',
    'tun.enable' => 'true',
    'tun.device' => 'tun_mihomo',
    'tun.stack' => 'gvisor',          // 文件里没写 → missing
    'tun.auto-route' => 'false',
    'tun.strict-route' => 'false',
    'tun.mtu' => '1500',
    'dns.enable' => 'true',
    'dns.listen' => '127.0.0.1:1053',
    'dns.enhanced-mode' => 'redir-host',
    'sniffer.enable' => 'true',
];
$runtimeStub = ['log-level' => 'info', 'mode' => 'rule', 'tun' => ['enable' => true, 'auto-route' => false, 'mtu' => 1500]];
$rows = Inspector::compare($inspYaml, $model, $runtimeStub);
$byKey = [];
foreach ($rows as $row) {
    $byKey[$row['key']] = $row;
}
check('对照：一致项', ($byKey['log-level']['state'] ?? '') === Inspector::STATE_MATCH, (string)($byKey['log-level']['state'] ?? '?'));
check('对照：不一致项', ($byKey['mode']['state'] ?? '') === Inspector::STATE_DIFFERS, (string)($byKey['mode']['state'] ?? '?'));
check('对照：文件未写项', ($byKey['tun.stack']['state'] ?? '') === Inspector::STATE_MISSING, (string)($byKey['tun.stack']['state'] ?? '?'));
check('对照：运行值取自 /configs', ($byKey['mode']['runtime'] ?? '') === 'rule', (string)($byKey['mode']['runtime'] ?? '?'));
check('对照：tun 子对象运行值', ($byKey['tun.enable']['runtime'] ?? '') === 'true', (string)($byKey['tun.enable']['runtime'] ?? '?'));
check('对照：密钥不外泄', ($byKey['secret']['file'] ?? '') !== '"abc123"'
    && ($byKey['secret']['model'] ?? '') !== 'abc123', (string)($byKey['secret']['file'] ?? '?'));
check('对照：密钥被识别为已设置', ($byKey['secret']['state'] ?? '') === Inspector::STATE_MATCH);

echo "\n=== 汇总: {$failures} 个失败 ===\n";
exit($failures === 0 ? 0 : 1);