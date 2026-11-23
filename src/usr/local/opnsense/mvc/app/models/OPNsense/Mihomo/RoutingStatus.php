<?php

namespace OPNsense\Mihomo;

/** Shared, read-only evidence for saved bindings and loaded PF rules. */
class RoutingStatus
{
    /** Native floating rules identify their binding by source_net, not interface. */
    public static function configuredRules(\SimpleXMLElement $cfg): array
    {
        $rules = [];
        foreach ($cfg->xpath('./OPNsense/Firewall/Filter/rules/rule') ?: [] as $rule) {
            if ((string)$rule->enabled !== '1' || (string)$rule->action !== 'pass'
                || (string)$rule->gateway !== 'MIHOMO_TUN'
                || !preg_match('/^Mihomo policy \(([a-z0-9_]+)\)$/', (string)$rule->description, $m)
                || (string)$rule->source_net !== $m[1] || (string)$rule->source_not === '1') {
                continue;
            }
            $rules[] = ['interface' => $m[1], 'gateway' => 'MIHOMO_TUN', 'origin' => 'native',
                'complete' => (string)$rule->direction === 'in' && (string)$rule->ipprotocol === 'inet'
                    && in_array((string)$rule->interface, ['', $m[1]], true)
                    && (string)$rule->interfacenot !== '1' && (string)$rule->destination_net === 'any'
                    && (string)$rule->destination_not !== '1' && in_array((string)$rule->protocol, ['', 'any'], true)
                    && (string)$rule->source_port === '' && (string)$rule->destination_port === ''];
        }
        foreach ($cfg->xpath('./filter/rule') ?: [] as $rule) {
            if (isset($rule->disabled) || (string)$rule->type !== 'pass'
                || (string)$rule->gateway !== 'MIHOMO_TUN'
                || stripos((string)$rule->descr, 'Mihomo policy routing') !== 0) {
                continue;
            }
            foreach (explode(',', (string)$rule->interface) as $iface) {
                if ($iface !== '') {
                    $rules[] = ['interface' => $iface, 'gateway' => 'MIHOMO_TUN', 'origin' => 'legacy',
                        'complete' => (string)$rule->ipprotocol === 'inet'
                            && in_array((string)$rule->direction, ['', 'in'], true)
                            && (string)$rule->source->network === $iface && !isset($rule->source->not)
                            && isset($rule->destination->any) && !isset($rule->destination->not)
                            && in_array((string)$rule->protocol, ['', 'any'], true) && !isset($rule->source->port)
                            && !isset($rule->destination->port)];
                }
            }
        }
        return $rules;
    }

    public static function gateway(\SimpleXMLElement $cfg, string $tun): ?array
    {
        foreach ($cfg->xpath('./OPNsense/Gateways/gateway_item') ?: [] as $gateway) {
            $iface = (string)$gateway->interface;
            if ((string)$gateway->name === 'MIHOMO_TUN' && (string)$gateway->disabled !== '1'
                && (string)($cfg->interfaces->$iface->if ?? '') === $tun
                && filter_var((string)$gateway->gateway, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
                return ['device' => $tun, 'address' => (string)$gateway->gateway];
            }
        }
        return null;
    }

    /** Only literal IPv4 scopes are provable here; aliases/negations remain unconfirmed. */
    private static function contains(string $outer, string $inner): bool
    {
        $parse = static function (string $value): ?array {
            $parts = explode('/', $value);
            if (count($parts) > 2 || !filter_var($parts[0], FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)
                || (isset($parts[1]) && (!ctype_digit($parts[1]) || (int)$parts[1] > 32))) {
                return null;
            }
            return [ip2long($parts[0]), isset($parts[1]) ? (int)$parts[1] : 32];
        };
        $target = $parse($inner);
        if ($target === null) { return false; }
        if ($outer === 'any') { return true; }
        $scope = $parse($outer);
        if ($scope === null || $scope[1] > $target[1]) { return false; }
        $mask = $scope[1] === 0 ? 0 : (-1 << (32 - $scope[1]));
        return ($scope[0] & $mask) === ($target[0] & $mask);
    }

    public static function evidence(\SimpleXMLElement $cfg, array $snapshot, string $tun, string $iface, string $source): array
    {
        $configured = array_values(array_filter(self::configuredRules($cfg), fn ($rule) => $rule['interface'] === $iface));
        $gateway = self::gateway($cfg, $tun);
        $available = ($snapshot['status'] ?? '') === 'ok' && ($snapshot['rules_available'] ?? false) === true;
        $device = (string)($cfg->interfaces->$iface->if ?? '');
        $observed = [];
        $complete = false;
        if ($available && $device !== '') {
            foreach ($snapshot['rules'] ?? [] as $rule) {
                $coversSource = self::contains($rule['source'] ?? '', $source);
                $overlapsSource = $coversSource || self::contains($source, $rule['source'] ?? '');
                if (!in_array($rule['direction'] ?? '', ['in', 'any'], true)
                    || !in_array($rule['family'] ?? '', ['IPv4', 'IPv4/IPv6'], true)
                    || !in_array($rule['device'] ?? '', ['', $device], true)
                    || !$overlapsSource
                    || !str_starts_with($rule['next_hop'] ?? '', $tun . ' ')) {
                    continue;
                }
                $observed[] = $rule;
                // Limited protocols, ports, destinations or a stale peer are not full binding evidence.
                if ($coversSource && $gateway !== null && $rule['next_hop'] === $tun . ' ' . $gateway['address']
                    && ($rule['protocols'] ?? []) === ['any'] && ($rule['destination'] ?? '') === 'any'
                    && ($rule['ports'] ?? '') === '*' && ($rule['unrestricted'] ?? false) === true) {
                    $complete = true;
                }
            }
        }
        return ['configured_rules' => $configured, 'gateway' => $gateway !== null,
            'rules_available' => $available, 'observed_rules' => $observed, 'complete' => $complete];
    }

    public static function rows(\SimpleXMLElement $cfg, array $snapshot, string $tun, bool $tunEnabled, array $rows, array $subnets): array
    {
        foreach ($rows as &$row) {
            $row['source'] = $row['source'] !== '' ? $row['source'] : ($subnets[$row['interface']] ?? '');
            $row['evidence'] = self::evidence($cfg, $snapshot, $tun, $row['interface'], $row['source']);
            if ($row['enabled'] !== '1') {
                $row['state'] = 'disabled';
                $row['note'] = gettext('This binding is disabled. Saved or loaded firewall rules may still exist.');
            } elseif (!$tunEnabled) {
                $row['state'] = 'inactive';
                $row['note'] = gettext('TUN is disabled: traffic does not reach mihomo.');
            } elseif ($row['firewall'] === 'manual') {
                $row['state'] = 'manual';
                $row['note'] = gettext('Manual: make sure the interface is policy routed into the TUN device.');
            } elseif (!$row['evidence']['gateway'] || $row['evidence']['configured_rules'] === []) {
                $row['state'] = 'pending';
                $row['note'] = gettext('Waiting for the OPNsense side: interface, gateway and policy routing rule.');
            } elseif (!$row['evidence']['rules_available']) {
                $row['state'] = 'unknown';
                $row['note'] = gettext('The loaded PF ruleset could not be read.');
            } elseif (!$row['evidence']['complete']
                || !self::contains($subnets[$row['interface']] ?? '', $row['source'])
                || !in_array(true, array_column($row['evidence']['configured_rules'], 'complete'), true)) {
                $row['state'] = 'pending';
                $row['note'] = gettext('No complete loaded PF rule was confirmed for this binding.');
            } else {
                $row['state'] = 'active';
                $row['note'] = gettext('A matching PF rule is loaded. Rule order and core policies still affect traffic; reachability is not verified.');
            }
        }
        unset($row);
        return $rows;
    }
}
