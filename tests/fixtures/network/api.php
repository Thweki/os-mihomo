<?php
namespace OPNsense\Base {
    class ApiMutableModelControllerBase {
        public $request;
        public function throwReadOnly() {}
        public function getModel() {
            return (object)['policyRouting' => (object)['rule' => new \OPNsense\Firewall\FixtureRules()]];
        }
    }
}
namespace OPNsense\Firewall {
    class FixtureRules {
        public function iterateItems(): array { return []; }
    }
    class Filter {
        public $rules;
        public function __construct() { $this->rules = (object)['rule' => new FixtureRules()]; }
        public function performValidation(): array { return []; }
        public function serializeToConfig(): void {
            \OPNsense\Core\Config::getInstance()->object()->fixtureRules = 'saved';
        }
    }
}
namespace OPNsense\Core {
    class Backend {
        public function configdpRun($action, $args) { return ($GLOBALS['networkBackend'])($action, $args); }
    }
}
