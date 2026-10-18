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

use OPNsense\Mihomo\Config;

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
$noop = Config::patchKeys($original, [
    'mode' => 'rule',
    'allow-lan' => false,
    'tun.enable' => true,
    'log-level' => 'info',
]);
check('全部键都是原值时字节完全不变', $noop === $original);
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

echo "\n=== 汇总: {$failures} 个失败 ===\n";
exit($failures === 0 ? 0 : 1);
