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
namespace {
    if (!function_exists('gettext')) {
        function gettext(string $message): string { return $message; }
    }
    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    foreach (['RequestParamsTrait', 'Logs', 'ActionResult', 'Subscription', 'Config', 'Inspector', 'Safety'] as $name) {
        require_once $app . 'models/OPNsense/Mihomo/' . $name . '.php';
    }
    foreach (['Dashboard', 'Settings', 'Subscription', 'Routing', 'Log'] as $name) {
        require $app . 'controllers/OPNsense/Mihomo/Api/' . $name . 'Controller.php';
    }
    function expect($condition, $label) {
        if (!$condition) { throw new \RuntimeException($label); }
    }
    class Request {
        public function isPost() { return true; }
        public function getPost($name, $filter = null, $default = null) { return $default; }
        public function getQuery($name, $filter = null, $default = null) { return $default; }
        public function getJsonRawBody() { return []; }
    }
    $guarded = [
        'Dashboard' => ['selectProxy', 'setMode', 'closeConnection', 'testDelay'],
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
    foreach (['api/mihomo/settings/config_get', 'api/mihomo/subscription/get', 'api/mihomo/dashboard/set_mode', 'api/mihomo/routing/history_show'] as $path) {
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

/** Exercise the real REST decode and group projection without network or appliance I/O. */
namespace OPNsense\Mihomo {
    class Fixture {
        public static array $proxies = [];
        public static int $historyReads = 0;
    }
    // Namespace-local transport doubles work even when ext-curl is unavailable.
    const CURLOPT_CUSTOMREQUEST = 1, CURLOPT_RETURNTRANSFER = 2, CURLOPT_CONNECTTIMEOUT = 3,
        CURLOPT_TIMEOUT = 4, CURLOPT_HTTPHEADER = 5, CURLOPT_FOLLOWLOCATION = 6, CURLINFO_HTTP_CODE = 7;
    function curl_init($url) {
        if ($url !== 'http://127.0.0.1:9090/proxies') { throw new \RuntimeException('Unexpected request'); }
        return new \stdClass();
    }
    function curl_setopt_array($handle, $options) {}
    function curl_exec($handle) { return json_encode(['proxies' => Fixture::$proxies]); }
    function curl_getinfo($handle, $option) { return 200; }
    function curl_error($handle) { return ''; }
    function curl_close($handle) {}
    function array_reverse($array, $preserveKeys = false) {
        Fixture::$historyReads++;
        return \array_reverse($array, $preserveKeys);
    }
}
namespace {
    require dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Controller.php';
    use OPNsense\Mihomo\Controller;
    use OPNsense\Mihomo\Fixture;
    $config = tempnam(sys_get_temp_dir(), 'mihomo-proxies-');
    file_put_contents($config, "external-controller: 127.0.0.1:9090\n");
    \OPNsense\Mihomo\Config::setFileOverride($config);
    try {
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
        Fixture::$proxies = $nodes;
        for ($i = 19; $i >= 0; $i--) {
            Fixture::$proxies[sprintf('group-%02d', $i)] = [
                'type' => 'Selector', 'all' => $members, 'now' => $i % 2 ? 'zero' : 'shared',
            ];
        }
        $result = Controller::proxyGroups();
        expect($result['ready'] && $result['error'] === '', 'Successful response preserved');
        expect(count($result['groups']) === 20, 'Every group remains present');
        foreach ($result['groups'] as $i => $group) {
            expect($group['name'] === sprintf('group-%02d', $i), 'Groups remain sorted');
            expect($group['type'] === 'Selector', 'Group type preserved');
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
        expect(Fixture::$historyReads <= count($members), 'Shared histories must be processed at most once per response, including null delays');

        // Repeated polls must observe changed histories, including previously missing nodes.
        Fixture::$proxies['shared']['history'][] = ['delay' => 99];
        Fixture::$proxies['missing'] = ['history' => [['delay' => 15]]];
        Fixture::$historyReads = 0;
        $next = Controller::proxyGroups();
        expect($next['groups'][0]['members'][0]['delay'] === 99, 'New response refreshes a cached delay');
        expect($next['groups'][0]['members'][7]['delay'] === 15, 'New response refreshes a cached null');
        expect(Fixture::$historyReads <= count($members), 'Subsequent responses also reuse shared histories');
        Fixture::$proxies = [];
        expect(Controller::proxyGroups()['groups'] === [], 'Empty response does not retain old groups');
        echo "Proxy groups: shared history work bounded per response, output and freshness preserved\n";
    } finally {
        \OPNsense\Mihomo\Config::setFileOverride(null);
        unlink($config);
    }
}
