<?php

namespace OPNsense\Mihomo;

/** Read-only facts. Rule observations do not imply packet reachability. */
class RuntimeStatus
{
    public static function parseRules(string $output, string $tun): array
    {
        $rows = [];
        foreach (preg_split('/\r?\n/', $output) as $line) {
            if (!preg_match('/^\s*(?:@\d+\s+)?pass\b/', $line)
                || !preg_match('/\broute-to\s+\(\s*([^\s()]+)\s+([^\s()]+)\s*\)/', $line, $next)
                || $next[1] !== $tun) {
                continue;
            }
            preg_match('/\bon\s+([A-Za-z0-9_.:-]+)/', $line, $iface);
            preg_match('/\bproto\s+(\{[^}]+\}|[^\s]+)/', $line, $proto);
            $protocols = preg_split('/[\s,{}]+/', $proto[1] ?? 'any', -1, PREG_SPLIT_NO_EMPTY);
            $protocols = array_map(fn ($p) => ['6' => 'tcp', '17' => 'udp'][$p] ?? strtolower($p), $protocols);
            $condition = preg_split('/\s+(?:flags|keep|modulate|synproxy|label|tag|rtable|dnpipe|dnqueue)\b/', $line, 2)[0];
            preg_match('/\bfrom\s+(.+?)\s+to\s+(.+)$/', $condition, $scope);
            $destination = trim($scope[2] ?? '');
            preg_match('/\bport\s+(.+)$/', $destination, $ports);
            $rows[] = [
                'device' => $iface[1] ?? '',
                'family' => preg_match('/\binet6\b/', $line) ? 'IPv6' : (preg_match('/\binet\b/', $line) ? 'IPv4' : 'IPv4/IPv6'),
                'direction' => preg_match('/\bpass\s+out\b/', $line) ? 'out' : (preg_match('/\bpass\s+in\b/', $line) ? 'in' : 'any'),
                'protocols' => array_values($protocols),
                'source' => trim($scope[1] ?? ''),
                'destination' => $destination,
                'ports' => trim($ports[1] ?? '*'),
                'next_hop' => $next[1] . ' ' . $next[2],
            ];
        }
        return $rows;
    }

    public static function interfaces(string $xml): array
    {
        $root = simplexml_load_string($xml, \SimpleXMLElement::class, LIBXML_NONET);
        if ($root === false || !isset($root->interfaces)) {
            return [];
        }
        $result = [];
        foreach ($root->interfaces->children() as $key => $node) {
            $device = trim((string)$node->if);
            if ($device === '' || $device === 'lo0' || (string)$node->internal_dynamic === '1'
                || !filter_var((string)$node->ipaddr, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
                continue;
            }
            $result[] = ['interface' => $key, 'device' => $device,
                'description' => trim((string)$node->descr) ?: $key];
        }
        return $result;
    }

    public static function task(string $log, bool $running): array
    {
        $submitted = null;
        $finished = null;
        $lastSuccess = null;
        $lastEvent = '';
        $exit = null;
        foreach (preg_split('/\r?\n/', $log) as $line) {
            if (preg_match('/^\[([^]]+)\] Subscription task submitted\b/', $line, $m)) {
                $submitted = $m[1];
                $lastEvent = 'submitted';
            } elseif (preg_match('/^\[([^]]+)\] Subscription task finished \(exit=(\d+)\)/', $line, $m)) {
                $finished = $m[1];
                $exit = (int)$m[2];
                $lastEvent = 'finished';
                if ($exit === 0) {
                    $lastSuccess = $finished;
                }
            }
        }
        $state = $running ? 'running' : ($lastEvent === 'finished' ? ($exit === 0 ? 'success' : 'failed')
            : ($lastEvent === 'submitted' ? 'incomplete' : (trim($log) === '' ? 'idle' : 'unknown')));
        return ['state' => $state, 'submitted' => $submitted, 'finished' => $finished,
            'last_success' => $lastSuccess, 'exit_code' => $exit];
    }

    public static function process(string $output, int $pid, string $pattern): ?array
    {
        if ($pid <= 1 || !preg_match('/^\s*(\d+)\s+(\d+)\s+(.+)$/s', trim($output), $match)
            || (int)$match[1] !== $pid || !preg_match($pattern, $match[3])) {
            return null;
        }
        return ['pid' => $pid, 'rss' => (int)$match[2] * 1024];
    }
}
