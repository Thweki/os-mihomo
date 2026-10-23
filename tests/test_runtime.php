<?php
require dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/RuntimeStatus.php';
use OPNsense\Mihomo\RuntimeStatus;
function expect($condition, $label) {
    if (!$condition) { throw new RuntimeException($label); }
}
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
expect(RuntimeStatus::process('42 1024 /usr/local/bin/mihomo -d /example', 42, '~^(?:/usr/local/bin/)?mihomo(?:\s|$)~')['rss'] === 1048576, 'RSS KiB to bytes');
expect(RuntimeStatus::process('42 1024 /bin/unrelated', 42, '~^(?:/usr/local/bin/)?mihomo(?:\s|$)~') === null, 'Reject reused PID');
expect(RuntimeStatus::process('42 512 /usr/sbin/daemon /usr/local/bin/mihomo', 42, '~^(?:/usr/local/bin/)?mihomo(?:\s|$)~') === null, 'Do not report supervisor RSS as core memory');
$xml = '<opnsense><interfaces><lan><if>vtnet1</if><descr>Example LAN</descr><ipaddr>192.0.2.1</ipaddr></lan><wan><if>vtnet0</if><ipaddr>dhcp</ipaddr></wan></interfaces></opnsense>';
expect(count(RuntimeStatus::interfaces($xml)) === 1, 'Static client interface discovery');
echo "Runtime rules, task records and process identity: all checks passed\n";
