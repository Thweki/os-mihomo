<?php
/** Exercise the real three-stage controller and its cleanup without OPNsense or configd. */
namespace OPNsense\Base {
    class ApiMutableModelControllerBase {
        public $request;
        public function throwReadOnly() {}
        public function getModel() {
            $item = (object)['enabled' => '1', 'interface' => 'lan', 'source' => '', 'scope' => '',
                'target' => '', 'firewall' => 'auto', 'descr' => ''];
            $rows = new class($item) {
                private $item;
                public function __construct($item) { $this->item = $item; }
                public function iterateItems() { return ['fixture' => $this->item]; }
            };
            return (object)['policyRouting' => (object)['rule' => $rows]];
        }
    }
}
namespace OPNsense\Core {
    class Backend {
        public static array $results = [];
        public static array $payloads = [];
        public function configdpRun($action, $args) {
            self::$payloads[] = json_decode(file_get_contents($args[0]), true);
            $result = array_shift(self::$results);
            if ($result instanceof \Throwable) { throw $result; }
            if ($result === null) { throw new \LogicException('Unexpected backend call'); }
            return json_encode($result);
        }
    }
    class Config {
        public static function getInstance() { return new self(); }
        public function save() {}
    }
}
namespace OPNsense\Mihomo {
    class NetworkConfig {
        public string $version = 'fixture-revision';
        public function __construct(?string $expected = null) {
            if ($expected !== null && $expected !== $this->version) {
                throw new \RuntimeException('Unexpected fixture revision');
            }
        }
        public function save(): string { return $this->version; }
        public function close(): void {}
        public function advanceBackup(?string $backup, string $version): void {}
    }
    class Config {
        public static function interfaceSubnets() { return ['lan' => '192.0.2.0/24']; }
        public static function createStagingFile($content) {
            $path = tempnam(sys_get_temp_dir(), 'mihomo-net-api-');
            file_put_contents($path, $content);
            return $path;
        }
    }
}
namespace OPNsense\Firewall {
    class Filter {
        public static bool $failRemoval = false;
        public static int $removed = 0;
        public $rules;
        public function __construct() {
            $rows = new class {
                public function iterateItems() { return ['fixture' => (object)['description' => 'Mihomo policy (lan)']]; }
                public function del($uuid) {
                    if (Filter::$failRemoval) { throw new \RuntimeException('Injected rule removal failure'); }
                    Filter::$removed++;
                }
            };
            $this->rules = (object)['rule' => $rows];
        }
        public function performValidation() { return []; }
        public function serializeToConfig() {}
    }
}
namespace {
    if (!function_exists('gettext')) {
        function gettext(string $message): string { return $message; }
    }
    $app = dirname(__DIR__) . '/src/usr/local/opnsense/mvc/app/';
    require $app . 'models/OPNsense/Mihomo/RequestParamsTrait.php';
    require $app . 'controllers/OPNsense/Mihomo/Api/RoutingController.php';
    function expectNetworkApi($condition, $label) {
        if (!$condition) { throw new \RuntimeException($label); }
    }
    $controller = new \OPNsense\Mihomo\Api\RoutingController();
    $controller->request = new class {
        public function isPost() { return true; }
        public function getPost($name, $filters, $default) { return $default; }
        public function getJsonRawBody() { return ['version' => 'fixture-revision']; }
    };
    $ok = ['status' => 'ok', 'messages' => [], 'version' => 'fixture-revision'];
    $failed = ['status' => 'failed', 'message' => 'Injected PF/reload failure'];
    foreach ([$ok, $failed, new \RuntimeException('Injected backend failure')] as $cleanup) {
        \OPNsense\Core\Backend::$results = [$ok, $failed, $cleanup];
        \OPNsense\Core\Backend::$payloads = [];
        $result = $controller->netapplyAction();
        expectNetworkApi($result['status'] === 'failed', 'Apply failure survives cleanup');
        $confirmed = $cleanup === $ok;
        expectNetworkApi($result['rollback']['status'] === ($confirmed ? 'ok' : 'failed'), 'Cleanup outcome is explicit');
        expectNetworkApi(str_contains($result['message'], $confirmed ? 'verified as empty' : 'not confirmed'), 'No false unbind claim');
        $calls = \OPNsense\Core\Backend::$payloads;
        expectNetworkApi(count($calls) === 3 && $calls[2]['interfaces'] === [] && $calls[2]['verify_only'], 'Cleanup must reload and verify empty PF bindings');
    }
    \OPNsense\Firewall\Filter::$failRemoval = true;
    \OPNsense\Core\Backend::$results = [$ok, $failed];
    $result = $controller->netapplyAction();
    expectNetworkApi($result['rollback']['status'] === 'failed'
        && str_contains($result['message'], 'Injected rule removal failure'), 'Removal exceptions are not swallowed');
    \OPNsense\Firewall\Filter::$failRemoval = false;
    \OPNsense\Core\Backend::$results = [$ok, new \RuntimeException('Apply backend unavailable'), $ok];
    $result = $controller->netapplyAction();
    expectNetworkApi($result['status'] === 'failed' && $result['rollback']['status'] === 'ok', 'Apply transport exception still attempts verified cleanup');
    \OPNsense\Core\Backend::$results = [$ok, $ok];
    \OPNsense\Core\Backend::$payloads = [];
    $result = $controller->netapplyAction();
    expectNetworkApi($result['status'] === 'ok' && count(\OPNsense\Core\Backend::$payloads) === 2, 'Verified apply does not remove rules');
    \OPNsense\Core\Backend::$results = [$failed];
    \OPNsense\Core\Backend::$payloads = [];
    $result = $controller->netapplyAction();
    expectNetworkApi($result['status'] === 'failed' && count(\OPNsense\Core\Backend::$payloads) === 1, 'Preparation failure stops apply');
    echo "Network API apply and cleanup results: passed\n";
}
