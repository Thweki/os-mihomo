<?php

namespace OPNsense\Mihomo;

/** Verify loaded PF state, not just the saved configuration or a global rule count. */
class NetworkApply
{
    /** Bindings to restore come from the saved firewall rules, not the current policy rows. */
    public static function bindings(string $xml): array
    {
        $root = self::config($xml);
        $interfaces = [];
        foreach ($root->xpath('/opnsense/OPNsense/Firewall/Filter/rules/rule') as $rule) {
            if ((string)$rule->enabled === '1' && (string)$rule->gateway === 'MIHOMO_TUN'
                && preg_match('/^Mihomo policy \(([^)]+)\)$/', (string)$rule->description, $match)) {
                $interfaces[] = $match[1];
            }
        }
        foreach ($root->xpath('/opnsense/filter/rule') as $rule) {
            if (!isset($rule->disabled) && (string)$rule->gateway === 'MIHOMO_TUN'
                && str_contains((string)$rule->descr, 'Mihomo policy routing')) {
                $interfaces[] = (string)$rule->interface;
            }
        }
        return array_values(array_unique($interfaces));
    }

    /** The runner returns [exit code, output]; injectable without executing appliance commands. */
    public static function reload(string $xml, array $interfaces, callable $run): array
    {
        $messages = [];
        try {
            [$rc, $output] = $run('configctl filter reload');
            if ($rc !== 0 || !in_array(strtolower(trim($output)), ['ok', 'ok.'], true)) {
                throw new \RuntimeException('Filter reload was not confirmed (exit ' . $rc . ').');
            }
            $messages[] = 'filter reload: OK';
            // No pipeline: a failed pfctl must never become an empty, successful unbind.
            [$rc, $output] = $run('pfctl -sr');
            if ($rc !== 0) {
                throw new \RuntimeException('Unable to inspect loaded PF rules (exit ' . $rc . ').');
            }
            $root = self::config($xml);
            $gateway = '';
            foreach ($root->xpath('/opnsense/OPNsense/Gateways/gateway_item') as $item) {
                if ((string)$item->name === 'MIHOMO_TUN') {
                    $gateway = (string)$item->gateway;
                }
            }
            $expected = [];
            foreach (array_unique($interfaces) as $iface) {
                $node = $root->interfaces->{$iface};
                $source = self::network((string)$node->ipaddr . '/' . (string)$node->subnet);
                if ($source === null || (string)$node->if === ''
                    || !filter_var($gateway, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
                    throw new \RuntimeException('Cannot verify binding for interface ' . $iface . '.');
                }
                $expected[$iface] = ['source' => $source, 'device' => (string)$node->if];
            }
            $loaded = [];
            $unexpected = [];
            foreach (RuntimeStatus::parseRules($output, 'tun_mihomo') as $rule) {
                $matched = false;
                foreach ($expected as $iface => $binding) {
                    if (self::network($rule['source']) !== $binding['source']
                        || ($rule['device'] !== '' && $rule['device'] !== $binding['device'])
                        || $rule['next_hop'] !== 'tun_mihomo ' . $gateway) {
                        continue;
                    }
                    $matched = true;
                    if ($rule['family'] !== 'IPv6' && $rule['direction'] !== 'out'
                        && $rule['protocols'] === ['any'] && $rule['destination'] === 'any') {
                        $loaded[$iface] = true;
                    }
                }
                if (!$matched) {
                    $unexpected[] = $rule['source'] . ' via ' . $rule['next_hop'];
                }
            }
            $missing = array_diff(array_keys($expected), array_keys($loaded));
            if ($missing !== [] || $unexpected !== []) {
                throw new \RuntimeException('Loaded PF bindings do not match the requested set.'
                    . ($missing !== [] ? ' Missing: ' . implode(', ', $missing) . '.' : '')
                    . ($unexpected !== [] ? ' Unexpected/stale TUN rules: ' . count($unexpected) . '.' : ''));
            }
            $messages[] = 'loaded PF bindings verified: ' . ($interfaces === [] ? 'none (unbound)' : implode(', ', $interfaces));
            return ['status' => 'ok', 'messages' => $messages];
        } catch (\Throwable $error) {
            return ['status' => 'failed', 'message' => $error->getMessage(), 'messages' => $messages];
        }
    }

    private static function config(string $xml): \SimpleXMLElement
    {
        $root = simplexml_load_string($xml, \SimpleXMLElement::class, LIBXML_NONET);
        if ($root === false) {
            throw new \RuntimeException('Unable to read network configuration for verification.');
        }
        return $root;
    }

    private static function network(string $source): ?string
    {
        $parts = explode('/', $source);
        $ip = $parts[0];
        $bits = $parts[1] ?? '32';
        if (count($parts) > 2 || !filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)
            || !ctype_digit($bits) || (int)$bits > 32) {
            return null;
        }
        $mask = (int)$bits === 0 ? 0 : (-1 << (32 - (int)$bits));
        return long2ip(ip2long($ip) & $mask) . '/' . (int)$bits;
    }
}
