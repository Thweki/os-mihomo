<?php
/** Isolated API contracts. No framework, appliance files, network or configd execution. */
namespace OPNsense\Base {
    class ApiControllerBase {
        public $request;
        public function throwReadOnly() { throw new \RuntimeException('read-only'); }
    }
    class ApiMutableModelControllerBase extends ApiControllerBase {}
}
namespace OPNsense\Core {
    class Backend {
        public static string $output = '';
        public static int $calls = 0;
        public function configdRun($action) { self::$calls++; return self::$output; }
        public function configdpRun($action, $args) { self::$calls++; return self::$output; }
    }
}
namespace OPNsense\Mihomo {
    // Keep the Apply failure fixture independent of appliance paths and services.
    class WriteCoordinator {
        public static function revisions(array $paths): array {
            $result = array_fill_keys($paths, 'missing');
            ksort($result);
            return $result;
        }
    }
    class BootSettingsProbe {
        public static int $calls = 0;
        public static bool $reject = false;
    }
    function is_readable(string $path): bool {
        if ($path === '/etc/rc.conf.d/mihomo') {
            BootSettingsProbe::$calls++;
            if (BootSettingsProbe::$reject) {
                throw new \LogicException('Rejected YAML must not reach boot settings');
            }
            return false;
        }
        return \is_readable($path);
    }
    // Namespace-local transport doubles exercise the real JSON decoder without
    // opening sockets or requiring the cURL extension on portable PHP runners.
    class ControllerHttpFixture {
        public static string|false $body = '';
        public static int $status = 200;
        public static string $url = '';
        public static int $historyReads = 0;
        public static int $requestCount = 0;
        public static array $requests = [];
        public static array $responses = [];
        public static array $urls = [];
    }
    function curl_init($url) {
        ControllerHttpFixture::$url = $url;
        ControllerHttpFixture::$requestCount++;
        ControllerHttpFixture::$urls[] = $url;
        return $url;
    }
    function curl_setopt_array($handle, $options) {
        ControllerHttpFixture::$requests[] = [$options[CURLOPT_CUSTOMREQUEST], $handle];
        return true;
    }
    function curl_exec($handle) {
        if (ControllerHttpFixture::$responses) {
            [ControllerHttpFixture::$status, ControllerHttpFixture::$body] = array_shift(ControllerHttpFixture::$responses);
        }
        return ControllerHttpFixture::$body;
        public static array $urls = [];
    }
    function curl_getinfo($handle, $option) { return ControllerHttpFixture::$status; }
    function curl_error($handle) { return 'Fixture transport failure'; }
    function curl_close($handle) {}
    function array_reverse($array, $preserveKeys = false) {
        ControllerHttpFixture::$historyReads++;
        return \array_reverse($array, $preserveKeys);
    }
    function gettext($message) { return $message; }
}
namespace {
    foreach (['CURLOPT_CUSTOMREQUEST', 'CURLOPT_RETURNTRANSFER', 'CURLOPT_CONNECTTIMEOUT',
        'CURLOPT_TIMEOUT', 'CURLOPT_HTTPHEADER', 'CURLOPT_FOLLOWLOCATION', 'CURLINFO_HTTP_CODE'] as $name) {
        define('OPNsense\\Mihomo\\' . $name, $name);
    }
    if (!function_exists('gettext')) {
        function gettext(string $message): string { return $message; }
    }
    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    foreach (['RequestParamsTrait', 'Logs', 'ActionResult', 'Subscription', 'Config', 'Controller', 'Inspector', 'Safety'] as $name) {
        require_once $app . 'models/OPNsense/Mihomo/' . $name . '.php';
    }
    foreach (['Dashboard', 'Settings', 'Subscription', 'Routing', 'Log'] as $name) {
        require $app . 'controllers/OPNsense/Mihomo/Api/' . $name . 'Controller.php';
    }
    function expect($condition, $label) {
        if (!$condition) { throw new \RuntimeException($label); }
    }
    // Use only the shipped example configuration, never appliance credentials.
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        foreach (['version' => ['version' => 'fixture', 'meta' => true],
            'runningConfig' => ['mode' => 'rule', 'tun' => ['enable' => false]]] as $method => $valid) {
            foreach (['"unexpected"', '""', '42', '1.5', 'true', 'false', 'null', '', '{invalid'] as $body) {
                \OPNsense\Mihomo\ControllerHttpFixture::$body = $body;
                expect(\OPNsense\Mihomo\Controller::$method() === null,
                    $method . ' treats non-array JSON as unavailable without a TypeError');
            }
            foreach ([$valid, []] as $data) {
                \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode($data);
                expect(\OPNsense\Mihomo\Controller::$method() === $data, $method . ' preserves decoded arrays');
            }
            $path = $method === 'version' ? '/version' : '/configs';
            expect(\OPNsense\Mihomo\ControllerHttpFixture::$url === 'http://127.0.0.1:9090' . $path,
                $method . ' uses the expected controller endpoint');
            \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode($valid);
            \OPNsense\Mihomo\ControllerHttpFixture::$status = 503;
            expect(\OPNsense\Mihomo\Controller::$method() === null, $method . ' rejects unsuccessful HTTP responses');
            \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
            \OPNsense\Mihomo\ControllerHttpFixture::$body = false;
            expect(\OPNsense\Mihomo\Controller::$method() === null, $method . ' handles transport failure');
        }
        $metadata = [
            ['host' => 'example.invalid', 'sourceIP' => '192.0.2.8', 'sourcePort' => 50000,
                'destinationIP' => '198.51.100.9', 'destinationPort' => 443],
            ['host' => 'ipv6.example.invalid', 'sourceIP' => '2001:db8::8', 'sourcePort' => 50001,
                'destinationIP' => '2001:db8::9', 'destinationPort' => 443],
            ['host' => 'unresolved.example.invalid', 'sourcePort' => 50002, 'destinationPort' => 443],
            ['sourceIP' => null, 'destinationIP' => null],
            ['sourceIP' => '192.0.2.8:443', 'destinationIP' => '[2001:db8::9]'],
            ['sourceIP' => 'example.invalid', 'destinationIP' => ' 192.0.2.8'],
            ['sourceIP' => true, 'destinationIP' => 42],
            ['sourceIP' => '2001:DB8::10', 'destinationIP' => '::ffff:192.0.2.10'],
            ['sourceIP' => '2001:db8::1%em0', 'destinationIP' => '198.51.100.0/24'],
        ];
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode(['connections' =>
            array_map(fn ($meta) => ['metadata' => $meta], $metadata)]);
        $rows = \OPNsense\Mihomo\Controller::connectionRows()['rows'];
        $expectedIPs = [
            ['192.0.2.8', '198.51.100.9'], ['2001:db8::8', '2001:db8::9'], ['', ''], ['', ''],
            ['', ''], ['', ''], ['', ''], ['2001:DB8::10', '::ffff:192.0.2.10'], ['', ''],
        ];
        foreach ($expectedIPs as $index => [$source, $destination]) {
            expect($rows[$index]['sourceIP'] === $source, 'Copy source IP excludes port');
            expect($rows[$index]['destinationIP'] === $destination, 'Copy destination IP excludes port and never falls back to hostname');
        }
        expect($rows[0]['host'] === 'example.invalid' && $rows[0]['source'] === '192.0.2.8:50000'
            && $rows[0]['destination'] === '198.51.100.9:443',
            'Copy metadata preserves existing display fields');
        echo "Connection copy addresses: strict IPv4/IPv6, display fields and hostname distinction passed\n";
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode(['proxies' => [
            'Empty' => ['type' => 'Selector', 'all' => []],
            'Leaf' => ['type' => 'Shadowsocks'],
            'Invalid' => ['type' => 'Selector', 'all' => null],
            'Malformed' => ['type' => 'Selector', 'all' => 'Leaf'],
            'Nested' => ['type' => 'Selector', 'all' => ['Empty'], 'now' => 'Empty'],
        ]]);
        $groups = \OPNsense\Mihomo\Controller::proxyGroups();
        expect($groups['ready'] === true, 'empty groups do not mean an unavailable controller');
        expect(array_column($groups['groups'], 'name') === ['Empty', 'Nested'],
            'retain empty groups but exclude leaves and malformed member lists');
        expect($groups['groups'][0]['members'] === [], 'empty group remains explicitly empty');
        expect($groups['groups'][1]['members'][0]['name'] === 'Empty', 'preserve nested empty group references');
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 503;
        $unavailable = \OPNsense\Mihomo\Controller::proxyGroups();
        expect($unavailable['ready'] === false && $unavailable['groups'] === [],
            'controller failures must not manufacture empty groups');
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
    }
    echo "Controller metadata response types: passed\n";
    // Reuse the existing socket-free transport double rather than redeclaring it.
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        $fixture = \OPNsense\Mihomo\ControllerHttpFixture::class;
        $fixture::$status = 200;
        $nodes = [
            'shared' => ['type' => 'Test', 'history' => [['delay' => 10], ['delay' => '42'], ['delay' => null]]],
            'zero' => ['history' => [['delay' => 12], ['delay' => 0]]],
            'negative' => ['history' => [['delay' => -1]]],
            'empty' => ['history' => []],
            'no-delay' => ['history' => [['time' => 'fixture']]],
            '001' => ['history' => [['delay' => 7]]],
            '1' => ['history' => [['delay' => 8]]],
        ];
        $members = array_merge(array_keys($nodes), ['missing']);
        $expectedDelays = [42, 0, -1, null, null, 7, 8, null];
        $proxies = $nodes;
        for ($i = 19; $i >= 0; $i--) {
            $proxies[sprintf('group-%02d', $i)] = [
                'type' => 'Selector', 'all' => $members, 'now' => $i % 2 ? 'zero' : 'shared',
            ];
        }
        $fixture::$body = json_encode(['proxies' => $proxies]);
        $fixture::$historyReads = 0;
        $fixture::$requests = 0;
        $result = \OPNsense\Mihomo\Controller::proxyGroups();
        expect($fixture::$requests === 1, 'One controller request per proxy group response');
        expect($fixture::$url === 'http://127.0.0.1:9090/proxies', 'Proxy group read uses the existing API endpoint');
        expect($result['ready'] && $result['error'] === '', 'Successful response preserved');
        expect(count($result['groups']) === 20, 'Every group remains present');
        foreach ($result['groups'] as $i => $group) {
            expect($group['name'] === sprintf('group-%02d', $i), 'Groups remain sorted');
            expect($group['type'] === 'Selector', 'Group type preserved');
            expect($group['now'] === ($i % 2 ? 'zero' : 'shared'), 'Current group selection preserved');
            expect(array_column($group['members'], 'name') === $members, 'Member order and names preserved');
            expect(array_column($group['members'], 'delay') === $expectedDelays, 'Latest non-null delay preserved');
            expect(array_column($group['members'], 'alive') === [true, false, false, false, false, true, true, false],
                'Alive state still follows delay');
            expect($group['members'][0]['type'] === 'Test' && $group['members'][7]['type'] === '', 'Member types preserved');
            foreach ($group['members'] as $member) {
                expect($member['selected'] === ($member['name'] === ($i % 2 ? 'zero' : 'shared')),
                    'Selection remains specific to each group');
            }
        }
        expect($fixture::$historyReads === count($members), 'Shared histories must be processed at most once per response, including null delays');

        // Repeated polls must observe changed histories, including previously missing nodes.
        $proxies['shared']['history'][] = ['delay' => 99];
        $proxies['missing'] = ['history' => [['delay' => 15]]];
        $fixture::$body = json_encode(['proxies' => $proxies]);
        $fixture::$historyReads = 0;
        $next = \OPNsense\Mihomo\Controller::proxyGroups();
        expect($next['groups'][0]['members'][0]['delay'] === 99, 'New response refreshes a cached delay');
        expect($next['groups'][0]['members'][7]['delay'] === 15, 'New response refreshes a cached null');
        expect($fixture::$historyReads === count($members), 'Subsequent responses also reuse shared histories');
        $fixture::$body = '{"proxies":{}}';
        expect(\OPNsense\Mihomo\Controller::proxyGroups()['groups'] === [], 'Empty response does not retain old groups');
        echo "Proxy groups: shared history work bounded per response, output and freshness preserved\n";
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        $fixture::$body = '';
        $fixture::$status = 200;
        $fixture::$historyReads = 0;
        $fixture::$requests = 0;
    }
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        $dashboard = new \OPNsense\Mihomo\Api\DashboardController();
        $validRules = [
            ['type' => 'DomainSuffix', 'payload' => 'example.org', 'proxy' => 'Proxy <&>', 'size' => -1],
            ['type' => 'RuleSet', 'payload' => '中文', 'proxy' => 'DIRECT'],
            ['type' => 'Match', 'payload' => '', 'proxy' => 'REJECT'],
        ];
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode(['rules' => $validRules, 'extra' => 'not exposed']);
        $result = $dashboard->rulesAction();
        expect($result === ['ready' => true, 'rows' => [
            ['position' => 1, 'type' => 'DomainSuffix', 'payload' => 'example.org', 'proxy' => 'Proxy <&>'],
            ['position' => 2, 'type' => 'RuleSet', 'payload' => '中文', 'proxy' => 'DIRECT'],
            ['position' => 3, 'type' => 'Match', 'payload' => '', 'proxy' => 'REJECT'],
        ]], 'Runtime rules expose only ordered display fields, including empty MATCH payloads');
        expect(\OPNsense\Mihomo\ControllerHttpFixture::$url === 'http://127.0.0.1:9090/rules', 'Reads the runtime rules endpoint');
        \OPNsense\Mihomo\ControllerHttpFixture::$body = '{"rules":[]}';
        expect($dashboard->rulesAction() === ['ready' => true, 'rows' => []], 'Empty rules are available');
        foreach (['null', '42', '"text"', '{invalid', '{}', '{"rules":null}', '{"rules":"text"}',
            '{"rules":{"named":{}}}', '{"rules":[null]}', '{"rules":[{"type":[],"payload":"","proxy":""}]}',
            '{"rules":[{"type":"Match","proxy":"DIRECT"}]}',
            json_encode(['rules' => [$validRules[0], ['type' => 'Match', 'payload' => '', 'proxy' => []]]])] as $body) {
            \OPNsense\Mihomo\ControllerHttpFixture::$body = $body;
            expect($dashboard->rulesAction() === ['ready' => false, 'rows' => []], 'Malformed rules cannot become an empty or partial successful snapshot');
        }
        foreach ([false, json_encode(['rules' => $validRules])] as $body) {
            \OPNsense\Mihomo\ControllerHttpFixture::$body = $body;
            \OPNsense\Mihomo\ControllerHttpFixture::$status = 503;
            expect($dashboard->rulesAction() === ['ready' => false, 'rows' => []], 'Transport and HTTP errors are unavailable');
        }
        $acl = simplexml_load_file($app . 'models/OPNsense/Mihomo/ACL/ACL.xml');
        expect(in_array('api/mihomo/dashboard/rules', array_map('strval',
            iterator_to_array($acl->{'page-vpn-mihomo-view'}->patterns->pattern, false)), true), 'View privilege can read runtime rules');
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
    }
    echo "Runtime rule snapshot, ordering, schema, failure and read-only API: passed\n";
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        $samples = array_map(fn ($delay) => ['delay' => $delay, 'time' => 'fixture', 'extra' => 'omit'],
            [999, 888, 100, 200, 0, 50, 50, -1, null, 'invalid', 25, 100]);
        $proxies = [
            'A' => ['type' => 'Selector', 'all' => ['Node', 'Empty', 'Missing', 'Unknown'], 'now' => 'Node'],
            'B' => ['type' => 'Selector', 'all' => ['Node']],
            'Node' => ['type' => 'test', 'history' => $samples],
            'Empty' => ['history' => []],
            'Unknown' => ['history' => [['time' => 'fixture']]],
        ];
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode(['proxies' => $proxies]);
        $dashboard = new \OPNsense\Mihomo\Api\DashboardController();
        $result = $dashboard->proxiesAction();
        $members = $result['groups'][0]['members'];
        expect($result['ready'] === true, 'Proxy history uses the existing read endpoint');
        expect($members[0]['delay_history'] === [100, 200, 0, 50, 50, -1, null, null, 25, 100],
            'Only the last ten measurements are exposed in controller order, with unknown gaps');
        expect($members[0]['delay'] === 100 && $members[0]['selected'] && $members[0]['alive'],
            'History leaves the existing delay and selection contract intact');
        expect($members[1]['delay_history'] === [] && $members[2]['delay_history'] === [],
            'Untested and missing proxies have no invented measurements');
        expect($members[3]['delay_history'] === [null], 'Unknown samples retain their position');
        expect($result['groups'][1]['members'][0]['delay_history'] === $members[0]['delay_history'],
            'Shared proxies show identical history in every group');
        expect($dashboard->proxiesAction() === $result, 'Repeated polls do not append measurements');
        $proxies['Node']['history'] = [['delay' => 42]];
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode(['proxies' => $proxies]);
        expect($dashboard->proxiesAction()['groups'][0]['members'][0]['delay_history'] === [42],
            'A controller history reset replaces old samples');
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 503;
        expect($dashboard->proxiesAction()['ready'] === false, 'Failed reads do not invent history');
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
    }
    echo "Proxy latency history API: passed\n";
    class Request {
        public function isPost() { return true; }
        public function getPost($name, $filter = null, $default = null) { return $default; }
        public function getQuery($name, $filter = null, $default = null) { return $default; }
        public function getJsonRawBody() { return []; }
    }
    $clientConnections = [
        ['metadata' => ['sourceIP' => '192.0.2.1', 'sourcePort' => 1000, 'network' => 'tcp'], 'download' => 100, 'upload' => 20],
        ['metadata' => ['sourceIP' => '192.0.2.1', 'sourcePort' => 2000, 'network' => 'udp'], 'download' => 300, 'upload' => 40],
        ['metadata' => ['sourceIP' => '2001:db8::1'], 'download' => 200, 'upload' => 300],
        ['metadata' => ['sourceIP' => '2001:0db8:0:0:0:0:0:1'], 'download' => 100, 'upload' => 100],
        ['metadata' => ['sourceIP' => '192.0.2.2'], 'download' => 0, 'upload' => 0],
        ['download' => -10, 'upload' => 7],
        ['metadata' => ['sourceIP' => '<invalid>'], 'download' => 'bad', 'upload' => 3],
    ];
    $clientSummary = \OPNsense\Mihomo\Controller::connectionClients($clientConnections);
    expect($clientSummary === ['rows' => [
        ['source' => '2001:db8::1', 'connections' => 2, 'download' => 300, 'upload' => 400],
        ['source' => '192.0.2.1', 'connections' => 2, 'download' => 400, 'upload' => 60],
        ['source' => '', 'connections' => 2, 'download' => 0, 'upload' => 10],
        ['source' => '192.0.2.2', 'connections' => 1, 'download' => 0, 'upload' => 0],
    ], 'total' => 4], 'Client totals combine ports/protocols and IPv6 spellings, rank combined bytes, retain idle and unknown clients');
    expect(\OPNsense\Mihomo\Controller::connectionClients([]) === ['rows' => [], 'total' => 0], 'Empty active snapshot has no clients');
    $manyClients = [];
    for ($i = 1; $i <= 15; $i++) {
        $manyClients[] = ['metadata' => ['sourceIP' => '192.0.2.' . $i], 'download' => $i, 'upload' => 0];
    }
    $topClients = \OPNsense\Mihomo\Controller::connectionClients($manyClients);
    expect($topClients['total'] === 15 && count($topClients['rows']) === 10, 'Response bounds rows but counts all clients');
    expect(array_column($topClients['rows'], 'download') === range(15, 6), 'Top ten selected after sorting all connections');
    $ties = array_map(static fn ($ip) => ['metadata' => ['sourceIP' => $ip], 'upload' => 10], ['192.0.2.2', '192.0.2.1']);
    expect(\OPNsense\Mihomo\Controller::connectionClients($ties) === \OPNsense\Mihomo\Controller::connectionClients(array_reverse($ties)), 'Equal-byte ordering is independent of snapshot order');
    $overview = new \OPNsense\Mihomo\Api\DashboardController();
    $overview->request = new class extends Request {
        public string $metadata = '0';
        public function getPost($name, $filter = null, $default = null) {
            return $name === 'metadata' ? $this->metadata : $default;
        }
    };
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        foreach (['0', '1'] as $metadata) {
            $overview->request->metadata = $metadata;
            \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode([
                'connections' => $clientConnections, 'downloadTotal' => 999999, 'uploadTotal' => 888888,
            ]);
            $beforeCalls = \OPNsense\Mihomo\ControllerHttpFixture::$requestCount;
            $data = $overview->overviewAction();
            expect($data['runtime']['clients'] === $clientSummary, 'Both overview modes expose the active snapshot summary, not lifetime totals');
            expect(\OPNsense\Mihomo\ControllerHttpFixture::$requestCount - $beforeCalls === ($metadata === '0' ? 1 : 4), 'Client summary adds no controller requests');
        }
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode(['connections' => []]);
        expect($overview->overviewAction()['runtime']['clients'] === ['rows' => [], 'total' => 0], 'Closed connections disappear rather than accumulate');
        \OPNsense\Mihomo\ControllerHttpFixture::$body = false;
        expect($overview->overviewAction()['runtime']['clients'] === null, 'Unavailable snapshot is distinct from no active clients');
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode(['connections' => $clientConnections]);
        expect($overview->overviewAction()['runtime']['clients'] === $clientSummary, 'Recovery restores current client totals');
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
    }
    echo "Client traffic aggregation and overview snapshot contracts: passed\n";
    // Exercise the real connection decoder and endpoint; spy only on the
    // framework search boundary (OPNsense owns matching, sorting and paging).
    class ConnectionSearchRequest extends Request {
        public function __construct(private array $params) {}
        public function getPost($name, $filter = null, $default = null) { return $this->params[$name] ?? $default; }
    }
    class ConnectionSearchController extends \OPNsense\Mihomo\Api\DashboardController {
        public array $searchInput = [];
        protected function searchRecordsetBase($records, $fields = null, $defaultSort = null) {
            $this->searchInput = [$records, $fields, $defaultSort];
            // A sentinel page proves the endpoint preserves the framework result.
            return ['rows' => [$records[1] ?? []], 'total' => 2, 'current' => 2, 'rowCount' => 1];
        }
    }
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    $connections = [
        ['id' => 'first', 'metadata' => ['host' => 'Example.test', 'sniffHost' => 'sniffed.test',
            'sourceIP' => '2001:db8::1', 'sourcePort' => '50000',
            'destinationIP' => '198.51.100.10', 'destinationPort' => '443',
            'process' => 'Browser <&>', 'processPath' => '/opt/应用/Browser <&>'],
            'chains' => ['DIRECT'], 'start' => '2026-01-01T00:00:01Z'],
        ['id' => 'second', 'metadata' => ['processPath' => '/opt/path-only'], 'chains' => []],
        ['id' => 'third', 'metadata' => [], 'chains' => []],
    ];
    try {
        \OPNsense\Mihomo\ControllerHttpFixture::$body = json_encode([
            'connections' => $connections, 'downloadTotal' => 1234, 'uploadTotal' => 567, 'memory' => 890,
        ]);
        $allFields = ['host', 'sniffHost', 'source', 'destination', 'process', 'processPath',
            'network', 'type', 'rule', 'rulePayload', 'chain', 'outbound'];
        foreach ([
            [[], $allFields],
            [['connectionScope' => 'all'], $allFields],
            [['connectionScope' => 'address'], ['source', 'destination']],
            [['connectionScope' => 'host'], ['host', 'sniffHost']],
            [['connectionScope' => 'process'], ['process', 'processPath']],
            [['connectionScope' => 'unknown'], $allFields],
            [['connectionScope' => ['process']], $allFields],
        ] as [$params, $fields]) {
            $search = new ConnectionSearchController();
            $search->request = new ConnectionSearchRequest($params);
            $page = $search->connectionsAction();
            [$records, $actualFields, $sort] = $search->searchInput;
            expect($actualFields === $fields, 'Only allowlisted scope fields reach framework search');
            expect(count($records) === 3 && $sort === 'start', 'Search receives all connections before framework pagination');
            expect($records[0]['process'] === 'Browser <&>' && $records[0]['processPath'] === '/opt/应用/Browser <&>',
                'Process metadata retains literal text and UTF-8 for server-side matching');
            expect($records[0]['host'] === 'Example.test' && $records[0]['sniffHost'] === 'sniffed.test',
                'Both original and sniffed hosts are searchable');
            expect($records[0]['source'] === '2001:db8::1:50000' && $records[0]['destination'] === '198.51.100.10:443',
                'Address search includes IPv6, destination and ports');
            expect($records[1]['process'] === '' && $records[1]['processPath'] === '/opt/path-only', 'Path-only metadata is retained');
            expect($records[2]['process'] === '' && $records[2]['processPath'] === '' && $records[2]['sniffHost'] === '',
                'Missing optional metadata stays empty');
            expect($page['rows'] === [$records[1]] && $page['total'] === 2 && $page['current'] === 2 && $page['rowCount'] === 1,
                'Endpoint preserves filtered page and match count from framework');
            expect($page['downloadTotal'] === 1234 && $page['uploadTotal'] === 567 && $page['memory'] === 890,
                'Search does not turn global counters into filtered totals');
            expect($page['ready'] === true && $page['error'] === '', 'Successful search retains readiness');
        }
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 503;
        $page = $search->connectionsAction();
        expect($search->searchInput[0] === [] && $page['ready'] === false, 'Unavailable controller provides no stale connections');
    } finally {
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
        \OPNsense\Mihomo\Config::setFileOverride(null);
    }
    echo "Connection search scopes, metadata and framework paging contract: passed\n";
    // Runtime counts come from the controller, never the on-disk YAML rules.
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        $dashboard = new \OPNsense\Mihomo\Api\DashboardController();
        $dashboard->request = new Request();
        $ruleFixtures = [
            ['{"rules":[{"type":"Domain","payload":"example.invalid"},{"type":"RuleSet","payload":"provider"},{"type":"Match"}]}', 3],
            ['{"rules":[]}', 0],
            ['{"rules":[{"type":"Match"}]}', 1],
            ['{}', null], ['{"rules":null}', null], ['{"rules":{}}', null],
            ['{"rules":{"0":{"type":"Match"}}}', null],
            ['{"rules":"unexpected"}', null], ['{"rules":false}', null],
            ['null', null], ['42', null], ['"unexpected"', null],
            ['[]', null], ['', null], ['{invalid', null], [false, null],
        ];
        foreach ($ruleFixtures as [$body, $expected]) {
            \OPNsense\Mihomo\ControllerHttpFixture::$body = $body;
            \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
            expect(\OPNsense\Mihomo\Controller::ruleCount() === $expected, 'Count rules, preserving zero versus unavailable');
            expect(\OPNsense\Mihomo\ControllerHttpFixture::$url === 'http://127.0.0.1:9090/rules', 'Count reads runtime /rules');
            $overview = $dashboard->overviewAction();
            expect(array_key_exists('ruleCount', $overview['runtime']) && $overview['runtime']['ruleCount'] === $expected,
                'Overview exposes only the runtime rule count, including unavailable');
            expect(!array_key_exists('rules', $overview['runtime']), 'Rule payloads stay server-side');
        }
        \OPNsense\Mihomo\ControllerHttpFixture::$body = '{"rules":[]}';
        foreach ([401, 404, 503] as $status) {
            \OPNsense\Mihomo\ControllerHttpFixture::$status = $status;
            expect($dashboard->overviewAction()['runtime']['ruleCount'] === null, 'Failed HTTP requests never report zero rules');
        }
        \OPNsense\Mihomo\ControllerHttpFixture::$status = 200;
        \OPNsense\Mihomo\ControllerHttpFixture::$urls = [];
        $dashboard->request = new class extends Request {
            public function getQuery($name, $filter = null, $default = null) { return $name === 'metadata' ? '0' : $default; }
        };
        expect(!array_key_exists('ruleCount', $dashboard->overviewAction()['runtime']), 'Fast polls omit rule metadata');
        expect(\OPNsense\Mihomo\ControllerHttpFixture::$urls === ['http://127.0.0.1:9090/connections'],
            'Fast polls do not fetch the potentially large rule list');
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
    }
    echo "Runtime rule counts, unavailable responses and metadata-only reads: passed\n";
    $guarded = [
        'Dashboard' => ['selectProxy', 'resetProxy', 'setMode', 'closeConnection', 'testDelay'],
        'Settings' => ['set', 'apply', 'import', 'configSet'],
        'Subscription' => ['save', 'run', 'clearLog'],
        'Routing' => ['apply', 'historyRestore', 'netapply', 'netrollback', 'selftest'],
        'Log' => ['clear'],
    ];
    foreach ($guarded as $name => $actions) {
        $class = 'OPNsense\\Mihomo\\Api\\' . $name . 'Controller';
        $controller = new $class();
        $controller->request = new Request();
        foreach ($actions as $action) {
            try { $controller->{$action . 'Action'}(); throw new \LogicException('Guard absent: ' . $name . '/' . $action); }
            catch (\RuntimeException $error) { expect($error->getMessage() === 'read-only', 'Read-only rejected before I/O'); }
        }
    }
    expect(\OPNsense\Core\Backend::$calls === 0, 'Read-only calls never reach configd');

    \OPNsense\Mihomo\BootSettingsProbe::$calls = 0;
    \OPNsense\Mihomo\BootSettingsProbe::$reject = true;
    // Exercise real Apply selection and patching with locked TUN siblings. The
    // always-written device/stack already match, but must still fail safely.
    $flow = "log-level: info\ntun: {enable: true, device: tun_mihomo, stack: gvisor, auto-route: false}\n";
    $flowFile = tempnam(sys_get_temp_dir(), 'mihomo-flow-test-');
    file_put_contents($flowFile, $flow);
    \OPNsense\Mihomo\Config::setFileOverride($flowFile);
    try {
        $apply = new class extends \OPNsense\Mihomo\Api\SettingsController {
            public $model;
            public function throwReadOnly() {}
            public function getModel() { return $this->model; }
        };
        $apply->model = (object)[
            'managed' => '',
            'general' => (object)[
                'logLevel' => 'debug', 'mode' => 'rule', 'allowLan' => '0',
                'controllerBind' => '127.0.0.1', 'controllerPort' => '9090',
                'secret' => '', 'ipv6' => '0', 'sniffer' => '0', 'enabled' => '1',
            ],
            'tun' => (object)[
                'enabled' => '0', 'device' => 'tun_mihomo', 'stack' => 'gvisor',
                'autoRoute' => '1', 'strictRoute' => '0', 'mtu' => '1500',
            ],
            'dns' => (object)[
                'enabled' => '0', 'listen' => '127.0.0.1:1053', 'enhancedMode' => 'redir-host', 'ipv6' => '0',
            ],
        ];
        $apply->request = new class extends Request {
            public function getJsonRawBody() {
                $expected = \OPNsense\Mihomo\WriteCoordinator::revisions([
                    \OPNsense\Mihomo\Config::FILE, \OPNsense\Mihomo\Subscription::ENV_FILE,
                    '/etc/rc.conf.d/mihomo', '/conf/config.xml',
                ]);
                return ['version' => hash('sha256', json_encode($expected, JSON_UNESCAPED_SLASHES))];
            }
        };
        foreach (['', 'mihomo.general.logLevel'] as $managed) {
            $apply->model->managed = $managed;
            $result = $apply->applyAction();
            expect($result['state'] === 'failed' && $result['changed'] === false && $result['code'] === 'apply',
                'Flow parent rejection is an explicit unchanged Apply failure');
            expect(str_contains($result['message'], '"tun"') && str_contains($result['message'], 'block mapping'),
                'Apply explains how to resolve the unsupported parent without exposing its contents');
            expect(\OPNsense\Core\Backend::$calls === 0 && \OPNsense\Mihomo\BootSettingsProbe::$calls === 0,
                'Flow parent rejection precedes other file preparation and configd commit');
            expect(file_get_contents($flowFile) === $flow, 'Locked siblings and earlier selected settings remain byte-identical');
            expect(glob($flowFile . '.bak.*') === [], 'Rejected Apply creates no configuration backup');
        }
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        unlink($flowFile);
        \OPNsense\Mihomo\BootSettingsProbe::$reject = false;
    }
    echo "Settings Apply flow mappings: fixed TUN fields reject without writes\n";

    foreach (['Config', 'Safety'] as $name) {
        require_once $app . 'models/OPNsense/Mihomo/' . $name . '.php';
    }
    $config = tempnam(sys_get_temp_dir(), 'mihomo-controller-safety-');
    \OPNsense\Mihomo\Config::setFileOverride($config);
    $bindings = [
        ':9090' => false,
        '0.0.0.0:9090' => false,
        '*:9090' => false,
        '[::]:9090' => false,
        '[0:0:0:0:0:0:0:0]:9090' => false,
        '192.0.2.1:9090' => false,
        '[2001:db8::1]:9090' => false,
        'controller.example.invalid:9090' => false,
        '127.0.0.1:9090' => true,
        '127.0.0.2:9090' => true,
        'localhost:9090' => true,
        '[::1]:9090' => true,
        '[0:0:0:0:0:0:0:1]:9090' => true,
        '127.0.0.1' => false,
        '::1:9090' => false,
        'localhost:invalid' => false,
        '' => true,
    ];
    try {
        foreach ($bindings as $bind => $loopback) {
            foreach (['', 'fixture-controller-token'] as $secret) {
                file_put_contents($config, "external-controller: \"{$bind}\"\nsecret: \"{$secret}\"\ntun:\n  enable: false\n");
                $items = array_column(\OPNsense\Mihomo\Safety::report(false)['items'], 'level', 'title');
                expect(isset($items['External controller is reachable from the network']) === !$loopback,
                    'Controller exposure warning: ' . $bind);
                expect(isset($items['External controller is exposed without a secret']) === (!$loopback && $secret === ''),
                    'Unauthenticated controller danger: ' . $bind);
                if (!$loopback && $secret === '') {
                    expect($items['External controller is exposed without a secret'] === 'danger',
                        'Exposed controller must be dangerous: ' . $bind);
                }
                expect(isset($items['External controller has no secret (loopback only)']) === ($loopback && $secret === ''),
                    'Loopback reassurance requires a loopback binding: ' . $bind);
            }
        }
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        unlink($config);
    }
    echo "Controller binding safety reports: passed\n";

    // Reset uses the core's unfix operation, never a guessed first/fastest member.
    class WritableDashboard extends \OPNsense\Mihomo\Api\DashboardController {
        public function throwReadOnly() {}
    }
    class ResetRequest extends Request {
        public function __construct(public mixed $group, public bool $post = true) {}
        public function isPost() { return $this->post; }
        public function getJsonRawBody() { return ['group' => $this->group]; }
    }
    $reset = function ($group, $post = true) {
        $controller = new WritableDashboard();
        $controller->request = new ResetRequest($group, $post);
        return $controller->resetProxyAction();
    };
    \OPNsense\Mihomo\Config::setFileOverride(dirname(__DIR__) . '/src/usr/local/etc/mihomo/config.yaml');
    try {
        \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
        foreach ([null, '', [], 123] as $invalid) {
            expect($reset($invalid)['status'] === 'failed', 'Invalid reset name rejected');
        }
        expect($reset('Group', false)['status'] === 'failed', 'Reset requires POST');
        expect(\OPNsense\Mihomo\ControllerHttpFixture::$requests === [], 'Rejected reset does no controller I/O');

        $name = ' 中文 /?%#" &gt; ';
        $url = 'http://127.0.0.1:9090/proxies/' . rawurlencode($name);
        foreach (['URLTest', 'Fallback'] as $type) {
            // Empty fixed is also safe: reset is idempotent if another operator already reset it.
            foreach (['Pinned', ''] as $fixed) {
                \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
                \OPNsense\Mihomo\ControllerHttpFixture::$responses = [
                    [200, json_encode(['type' => $type, 'fixed' => $fixed])], [204, ''],
                ];
                $result = $reset($name);
                expect($result['status'] === 'ok' && str_contains($result['message'], $name), 'Reset success preserves exact group name');
                expect(\OPNsense\Mihomo\ControllerHttpFixture::$requests === [['GET', $url], ['DELETE', $url]],
                    'Reset validates live type then deletes only the encoded group override');
            }
        }
        foreach ([['type' => 'Selector'], ['type' => 'LoadBalance'], ['type' => 'Direct'], [], 'invalid'] as $data) {
            \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
            \OPNsense\Mihomo\ControllerHttpFixture::$responses = [[200, json_encode($data)]];
            expect($reset($name)['status'] === 'failed', 'Unsupported or malformed group rejected');
            expect(count(\OPNsense\Mihomo\ControllerHttpFixture::$requests) === 1, 'Unsupported type never reaches DELETE');
        }
        foreach ([[404, '{}'], [503, '{}'], [0, false]] as $failure) {
            foreach ([false, true] as $failDelete) {
                \OPNsense\Mihomo\ControllerHttpFixture::$requests = [];
                \OPNsense\Mihomo\ControllerHttpFixture::$responses = $failDelete
                    ? [[200, '{"type":"URLTest"}'], $failure] : [$failure];
                $result = $reset($name);
                expect($result['status'] === 'failed' && $result['message'] !== '', 'Reset reports read/write failures');
                expect(count(\OPNsense\Mihomo\ControllerHttpFixture::$requests) === ($failDelete ? 2 : 1), 'Failed read prevents mutation');
            }
        }
        $nodes = [];
        foreach (['URLTest', 'Fallback', 'Selector', 'LoadBalance'] as $type) {
            foreach (['', 'Pinned', '0', null, []] as $i => $fixed) {
                $nodes[$type . $i] = ['type' => $type, 'fixed' => $fixed, 'all' => ['First', 'Pinned'], 'now' => 'Pinned'];
            }
        }
        \OPNsense\Mihomo\ControllerHttpFixture::$responses = [[200, json_encode(['proxies' => $nodes])]];
        foreach (\OPNsense\Mihomo\Controller::proxyGroups()['groups'] as $group) {
            $node = $nodes[$group['name']];
            $expected = in_array($node['type'], ['URLTest', 'Fallback'], true)
                && is_string($node['fixed']) && $node['fixed'] !== '';
            expect($group['canReset'] === $expected, 'Only overridden automatic groups advertise reset');
            expect($group['members'][1]['selected'], 'Reset capability preserves selection');
        }
    } finally {
        \OPNsense\Mihomo\ControllerHttpFixture::$responses = [];
        \OPNsense\Mihomo\Config::setFileOverride(null);
    }
    echo "Automatic selection reset: guards, exact names, group types and controller failures passed\n";
    $settings = new \OPNsense\Mihomo\Api\SettingsController();
    foreach (['', 'FATAL: invalid config', 'Configuration is valid.', '{"status":"ok"}', '{"state":"failed","status":"ok","changed":"no","code":[],"message":"invalid"}'] as $output) {
        \OPNsense\Core\Backend::$output = $output;
        expect($settings->configTestAction()['status'] === 'failed', 'Unknown output must not be reported as valid');
    }
    foreach (['unchanged', 'completed', 'accepted', 'failed', 'partial'] as $state) {
        $result = \OPNsense\Mihomo\ActionResult::make($state, $state === 'completed');
        $parsed = \OPNsense\Mihomo\ActionResult::parse(json_encode($result));
        expect($parsed['state'] === $state && is_bool($parsed['changed']), 'Structured state round trip: ' . $state);
    }
    \OPNsense\Core\Backend::$output = json_encode(\OPNsense\Mihomo\ActionResult::make('completed'));
    expect($settings->configTestAction()['status'] === 'ok', 'Explicit validated result accepted');
    $config = tempnam(sys_get_temp_dir(), 'mihomo-safety-');
    file_put_contents($config, "external-controller: 127.0.0.1:9090\ntun:\n  enable: false\n");
    \OPNsense\Mihomo\Config::setFileOverride($config);
    $fixtures = [
        'empty response' => ['', false, 'The backend did not return a valid action result.'],
        'whitespace response' => [" \n\t", false, 'The backend did not return a valid action result.'],
        'malformed JSON' => ['{"state":', false, 'The backend did not return a valid action result.'],
        'incomplete envelope' => ['{"status":"ok"}', false, 'The backend did not return a valid action result.'],
        'legacy success text' => ['Configuration is valid.', false, 'The backend did not return a valid action result.'],
        'rejected configuration' => [
            '{"status":"failed","state":"failed","changed":false,"code":"configuration_failed","message":"Mihomo rejected the configuration (exit 1)."}',
            false, 'Mihomo rejected the configuration (exit 1).',
        ],
        'missing binary' => [
            '{"status":"failed","state":"failed","changed":false,"code":"configuration_failed","message":"The mihomo binary is missing."}',
            false, 'The mihomo binary is missing.',
        ],
        'successful validation' => [
            '{"status":"ok","state":"unchanged","changed":false,"code":"valid","message":"Configuration validation passed."}',
            true, 'Configuration validation passed.',
        ],
    ];
    foreach (['accepted', 'partial', 'failed', 'completed'] as $state) {
        $fixtures[$state . ' is not a validation result'] = [
            json_encode(\OPNsense\Mihomo\ActionResult::make($state, false, 'valid', 'Validation pending.')),
            false, 'Validation pending.',
        ];
    }
    $fixtures['unrelated successful result'] = [
        json_encode(\OPNsense\Mihomo\ActionResult::make('unchanged', false, 'unchanged', 'No changes.')),
        false, 'No changes.',
    ];
    $fixtures['success depends on the envelope, not message words'] = [
        json_encode(\OPNsense\Mihomo\ActionResult::make('unchanged', false, 'valid', 'No invalid syntax or error found.')),
        true, 'No invalid syntax or error found.',
    ];
    try {
        foreach ($fixtures as $label => [$output, $valid, $message]) {
            \OPNsense\Core\Backend::$output = $output;
            $report = \OPNsense\Mihomo\Safety::report(true);
            $item = $report['items'][count($report['items']) - 1];
            expect($item['level'] === ($valid ? 'info' : 'danger'), 'Safety validation severity: ' . $label);
            expect($report['status'] === ($valid ? 'info' : 'danger'), 'Safety report severity: ' . $label);
            expect($item['title'] === ($valid ? 'Configuration syntax is valid' : 'Configuration syntax is invalid'), 'Safety validation title: ' . $label);
            expect($item['detail'] === $message, 'Safety validation message: ' . $label);
        }
        $report = \OPNsense\Mihomo\Safety::report(false);
        expect(count($report['items']) === 1, 'Optional validation stays disabled by default');
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        unlink($config);
    }
    echo "Safety structured validation results: passed\n";
    $raw = "converter https://example.invalid/path?token=fixture-value\nsecret: fixture-secret\nAuthorization: Bearer fixture-auth\n访问密钥：fixture-key\nnormal message";
    $redacted = \OPNsense\Mihomo\Logs::redact($raw);
    foreach (['fixture-value', 'fixture-secret', 'fixture-auth', 'fixture-key'] as $secret) {
        expect(!str_contains($redacted, $secret), 'Sensitive output masked');
    }
    expect(str_contains($redacted, 'normal message'), 'Ordinary log text preserved');
    $acl = simplexml_load_file($app . 'models/OPNsense/Mihomo/ACL/ACL.xml');
    $view = array_map('strval', iterator_to_array($acl->{'page-vpn-mihomo-view'}->patterns->pattern, false));
    foreach (['api/mihomo/settings/config_get', 'api/mihomo/subscription/get', 'api/mihomo/dashboard/set_mode', 'api/mihomo/dashboard/reset_proxy', 'api/mihomo/routing/history_show'] as $path) {
        foreach ($view as $pattern) { expect(!fnmatch($pattern, $path), 'View privilege excludes mutation and credentials'); }
    }
    expect((string)$acl->{'page-vpn-mihomo'}->patterns->pattern[1] === 'api/mihomo/*', 'Existing full-access grant remains compatible');
    require $app . 'models/OPNsense/Mihomo/CronApply.php';
    $marker = sys_get_temp_dir() . '/mihomo-cron-test-' . bin2hex(random_bytes(6));
    $saves = 0; $reloads = 0;
    $save = function () use (&$saves) { $saves++; };
    try {
        try {
            \OPNsense\Mihomo\CronApply::run(true, $save, function () use (&$reloads) { $reloads++; return 'failed'; }, $marker);
            throw new \LogicException('Cron failure was hidden');
        } catch (\RuntimeException $error) {
            expect(is_file($marker) && $saves === 1, 'Failed Cron reload remains pending after saved model');
        }
        expect(\OPNsense\Mihomo\CronApply::run(false, $save, function () use (&$reloads) { $reloads++; return 'OK'; }, $marker), 'Unchanged model retries pending Cron reload');
        expect(!is_file($marker) && $saves === 1 && $reloads === 2, 'Retry only reloads and clears pending marker');
        expect(!\OPNsense\Mihomo\CronApply::run(false, $save, fn () => 'unexpected', $marker), 'Unchanged completed Cron is a no-op');
    } finally { if (is_file($marker)) { unlink($marker); } }
    echo "API read-only guards, strict action results, redaction and ACL: passed\n";
}
