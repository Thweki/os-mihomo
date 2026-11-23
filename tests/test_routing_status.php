<?php
/** B7: read-only routing/safety contracts with fresh-install and migration fixtures. */
namespace OPNsense\Base {
    class ApiMutableModelControllerBase {
        public $model;
        public function getModel() { return $this->model; }
    }
}
namespace OPNsense\Core {
    class Config {
        public static $fixture;
        public static function getInstance() { return new self(); }
        public function object() { return self::$fixture; }
    }
    class Backend {
        public static array $calls = [];
        public static string $output = '';
        public static bool $failRuntime = false;
        public function configdRun($action) {
            self::$calls[] = $action;
            if ($action === 'mihomo status') { return 'mihomo is not running'; }
            if (self::$failRuntime) { throw new \RuntimeException('Runtime read unavailable'); }
            if ($action !== 'mihomo runtime-status') { throw new \RuntimeException('Unexpected action'); }
            return self::$output;
        }
    }
}
namespace OPNsense\Mihomo {
    function is_readable($path) { return false; } // No appliance boot configuration in fixture tests.
    class Inspector { public static function ipv6Allowed($raw) { return false; } }
    class Config {
        public const FILE = '/fixture/config.yaml';
        public static function exists() { return true; }
        public static function hasPlaceholderProxies() { return false; }
        public static function rawText() { return ''; }
        public static function secret() { return ''; }
        public static bool $tun = true;
        public static function interfaceSubnets() { return ['lan' => '192.0.2.0/24', 'opt1' => '203.0.113.0/24']; }
        public static function bool($key) { return $key === 'tun.enable' && self::$tun; }
        public static function scan() { return ['tun.device' => 'tun_mihomo']; }
    }
}
namespace {
    use OPNsense\Mihomo\RoutingStatus;
    use OPNsense\Mihomo\RuntimeStatus;
    use OPNsense\Mihomo\Safety;
    use OPNsense\Mihomo\Config;
    use OPNsense\Core\Backend;
    use OPNsense\Core\Config as CoreConfig;

    if (!function_exists('gettext')) {
        function gettext(string $message): string { return $message; }
    }

    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    foreach (['RuntimeStatus', 'RoutingStatus', 'Safety', 'RequestParamsTrait'] as $name) {
        require $app . 'models/OPNsense/Mihomo/' . $name . '.php';
    }
    require $app . 'controllers/OPNsense/Mihomo/Api/RoutingController.php';
    function expect($condition, $label) {
        if (!$condition) { throw new \RuntimeException($label); }
    }
    function fixture($name) { return simplexml_load_file(__DIR__ . '/fixtures/routing/' . $name . '.xml'); }
    function snapshot($pf) {
        return ['status' => 'ok', 'rules_available' => true, 'rules' => RuntimeStatus::parseRules($pf, 'tun_mihomo')];
    }
    function row($iface = 'lan', $source = '') {
        return ['enabled' => '1', 'interface' => $iface, 'source' => $source, 'scope' => 'all', 'target' => 'Proxy', 'firewall' => 'auto', 'descr' => ''];
    }
    function status($cfg, $live, $rows = null) {
        CoreConfig::$fixture = $cfg;
        Backend::$output = is_array($live) ? json_encode($live) : $live;
        $list = new class($rows ?? [row(), row('opt1')]) {
            public $items;
            public function __construct($rows) { $this->items = array_map(fn ($row) => (object)$row, $rows); }
            public function iterateItems() { return $this->items; }
        };
        $controller = new \OPNsense\Mihomo\Api\RoutingController();
        $controller->model = (object)['policyRouting' => (object)['rule' => $list]];
        return $controller->statusAction();
    }
    function warnings($cfg, $live) {
        return Safety::routingItems($cfg, $live, 'tun_mihomo', Config::interfaceSubnets());
    }
    $native = snapshot(file_get_contents(__DIR__ . '/fixtures/routing/native.pf'));
    $legacy = snapshot(file_get_contents(__DIR__ . '/fixtures/routing/legacy.pf'));
    $empty = snapshot('');
    expect(status(fixture('fresh'), $empty)['rows'][0]['state'] === 'pending', 'Fresh install is pending');
    expect(warnings(fixture('fresh'), $empty) === [], 'Fresh install has no invented policy exposure');
    foreach (['legacy' => $legacy, 'native' => $native] as $name => $live) {
        $cfg = fixture($name);
        $result = status($cfg, $live);
        expect($result['gateway'] && $result['firewall_rule'], "$name inventory found");
        expect($result['rows'][0]['state'] === 'active', "$name LAN rule observed");
        expect($result['rows'][1]['state'] === 'pending', "$name LAN never activates Guests");
        expect(count(warnings($cfg, $live)) === 1, "$name safety agrees with binding inventory");
        expect(str_contains(warnings($cfg, $live)[0]['detail'], 'Clients (lan)'), "$name warning identifies affected interface");
        expect(status($cfg, $empty)['rows'][0]['state'] === 'pending', "$name saved rule is not runtime evidence");
        expect(count(warnings($cfg, $empty)) === 1, "$name saved exposure still warned without live rule");
        foreach (['', 'null', 'false', '1', '{broken', '{"status":"failed"}'] as $unavailable) {
            expect(status($cfg, $unavailable)['rows'][0]['state'] === 'unknown', "$name unavailable PF never active");
        }
    }
    // Before and after migration must present the same binding and safety result.
    expect(status(fixture('legacy'), $legacy)['rows'][0]['state'] === status(fixture('native'), $native)['rows'][0]['state'], 'Migration preserves observed binding');
    expect(warnings(fixture('legacy'), $legacy) === warnings(fixture('native'), $native), 'Migration preserves safety warning');
    $mixed = simplexml_load_string(str_replace('</opnsense>', fixture('legacy')->filter->asXML() . '</opnsense>', fixture('native')->asXML()));
    expect(count(warnings($mixed, $native)) === 1, 'Mixed migration inventory deduplicates safety warnings');

    $cfg = fixture('native');
    $rule = $cfg->OPNsense->Firewall->Filter->rules->rule[1];
    foreach (['enabled' => '0', 'action' => 'block', 'gateway' => 'OTHER', 'source_net' => 'opt1', 'description' => 'Unrelated'] as $field => $value) {
        $old = (string)$rule->$field;
        $rule->$field = $value;
        expect(!status($cfg, $native)['firewall_rule'], "Invalid native $field is not a configured binding");
        expect(status($cfg, $native)['rows'][0]['state'] === 'pending', "Stale PF cannot hide native $field mismatch");
        $rule->$field = $old;
    }
    $rule->direction = 'out';
    expect(status($cfg, $native)['rows'][0]['state'] === 'pending', 'Edited native direction does not reuse stale incoming evidence');
    $rule->direction = 'in';
    $oldCfg = fixture('legacy');
    $oldCfg->filter->rule[1]->addChild('disabled');
    expect(!status($oldCfg, $legacy)['firewall_rule'], 'Disabled legacy rule ignored');
    $cfg->OPNsense->Gateways->gateway_item->disabled = '1';
    expect(status($cfg, $native)['rows'][0]['state'] === 'pending', 'Disabled gateway not ready');
    $cfg = fixture('native');
    $cfg->interfaces->opt2->if = 'other_tun';
    expect(status($cfg, $native)['rows'][0]['state'] === 'pending', 'Wrong gateway device not ready');

    $base = 'pass in quick route-to (tun_mihomo 198.18.0.2) inet from 192.0.2.0/24 to any';
    foreach ([
        str_replace('192.0.2.0/24', '203.0.113.0/24', $base),
        str_replace('198.18.0.2', '198.18.0.6', $base),
        str_replace('tun_mihomo', 'other_tun', $base),
        str_replace('quick route-to', 'quick on vtnet2 route-to', $base),
        str_replace('quick route-to', 'quick on ! vtnet1 route-to', $base),
        str_replace('quick route-to', 'quick on { vtnet2, vtnet3 } route-to', $base),
        str_replace('pass in', 'pass out', $base),
        str_replace('inet from', 'inet6 from', $base),
        str_replace('inet from', 'inet proto tcp from', $base),
        str_replace('to any', 'to any port = 443', $base),
        str_replace('to any', 'to ! 203.0.113.0/24', $base),
        str_replace('192.0.2.0/24', '<clients>', $base),
        str_replace('192.0.2.0/24', '! 192.0.2.0/24', $base),
        $base . ' tagged SPECIAL',
        $base . ' keep state tagged SPECIAL',
        str_replace('192.0.2.0/24', '192.0.2.42', $base),
    ] as $restricted) {
        expect(status(fixture('native'), snapshot($restricted))['rows'][0]['state'] === 'pending', 'Other or restricted scope never proves full binding');
    }
    expect(count(warnings(fixture('fresh'), snapshot(str_replace('192.0.2.0/24', '192.0.2.42', $base)))) === 1, 'Stale host-only forwarding still warns');
    expect(status(fixture('native'), $native, [row('lan', '192.0.2.42')])['rows'][0]['state'] === 'active', 'Source host within floating subnet matches');
    expect(status(fixture('native'), $native, [row('lan', '203.0.113.42')])['rows'][0]['state'] === 'pending', 'Custom source outside binding never borrows evidence');
    $disabled = row(); $disabled['enabled'] = '0';
    expect(status(fixture('native'), $native, [$disabled])['rows'][0]['state'] === 'disabled', 'Disabled binding never active');
    $manual = row(); $manual['firewall'] = 'manual';
    expect(status(fixture('native'), $native, [$manual])['rows'][0]['state'] === 'manual', 'Manual binding stays explicit');
    Config::$tun = false;
    expect(status(fixture('native'), $native)['rows'][0]['state'] === 'inactive', 'TUN off never active');
    expect(count(warnings(fixture('native'), $native)) === 1, 'TUN off does not erase loaded exposure');
    expect(warnings(fixture('fresh'), $native)[0]['title'] === 'TUN forwarding remains loaded', 'Removed config with stale PF still warns');
    expect(str_contains(warnings(fixture('native'), [])[0]['detail'], 'could not be read'), 'Unreadable PF is not claimed active or absent');
    Config::$tun = true;
    CoreConfig::$fixture = fixture('native');
    Backend::$output = json_encode($native);
    $report = Safety::report();
    expect(count(array_filter($report['items'], fn ($item) => $item['title'] === 'Policy routing is configured')) === 1,
        'Safety report uses native binding reader');
    Backend::$failRuntime = true;
    expect(status(fixture('native'), $native)['rows'][0]['state'] === 'unknown', 'Backend exception never activates binding');
    $report = Safety::report();
    expect(count(array_filter($report['items'], fn ($item) => $item['title'] === 'Policy routing is configured'
        && str_contains($item['detail'], 'could not be read'))) === 1, 'Backend exception retains saved exposure warning');
    expect(array_diff(Backend::$calls, ['mihomo runtime-status', 'mihomo status']) === [], 'Readers only call read-only backend');
    echo "B7 routing status and safety: fresh, native, legacy, migration and stale evidence passed\n";
}
