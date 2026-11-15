<?php
/** Injected command results and isolated CLI runs; never touches appliance files or PF. */
require dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/RuntimeStatus.php';
require dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/NetworkApply.php';
use OPNsense\Mihomo\NetworkApply;

function expectNetwork(bool $condition, string $label): void
{
    if (!$condition) { throw new RuntimeException($label); }
}
function networkConfig(array $bindings = ['lan', 'opt2']): string
{
    $rules = '';
    foreach ($bindings as $iface) {
        $rules .= '<rule><enabled>1</enabled><source_net>' . $iface . '</source_net>'
            . '<gateway>MIHOMO_TUN</gateway><description>Mihomo policy (' . $iface . ')</description></rule>';
    }
    return '<opnsense><interfaces>'
        . '<lo0><if>lo0</if></lo0>'
        . '<lan><if>vtnet1</if><ipaddr>192.0.2.1</ipaddr><subnet>24</subnet></lan>'
        . '<opt2><if>vtnet2</if><ipaddr>203.0.113.1</ipaddr><subnet>24</subnet></opt2>'
        . '<opt3><if>tun_mihomo</if></opt3></interfaces><OPNsense><Gateways><gateway_item>'
        . '<interface>opt3</interface><gateway>198.18.0.2</gateway><name>MIHOMO_TUN</name>'
        . '</gateway_item></Gateways><Firewall><Filter><rules>' . $rules
        . '</rules></Filter></Firewall></OPNsense></opnsense>';
}
$lan = 'pass in quick route-to (tun_mihomo 198.18.0.2) inet from 192.0.2.0/24 to any keep state label "fixture-lan"';
$opt2 = 'pass in quick route-to (tun_mihomo 198.18.0.2) inet from 203.0.113.0/24 to any keep state label "fixture-opt2"';
$both = $lan . "\n" . $opt2;
$xml = networkConfig();
$cases = [
    ['all bindings', ['lan', 'opt2'], [0, 'OK'], [0, $both], 'ok'],
    ['reload exit failure with old PF rules', ['lan', 'opt2'], [1, 'OK'], [0, $both], 'failed'],
    ['reload reports failure with zero exit', ['lan'], [0, 'failed'], [0, $lan], 'failed'],
    ['empty reload response', [], [0, ''], [0, ''], 'failed'],
    ['PF exit failure with plausible output', ['lan'], [0, 'OK'], [1, $lan], 'failed'],
    ['PF failure cannot prove unbind', [], [0, 'OK'], [1, ''], 'failed'],
    ['second binding missing', ['lan', 'opt2'], [0, 'OK'], [0, $lan], 'failed'],
    ['duplicate cannot substitute for missing binding', ['lan', 'opt2'], [0, 'OK'], [0, $lan . "\n" . $lan], 'failed'],
    ['no binding loaded', ['lan'], [0, 'OK'], [0, ''], 'failed'],
    ['partial removal is still loaded', ['lan'], [0, 'OK'], [0, $both], 'failed'],
    ['partial removal confirmed', ['lan'], [0, 'OK'], [0, $lan], 'ok'],
    ['unbind still loaded', [], [0, 'OK'], [0, $lan], 'failed'],
    ['unbind confirmed', [], [0, 'OK'], [0, ''], 'ok'],
    ['unrelated tunnel is not a binding', ['lan'], [0, 'OK'], [0, str_replace('tun_mihomo', 'another_tun', $lan)], 'failed'],
    ['wrong peer', ['lan'], [0, 'OK'], [0, str_replace('198.18.0.2', '198.18.0.3', $lan)], 'failed'],
    ['wrong source', ['lan'], [0, 'OK'], [0, $opt2], 'failed'],
    ['wrong scoped interface', ['lan'], [0, 'OK'], [0, str_replace('quick route-to', 'quick on vtnet2 route-to', $lan)], 'failed'],
    ['correct scoped interface', ['lan'], [0, 'OK'], [0, str_replace('quick route-to', 'quick on vtnet1 route-to', $lan)], 'ok'],
    ['limited protocol cannot prove binding', ['lan'], [0, 'OK'], [0, str_replace('inet from', 'inet proto tcp from', $lan)], 'failed'],
    ['limited destination cannot prove binding', ['lan'], [0, 'OK'], [0, str_replace('to any', 'to 203.0.113.0/24', $lan)], 'failed'],
    ['outbound is not inbound binding', ['lan'], [0, 'OK'], [0, str_replace('pass in', 'pass out', $lan)], 'failed'],
];
foreach ($cases as [$label, $interfaces, $reload, $pf, $status]) {
    $calls = [];
    $result = NetworkApply::reload($xml, $interfaces, function ($command) use (&$calls, $reload, $pf) {
        $calls[] = $command;
        if ($command === 'configctl filter reload') { return $reload; }
        expectNetwork($command === 'pfctl -sr', 'PF is inspected directly, without a pipeline');
        return $pf;
    });
    expectNetwork($result['status'] === $status, $label);
    if ($status === 'failed') { expectNetwork(!empty($result['message']), $label . ': explicit failure'); }
    if ($reload !== [0, 'OK']) { expectNetwork(count($calls) === 1, $label . ': reload failure cannot be overridden by PF'); }
}
expectNetwork(NetworkApply::bindings($xml) === ['lan', 'opt2'], 'Rollback uses saved floating bindings');
expectNetwork(NetworkApply::bindings(str_replace('<enabled>1</enabled>', '<enabled>0</enabled>', $xml)) === [], 'Disabled rules are not restored bindings');
$legacy = str_replace('</opnsense>', '<filter><rule><interface>lan</interface><gateway>MIHOMO_TUN</gateway><descr>Mihomo policy routing (lan)</descr></rule></filter></opnsense>', networkConfig([]));
expectNetwork(NetworkApply::bindings($legacy) === ['lan'], 'Rollback supports legacy inline bindings');

// Run the production CLI in a temporary filesystem with PATH command shims.
// Only fixed filesystem roots are relocated; no production logic is replaced.
$scratch = sys_get_temp_dir() . '/mihomo-net-test-' . bin2hex(random_bytes(6));
mkdir($scratch, 0700);
$staging = '/tmp/mihomo-' . bin2hex(random_bytes(8));
$source = dirname(__DIR__) . '/src/usr/local/opnsense/scripts/mihomo/policy_net.php';
$script = str_replace(
    ["dirname(__DIR__, 2)", '/conf/'],
    [var_export(dirname($source, 3), true), $scratch . '/'],
    file_get_contents($source)
);
file_put_contents($scratch . '/policy_net.php', $script);
$shim = <<<'SHIM'
<?php
$command = basename($argv[0]);
if ($command === 'ifconfig') { echo "inet 198.18.0.1 netmask 0xfffffffc\n"; exit(0); }
$path = __DIR__ . '/outcomes.json';
$queue = json_decode(file_get_contents($path), true);
file_put_contents(__DIR__ . '/calls', $command . ' ' . implode(' ', array_slice($argv, 1)) . "\n", FILE_APPEND);
if (empty($queue[$command])) { fwrite(STDERR, 'Unexpected command'); exit(99); }
[$rc, $output] = array_shift($queue[$command]);
file_put_contents($path, json_encode($queue));
echo $output;
exit($rc);
SHIM;
foreach (['configctl', 'pfctl', 'ifconfig'] as $command) {
    file_put_contents($scratch . '/' . $command, '#!' . PHP_BINARY . "\n" . $shim);
    chmod($scratch . '/' . $command, 0700);
}
function runNetworkCli(string $action, array $payload, string $current, array $outcomes, ?string $backup = null): array
{
    global $scratch, $staging;
    foreach (glob($scratch . '/config.xml*') as $path) { unlink($path); }
    file_put_contents($scratch . '/config.xml', $current);
    if ($backup !== null) { file_put_contents($scratch . '/config.xml.mihomo-bak.20000101_000000', $backup); }
    file_put_contents($scratch . '/outcomes.json', json_encode($outcomes));
    file_put_contents($scratch . '/calls', '');
    file_put_contents($staging, json_encode($payload));
    $command = [PHP_BINARY, $scratch . '/policy_net.php', $action];
    if ($action === 'apply') { $command[] = $staging; }
    $pipes = [];
    $env = getenv();
    $env['PATH'] = $scratch . PATH_SEPARATOR . ($env['PATH'] ?? '');
    $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, null, $env);
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    $exit = proc_close($process);
    expectNetwork($exit === 0 && $stderr === '', 'CLI must preserve structured results for configd: ' . $stderr);
    $result = json_decode($stdout, true);
    expectNetwork(is_array($result), 'CLI returns JSON');
    if ($action === 'apply') { expectNetwork(!is_file($staging), 'CLI cleans staging files'); }
    return $result;
}
try {
    foreach ($cases as [$label, $interfaces, $reload, $pf, $status]) {
        $result = runNetworkCli('apply', ['interfaces' => $interfaces, 'verify_only' => true], $xml,
            ['configctl' => [$reload], 'pfctl' => [$pf]]);
        expectNetwork($result['status'] === $status, 'CLI verification: ' . $label);
    }
    foreach ([[[1, 'failed'], [0, $both], 'failed'], [[0, 'OK'], [1, $both], 'failed'],
        [[0, 'OK'], [0, $lan], 'failed'], [[0, 'OK'], [0, $both], 'ok']] as [$reload, $pf, $status]) {
        $result = runNetworkCli('rollback', [], networkConfig([]), ['configctl' => [$reload], 'pfctl' => [$pf]], $xml);
        expectNetwork($result['status'] === $status, 'Explicit rollback verifies both reload and every restored binding');
        expectNetwork(file_get_contents($scratch . '/config.xml') === $xml, 'Rollback restores saved bytes');
    }
    foreach ([$lan => 'failed', '' => 'ok'] as $pf => $status) {
        $result = runNetworkCli('rollback', [], $xml, ['configctl' => [[0, 'OK']], 'pfctl' => [[0, $pf]]], networkConfig([]));
        expectNetwork($result['status'] === $status, 'Rollback to empty bindings verifies removal');
    }
    $result = runNetworkCli('apply', ['interfaces' => ['lan', 'opt2']], $xml,
        ['configctl' => [[1, 'failed']], 'pfctl' => []]);
    expectNetwork($result['status'] === 'failed', 'Unchanged XML still checks reload');
    $result = runNetworkCli('apply', ['interfaces' => ['lan', 'opt2']], $xml,
        ['configctl' => [[0, 'OK']], 'pfctl' => [[0, $lan]]]);
    expectNetwork($result['status'] === 'failed', 'Unchanged XML still checks every loaded binding');
    $result = runNetworkCli('apply', ['interfaces' => ['lan', 'opt2'], 'verify' => false], $xml,
        ['configctl' => [], 'pfctl' => []]);
    expectNetwork($result['status'] === 'ok' && file_get_contents($scratch . '/calls') === '', 'Preparation stage does not reload');

    // Removing the TUN gateway changes XML, exercising automatic restoration on failure.
    foreach ([[[0, 'OK'], [0, $both], 'ok'], [[1, 'failed'], [0, $both], 'failed'],
        [[0, 'OK'], [1, ''], 'failed'], [[0, 'OK'], [0, $lan], 'failed']] as [$reload, $pf, $status]) {
        $result = runNetworkCli('apply', ['interfaces' => []], $xml,
            ['configctl' => [[0, 'OK'], $reload], 'pfctl' => [[0, $lan], $pf]]);
        expectNetwork($result['status'] === 'failed', 'Stale loaded binding fails full apply');
        expectNetwork($result['rollback']['status'] === $status, 'Automatic rollback reports its own verified outcome');
        expectNetwork(file_get_contents($scratch . '/config.xml') === $xml, 'Automatic rollback restores saved bytes');
    }
    $result = runNetworkCli('apply', ['interfaces' => []], $xml,
        ['configctl' => [[1, 'failed'], [0, 'OK']], 'pfctl' => [[0, $both]]]);
    expectNetwork($result['status'] === 'failed' && $result['rollback']['status'] === 'ok', 'Full apply reload failure survives successful rollback');
    $result = runNetworkCli('apply', ['interfaces' => []], $xml,
        ['configctl' => [[0, 'OK']], 'pfctl' => [[0, '']]]);
    expectNetwork($result['status'] === 'ok' && !isset($result['rollback']), 'Full apply confirms removal');
} finally {
    if (is_file($staging)) { unlink($staging); }
    foreach (glob($scratch . '/*') as $path) { unlink($path); }
    rmdir($scratch);
}
echo "Network reload, every loaded binding, removal and rollback: passed\n";
