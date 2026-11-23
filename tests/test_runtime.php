<?php
require dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/RuntimeStatus.php';
use OPNsense\Mihomo\RuntimeStatus;
function expect($condition, $label) {
    if (!$condition) { throw new RuntimeException($label); }
}
// A child must be able to emit more diagnostics than a pipe can hold before
// closing stdout. Nonblocking writes turn the old deadlock into a finite failure,
// so this regression needs neither a timeout utility nor the pcntl extension.
$noisyChild = <<<'PHP'
fwrite(STDOUT, "before\n");
stream_set_blocking(STDERR, false);
$chunk = str_repeat('x', 65536);
for ($i = 0; $i < 64; $i++) {
    $offset = 0;
    while ($offset < strlen($chunk)) {
        $written = fwrite(STDERR, substr($chunk, $offset));
        if ($written === false || $written === 0) { exit(91); }
        $offset += $written;
    }
}
fwrite(STDOUT, "after\n");
PHP;
expect(RuntimeStatus::readCommand([PHP_BINARY, '-r', $noisyChild]) === [0, "before\nafter\n"],
    'Large stderr cannot block runtime polling or contaminate stdout');
expect(RuntimeStatus::readCommand([PHP_BINARY, '-r', 'fwrite(STDERR, "diagnostic"); echo "partial"; exit(7);']) === [7, 'partial'],
    'Failed commands retain their exit status and stdout');
expect(RuntimeStatus::readCommand([PHP_BINARY, '-r', 'exit(0);']) === [0, ''],
    'Empty successful output remains empty');
$pf = <<<'RULES'
pass in quick on vtnet2 route-to (tun_mihomo 198.51.100.2) inet proto tcp from 203.0.113.0/24 to ! 192.0.2.0/24 flags S/SA keep state label "example"
pass in quick on vtnet2 route-to (tun_mihomo 198.51.100.2) inet proto udp from any to any port = { 53, 500, 4500 } keep state
pass in on vtnet3 route-to (other_tun 192.0.2.2) inet from any to any
block in on vtnet2 inet from any to any
pass in quick route-to (tun_mihomo 198.51.100.2) inet6 proto 6 from any to any
RULES;
$rules = RuntimeStatus::parseRules($pf, 'tun_mihomo');
expect(count($rules) === 3, 'Include only pass rules to this TUN');
expect($rules[0]['ports'] === '*' && $rules[0]['destination'] === '! 192.0.2.0/24', 'Preserve destination exceptions');
expect($rules[1]['protocols'] === ['udp'] && str_contains($rules[1]['ports'], '4500'), 'Preserve limited UDP coverage');
expect($rules[2]['device'] === '' && $rules[2]['family'] === 'IPv6' && $rules[2]['protocols'] === ['tcp'], 'Keep unscoped and IPv6 rules explicit');
$log = "[2026-01-01 01:00:00] Subscription task submitted\n[2026-01-01 01:01:00] Subscription task finished (exit=0).\n";
expect(RuntimeStatus::task($log, false)['state'] === 'success', 'Completed success');
$failed = $log . "[2026-01-02 01:01:00] Subscription task finished (exit=1).\n";
expect(RuntimeStatus::task($failed, false)['state'] === 'failed' && RuntimeStatus::task($failed, false)['last_success'] === '2026-01-01 01:01:00', 'Last success survives later failure');
expect(RuntimeStatus::task($failed . "[2026-01-03 01:00:00] Subscription task submitted\n", false)['state'] === 'incomplete', 'Missing finish is not success');
expect(RuntimeStatus::task('', true)['state'] === 'running', 'A verified live worker wins over rotated logs');
expect(RuntimeStatus::task('', false)['state'] === 'idle', 'Empty log');
expect(RuntimeStatus::task('legacy output', false)['state'] === 'unknown', 'Unstructured output is not a known success');
expect(RuntimeStatus::process('42 1024 90 /usr/local/bin/mihomo -d /example', 42, '~^(?:/usr/local/bin/)?mihomo(?:\s|$)~')['rss'] === 1048576, 'RSS KiB to bytes');
expect(RuntimeStatus::process('42 1024 90 /bin/unrelated', 42, '~^(?:/usr/local/bin/)?mihomo(?:\s|$)~') === null, 'Reject reused PID');
expect(RuntimeStatus::process('42 512 90 /usr/sbin/daemon /usr/local/bin/mihomo', 42, '~^(?:/usr/local/bin/)?mihomo(?:\s|$)~') === null, 'Do not report supervisor RSS as core memory');
$pattern = '~^(?:/usr/local/bin/)?mihomo(?:\s|$)~';
foreach ([0, 59, 3600, 90061, 31536000] as $seconds) {
    $process = RuntimeStatus::process("42 1024 $seconds /usr/local/bin/mihomo -d /example", 42, $pattern);
    expect($process['uptime_seconds'] === $seconds, 'Uptime is actual core age, including zero and multiple days');
}
foreach (['-', '-1', '1.5', '999999999999999999999999999'] as $invalid) {
    $process = RuntimeStatus::process("42 1024 $invalid /usr/local/bin/mihomo -d /example", 42, $pattern);
    expect($process['uptime_seconds'] === null && $process['rss'] === 1048576, 'Invalid age is unknown without losing RSS');
}
expect(RuntimeStatus::process('43 1024 90 /usr/local/bin/mihomo', 42, $pattern) === null, 'PID mismatch has no uptime');
expect(RuntimeStatus::process('', 42, $pattern) === null, 'Missing process has no uptime');
expect(RuntimeStatus::process('1 1024 90 /usr/local/bin/mihomo', 1, $pattern) === null, 'Reject init PID');
expect(RuntimeStatus::lastReload("1700000000\n", 1700000001) === 1700000000, 'Read recorded reload timestamp');
expect(RuntimeStatus::lastReload('1700000001', 1700000001) === 1700000001, 'Accept current second');
foreach (['', '0', '-1', '1700000002', '1700000000junk', '1700000000\n1700000001', '999999999999999999999'] as $invalid) {
    expect(RuntimeStatus::lastReload($invalid, 1700000001) === null, 'Missing, malformed and future markers are unknown');
}
$xml = '<opnsense><interfaces><lan><if>vtnet1</if><descr>Example LAN</descr><ipaddr>192.0.2.1</ipaddr></lan><wan><if>vtnet0</if><ipaddr>dhcp</ipaddr></wan></interfaces></opnsense>';
expect(count(RuntimeStatus::interfaces($xml)) === 1, 'Static client interface discovery');
echo "Runtime command I/O, rules, task records and process identity: all checks passed\n";
