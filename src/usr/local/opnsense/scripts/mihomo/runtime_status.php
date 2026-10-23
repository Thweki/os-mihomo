#!/usr/local/bin/php
<?php

// Read-only configd action: no file writes, service actions, or rule reloads.
require_once '/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/RuntimeStatus.php';
require_once '/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Config.php';

use OPNsense\Mihomo\RuntimeStatus;
use OPNsense\Mihomo\Config;

function read_command(array $command): array
{
    $pipes = [];
    $proc = proc_open($command, [0 => ['file', '/dev/null', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if (!is_resource($proc)) {
        return [1, ''];
    }
    $output = stream_get_contents($pipes[1]);
    stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    return [proc_close($proc), (string)$output];
}

function process_for_pid(string $pid, string $pattern): ?array
{
    if (!ctype_digit($pid) || (int)$pid <= 1) { return null; }
    [$code, $output] = read_command(['/bin/ps', '-ww', '-p', $pid, '-o', 'pid=', '-o', 'rss=', '-o', 'command=']);
    return $code === 0 ? RuntimeStatus::process($output, (int)$pid, $pattern) : null;
}

function read_process(string $file, string $pattern): ?array
{
    return process_for_pid(trim((string)@file_get_contents($file)), $pattern);
}

function core_process(): ?array
{
    // rc.d stores the supervising daemon PID. Verify the actual core command.
    $pattern = '~^(?:/usr/local/bin/)?mihomo\s.*(?:-d\s+|--dir\s+|--dir=)/usr/local/etc/mihomo/?(?:\s|$)~';
    $pid = trim((string)@file_get_contents('/var/run/mihomo.pid'));
    $core = process_for_pid($pid, $pattern);
    if ($core !== null) { return $core; }
    [$code, $pids] = read_command(['/usr/bin/pgrep', '-x', 'mihomo']);
    if ($code === 0) {
        foreach (preg_split('/\s+/', trim($pids)) as $candidate) {
            $core = process_for_pid($candidate, $pattern);
            if ($core !== null) { return $core; }
        }
    }
    return null;
}

$scan = Config::scan();
$tun = (string)($scan['tun.device'] ?? 'tun_mihomo');
[$code, $pf] = read_command(['/sbin/pfctl', '-a', '*', '-sr']);
$log = '';
$stream = @fopen('/var/log/mihomo_sub.log', 'rb');
if ($stream !== false) {
    $size = fstat($stream)['size'];
    if ($size > 262144) {
        fseek($stream, -262144, SEEK_END);
        fgets($stream); // Drop the partial first line.
    }
    $log = (string)stream_get_contents($stream);
    fclose($stream);
}
$task = read_process('/var/run/mihomo-sub-ui.pid', '~(?:/mihomo/sub/sub\.sh|MIHOMO_SERVICE_CMD)~');
echo json_encode([
    'status' => 'ok', 'observed_at' => time(), 'rules_available' => $code === 0,
    'interfaces' => RuntimeStatus::interfaces((string)file_get_contents('/conf/config.xml')),
    'rules' => $code === 0 ? RuntimeStatus::parseRules($pf, $tun) : [],
    'process' => core_process(),
    'subscription' => RuntimeStatus::task($log, $task !== null),
], JSON_INVALID_UTF8_SUBSTITUTE | JSON_UNESCAPED_UNICODE);
