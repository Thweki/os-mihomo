<?php

/*
 * os-mihomo —— 路由策略（按接口/源分流）接口
 *
 * 提供 OPNsense 原生的表格 CRUD（search/get/set/add/del/toggle），
 * 以及三个自定义动作：
 *   options  下拉数据（接口 + 代理组）
 *   preview  预览将要写入 config.yaml 的规则（只读，不落盘）
 *   apply    渲染规则 -> configd(root) 落盘 config.yaml 与订阅模板（mihomo -t 校验 + 自动备份）
 *   status   只读状态：每个接口当前是否真的会经过 mihomo
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Core\Config as CoreConfig;
use OPNsense\Mihomo\Config;
use OPNsense\Mihomo\RequestParamsTrait;

class RoutingController extends ApiMutableModelControllerBase
{
    use RequestParamsTrait;

    protected static $internalModelName = 'mihomo';
    protected static $internalModelClass = '\OPNsense\Mihomo\Mihomo';

    /* ------------------------------------------------------------------ *
     * 表格 CRUD（与核心防火墙规则页同一套方法名）
     * ------------------------------------------------------------------ */

    public function searchRuleAction()
    {
        return $this->searchBase('policyRouting.rule', null, 'interface');
    }

    public function getRuleAction($uuid = null)
    {
        return $this->getBase('mihomo', 'policyRouting.rule', $uuid);
    }

    public function setRuleAction($uuid)
    {
        return $this->setBase('mihomo', 'policyRouting.rule', $uuid);
    }

    public function addRuleAction()
    {
        return $this->addBase('mihomo', 'policyRouting.rule');
    }

    public function delRuleAction($uuid)
    {
        return $this->delBase('policyRouting.rule', $uuid);
    }

    public function toggleRuleAction($uuid, $enabled = null)
    {
        return $this->toggleBase('policyRouting.rule', $uuid, $enabled);
    }

    /* ------------------------------------------------------------------ *
     * 下拉数据与预览
     * ------------------------------------------------------------------ */

    /**
     * 接口（带描述与网段）与代理组，供对话框下拉使用。
     */
    public function optionsAction()
    {
        $subnets = $this->bindableInterfaces();
        $descr = [];
        try {
            $cfg = CoreConfig::getInstance()->object();
            foreach ($cfg->interfaces->children() as $name => $node) {
                $descr[$name] = trim((string)$node->descr);
            }
        } catch (\Throwable $e) {
            /* 取不到描述就用接口名 */
        }

        $interfaces = [];
        foreach ($subnets as $name => $cidr) {
            $label = $name;
            if (!empty($descr[$name])) {
                $label = sprintf('%s (%s)', $descr[$name], $name);
            }
            $interfaces[] = [
                'value' => $name,
                'label' => sprintf('%s — %s', $label, $cidr),
                'subnet' => $cidr,
            ];
        }
        ksort($interfaces);

        $targets = [];
        foreach (Config::policyTargets() as $group) {
            $targets[] = ['value' => $group, 'label' => $group];
        }

        return [
            'status' => 'ok',
            'interfaces' => array_values($interfaces),
            'targets' => $targets,
            'tun_enabled' => Config::bool('tun.enable'),
            'auto_route' => Config::bool('tun.auto-route'),
        ];
    }

    /**
     * 预览：模型里的策略行会渲染成哪些 mihomo 规则。
     */
    public function previewAction()
    {
        $rules = $this->collectRows();
        $subnets = Config::interfaceSubnets();
        $lines = Config::renderPolicyRules($rules, $subnets);

        $known = Config::policyTargets();
        $warnings = [];
        if ($lines === []) {
            $warnings[] = gettext('No rule would be generated: every row is disabled, has no source, or has no outbound selected.');
        }
        foreach ($rules as $row) {
            if ($row['scope'] === 'direct' || $row['target'] === '') {
                continue;
            }
            if (!in_array($row['target'], $known, true)) {
                $warnings[] = sprintf(
                    gettext('Proxy group "%s" does not exist in the current configuration file.'),
                    $row['target']
                );
            }
            if ($row['source'] === '' && !isset($subnets[$row['interface']])) {
                $warnings[] = sprintf(
                    gettext('Interface "%s" has no IPv4 network; set a source explicitly.'),
                    $row['interface']
                );
            }
        }
        if (!Config::bool('tun.enable')) {
            $warnings[] = gettext('TUN is disabled: these rules are written and validated, but no traffic reaches mihomo yet.');
        }

        $sample = Config::applyPolicyBlock(
            "rules:\n  - GEOSITE,private,DIRECT\n  - MATCH,DIRECT\n",
            $lines
        );

        return [
            'status' => 'ok',
            'rules' => $lines,
            'warnings' => $warnings,
            'sample' => $sample,
            'targets' => $known,
        ];
    }

    /**
     * 应用：把渲染结果交给 configd（root）写入 config.yaml 与订阅模板。
     */
    public function applyAction()
    {
        $result = ['status' => 'failed', 'messages' => []];
        if (!$this->request->isPost()) {
            $result['message'] = gettext('POST required.');
            return $result;
        }
        $this->throwReadOnly();

        if (!Config::exists()) {
            $result['message'] = sprintf(
                gettext('Configuration file %s is missing. Install the plugin first.'),
                Config::FILE
            );
            return $result;
        }

        $lines = Config::renderPolicyRules($this->collectRows(), Config::interfaceSubnets());

        try {
            $staging = Config::createStagingFile(json_encode(
                ['rules' => $lines],
                JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
            ));
        } catch (\Throwable $e) {
            $result['message'] = $e->getMessage();
            return $result;
        }

        $backend = new Backend();
        $output = trim((string)$backend->configdpRun('mihomo policy-apply', [$staging]));
        $decoded = json_decode($output, true);
        if (is_array($decoded)) {
            return $decoded;
        }

        $result['message'] = $output === '' ? gettext('(no output)') : $output;
        return $result;
    }

    /**
     * 只读状态：每个接口当前是否真的会经过 mihomo。
     */
    public function statusAction()
    {
        $subnets = Config::interfaceSubnets();
        $tunEnabled = Config::bool('tun.enable');
        $autoRoute = Config::bool('tun.auto-route');

        /* OPNsense 侧是否已经存在策略路由（P12-2 才会创建，这里只做只读判断） */
        $gatewayExists = false;
        $ruleExists = false;
        try {
            $cfg = CoreConfig::getInstance()->object();
            /* 网关：模型挂载点是 //OPNsense/Gateways */
            if (isset($cfg->OPNsense->Gateways)) {
                foreach ($cfg->OPNsense->Gateways->gateway_item as $item) {
                    if ((string)$item->name === 'MIHOMO_TUN') {
                        $gatewayExists = true;
                    }
                }
            }
            if (isset($cfg->filter->rule)) {
                foreach ($cfg->filter->rule as $rule) {
                    if (
                        (string)$rule->gateway === 'MIHOMO_TUN'
                        && stripos((string)$rule->descr, 'Mihomo policy routing') !== false
                    ) {
                        $ruleExists = true;
                    }
                }
            }
        } catch (\Throwable $e) {
            /* 只读判断失败不阻塞页面 */
        }

        $rows = [];
        foreach ($this->collectRows(true) as $row) {
            if ($row['source'] === '') {
                $row['source'] = (string)($subnets[$row['interface']] ?? '');
            }
            if (!$tunEnabled) {
                $row['state'] = 'inactive';
                $row['note'] = gettext('TUN is disabled: traffic does not reach mihomo.');
            } elseif ($row['firewall'] === 'auto' && !($gatewayExists && $ruleExists)) {
                $row['state'] = 'pending';
                $row['note'] = gettext('Waiting for the OPNsense side: interface, gateway and policy routing rule.');
            } elseif ($row['firewall'] === 'manual') {
                $row['state'] = 'manual';
                $row['note'] = gettext('Manual: make sure the interface is policy routed into the TUN device.');
            } else {
                $row['state'] = 'active';
                $row['note'] = gettext('Policy routing is in place.');
            }
            $rows[] = $row;
        }

        return [
            'status' => 'ok',
            'tun_enabled' => $tunEnabled,
            'auto_route' => $autoRoute,
            'gateway' => $gatewayExists,
            'firewall_rule' => $ruleExists,
            'rows' => $rows,
        ];
    }

    /* ------------------------------------------------------------------ *
     * 网络侧（OPNsense）：接口 / 网关 / 策略路由规则
     *
     * 只对「已启用 + 策略路由=自动」的行生效；未列出的接口一条规则都不加。
     * 实际写入由 configd(root) 的 policy_net.php 完成：只增不改 + config.xml 备份 + 可回滚。
     * ------------------------------------------------------------------ */

    /** 网络侧现状（只读） */
    public function netstatusAction()
    {
        return $this->configdJson('policy-net-check');
    }

    /** 可用于绑定的接口（排除回环/动态接口） */
    private function bindableInterfaces(): array
    {
        $subnets = Config::interfaceSubnets();
        unset($subnets['lo0']);
        return $subnets;
    }

    /** 网络侧变更计划（只读，供弹窗展示） */
    public function netplanAction()
    {
        $staging = null;
        try {
            $staging = $this->writeStaging($this->netPayload());
            return $this->configdJson('policy-net-plan', [$staging]);
        } catch (\Throwable $e) {
            return ['status' => 'failed', 'message' => $e->getMessage()];
        } finally {
            if ($staging !== null) {
                @unlink($staging);
            }
        }
    }

    /** 应用网络侧变更（写 config.xml + filter reload）。interfaces 为空 = 全部解绑 */
    public function netapplyAction()
    {
        $result = ['status' => 'failed', 'messages' => []];
        if (!$this->request->isPost()) {
            $result['message'] = gettext('POST required.');
            return $result;
        }
        $this->throwReadOnly();

        $payload = $this->netPayload();

        /* 1) 防火墙规则：写进核心防火墙模块的「浮动规则」——
         *    浮动规则先于接口规则执行，因此不会被该接口的默认放行规则挡住。
         *    （写进旧版根 <filter> 的规则会被默认放行规则抢先，实测 Evaluations=0） */
        try {
            $result['messages'] = array_merge($result['messages'], $this->syncFloatingRules($payload['interfaces']));
        } catch (\Throwable $e) {
            $result['message'] = sprintf(gettext('Firewall rules could not be updated: %s'), $e->getMessage());
            return $result;
        }

        /* 2) 接口 + 网关（root 脚本，文本级编辑 + 备份），并清理旧版遗留规则 */
        $staging = null;
        try {
            $staging = $this->writeStaging($payload);
            $netResult = $this->configdJson('policy-net-apply', [$staging]);
        } catch (\Throwable $e) {
            $result['message'] = $e->getMessage();
            return $result;
        } finally {
            if ($staging !== null) {
                @unlink($staging);
            }
        }

        if (($netResult['status'] ?? '') !== 'ok') {
            return $netResult;
        }

        return [
            'status' => 'ok',
            'messages' => array_merge($result['messages'], $netResult['messages'] ?? []),
            'diff' => $netResult['diff'] ?? '',
            'state' => $netResult['state'] ?? [],
        ];
    }

    /**
     * 在核心防火墙模块里维护本插件的浮动规则：
     *   · 每个绑定接口：先「内网直达」（无网关）× N，再「策略路由」（带网关）——顺序即优先级
     *   · 未绑定的接口：删除其规则
     * 规则用 description 标记（Mihomo local bypass (x) / Mihomo policy routing (x)）。
     */
    private function syncFloatingRules(array $interfaces): array
    {
        $messages = [];
        $model = new \OPNsense\Firewall\Filter();
        $subnets = $this->bindableInterfaces();

        /* 现有本插件规则：description → uuid 列表（同一描述出现多次视为重复，保留一个） */
        $existing = [];
        foreach ($model->rules->rule->iterateItems() as $uuid => $node) {
            if (preg_match('/^Mihomo (bypass|policy) \(([^)]*)\)$/', (string)$node->description, $m)) {
                $existing[$m[1] . '(' . $m[2] . ')'][] = $uuid;
            }
        }
        $existingKey = [];
        foreach ($existing as $key => $uuids) {
            $existingKey[$key] = $uuids[0];
        }

        /* 期望集合：绑定接口的内网直达 + 策略路由（键与 description 一致，便于比对） */
        $desired = [];
        foreach ($interfaces as $iface) {
            foreach (array_keys($subnets) as $destIface) {
                if ($destIface === $iface) {
                    continue;
                }
                $desired['bypass(' . $destIface . ')'] = ['kind' => 'bypass', 'iface' => $iface, 'dest' => $destIface];
            }
            $desired['policy(' . $iface . ')'] = ['kind' => 'policy', 'iface' => $iface, 'dest' => ''];
        }

        /* 删除不再需要的规则 + 同名重复项 */
        $removed = 0;
        foreach ($existing as $key => $uuids) {
            if (!isset($desired[$key])) {
                foreach ($uuids as $uuid) {
                    $model->rules->rule->del($uuid);
                    $removed++;
                }
            } else {
                foreach (array_slice($uuids, 1) as $uuid) {
                    $model->rules->rule->del($uuid);
                    $removed++;
                }
            }
        }
        if ($removed > 0) {
            $messages[] = sprintf('firewall: %d obsolete/duplicate rules removed', $removed);
        }

        /* 添加缺失的（浮动规则：不设置 interface；sequence 留空由框架按浮动组递增分配，
           保证「内网直达」排在「策略路由」之前） */
        $added = 0;
        foreach ($desired as $key => $spec) {
            if (isset($existingKey[$key])) {
                continue;
            }
            $rule = $model->rules->rule->Add();
            $rule->enabled = '1';
            $rule->action = 'pass';
            $rule->quick = '1';
            $rule->ipprotocol = 'inet';
            $rule->direction = 'in';
            $rule->description = sprintf('Mihomo %s (%s)', $spec['kind'], $spec['kind'] === 'policy' ? $spec['iface'] : $spec['dest']);
            if ($spec['kind'] === 'policy') {
                $rule->source_net = $spec['iface'];
                $rule->destination_net = 'any';
                $rule->gateway = 'MIHOMO_TUN';
            } else {
                $rule->source_net = $spec['iface'];
                $rule->destination_net = $spec['dest'];
            }
            $added++;
        }
        if ($added > 0) {
            $messages[] = sprintf('firewall: %d floating rules added (%s)', $added, implode(', ', $interfaces));
        }
        if ($added === 0 && $removed === 0 && count($existingKey) === count($desired)) {
            $messages[] = 'firewall: floating rules already in place';
        }

        $validations = $model->performValidation();
        foreach ($validations as $validation) {
            if ($validation->getType() === 'error') {
                throw new \RuntimeException((string)$validation);
            }
        }
        $model->serializeToConfig();
        \OPNsense\Core\Config::getInstance()->save();

        return $messages;
    }

    /** 回滚最近一次网络侧改动 */
    public function netrollbackAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $this->throwReadOnly();
        return $this->configdJson('policy-net-rollback');
    }

    /** 需要自动策略路由的接口列表 */
    private function netPayload(): array
    {
        $interfaces = [];
        foreach ($this->collectRows(true) as $row) {
            if ($row['enabled'] === '0' || $row['firewall'] !== 'auto') {
                continue;
            }
            $interfaces[$row['interface']] = true;
        }
        /* 网关地址留空 -> 由 policy_net.php 从 ifconfig 推断 */
        return ['interfaces' => array_keys($interfaces), 'gateway' => ''];
    }

    private function writeStaging(array $payload): string
    {
        return Config::createStagingFile(json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        ));
    }

    private function configdJson(string $action, array $args = []): array
    {
        $backend = new Backend();
        $output = trim((string)$backend->configdpRun('mihomo ' . $action, $args));
        $decoded = json_decode($output, true);
        if (is_array($decoded)) {
            return $decoded;
        }
        return [
            'status' => 'failed',
            'message' => $output === '' ? gettext('(no output)') : $output,
        ];
    }

    /* ------------------------------------------------------------------ *
     * 绑定自检 / 配置历史
     * ------------------------------------------------------------------ */

    /** 绑定自检：把测试流量真的送进 TUN，回报出口 IP 与命中的规则 */
    public function selftestAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $subnets = Config::interfaceSubnets();
        $tests = [];
        foreach ($this->collectRows(true) as $row) {
            if ($row['enabled'] === '0' || $row['firewall'] !== 'auto') {
                continue;
            }
            $srcIp = Config::interfaceIp($row['interface']);
            if ($srcIp === '') {
                continue;
            }
            $tests[] = [
                'interface' => $row['interface'],
                'source' => $row['source'] !== '' ? $row['source'] : ($subnets[$row['interface']] ?? ''),
                'src_ip' => $srcIp,
                'target' => $row['target'],
            ];
        }
        if ($tests === []) {
            return [
                'status' => 'failed',
                'message' => gettext('Nothing to test: no enabled row requests a firewall rule.'),
            ];
        }

        $staging = null;
        try {
            $staging = $this->writeStaging(['tests' => $tests]);
            return $this->configdJson('selftest', [$staging]);
        } catch (\Throwable $e) {
            return ['status' => 'failed', 'message' => $e->getMessage()];
        } finally {
            if ($staging !== null) {
                @unlink($staging);
            }
        }
    }

    /** 配置历史：列出时间戳备份 */
    public function historyAction()
    {
        $files = glob(Config::FILE . '.bak.*') ?: [];
        rsort($files);
        $rows = [];
        $current = is_file(Config::FILE) ? filesize(Config::FILE) : 0;
        foreach (array_slice($files, 0, 20) as $file) {
            $rows[] = [
                'ts' => str_replace(Config::FILE . '.bak.', '', $file),
                'size' => filesize($file),
                'current_size' => $current,
            ];
        }
        return ['status' => 'ok', 'rows' => $rows, 'current_ts' => date('Ymd_His')];
    }

    /** 配置历史：某个备份的内容与差异 */
    public function historyShowAction($ts = '')
    {
        $file = $this->backupPath($ts);
        if ($file === null) {
            return ['status' => 'failed', 'message' => gettext('Backup not found.')];
        }
        $old = (string)file_get_contents($file);
        $new = is_file(Config::FILE) ? (string)file_get_contents(Config::FILE) : '';
        return [
            'status' => 'ok',
            'ts' => $ts,
            'content' => $old,
            'diff' => $this->lineDiff($old, $new),
        ];
    }

    /** 配置历史：从备份还原（校验后落盘，当前文件自动备份） */
    public function historyRestoreAction()
    {
        $result = ['status' => 'failed', 'messages' => []];
        if (!$this->request->isPost()) {
            $result['message'] = gettext('POST required.');
            return $result;
        }
        $this->throwReadOnly();
        $ts = (string)$this->request->getPost('ts', 'string', '');
        $file = $this->backupPath($ts);
        if ($file === null) {
            $result['message'] = gettext('Backup not found.');
            return $result;
        }
        $backend = new Backend();
        $output = trim((string)$backend->configdpRun('mihomo config-restore', [$file]));
        $result['status'] = stripos($output, 'Restored from') !== false ? 'ok' : 'failed';
        $result['messages'][] = $output === '' ? gettext('(no output)') : $output;
        return $result;
    }

    private function backupPath(string $ts): ?string
    {
        if (!preg_match('/^[0-9_]{8,20}$/', $ts)) {
            return null;
        }
        $file = Config::FILE . '.bak.' . $ts;
        return is_file($file) ? $file : null;
    }

    /** 极简逐行差异（给界面看，不追求 patch 精度） */
    private function lineDiff(string $old, string $new): string
    {
        $a = preg_split("/\r\n|\n|\r/", $old) ?: [];
        $b = preg_split("/\r\n|\n|\r/", $new) ?: [];
        $lines = [];
        $shown = 0;
        $max = max(count($a), count($b));
        for ($i = 0; $i < $max && $shown < 60; $i++) {
            $left = $a[$i] ?? null;
            $right = $b[$i] ?? null;
            if ($left === $right) {
                continue;
            }
            if ($left !== null && !in_array($left, $b, true)) {
                $lines[] = sprintf('%-4d - %s', $i + 1, $left);
            }
            if ($right !== null && !in_array($right, $a, true)) {
                $lines[] = sprintf('%-4d + %s', $i + 1, $right);
            }
            $shown++;
        }
        return implode("\n", $lines);
    }

    /* ------------------------------------------------------------------ *
     * 内部：从模型收集策略行
     * ------------------------------------------------------------------ */

    /**
     * @param bool $withFlags 是否附带 uuid/firewall 等状态字段
     */
    private function collectRows(bool $withFlags = false): array
    {
        $rows = [];
        foreach ($this->getModel()->policyRouting->rule->iterateItems() as $uuid => $item) {
            $row = [
                'enabled' => (string)$item->enabled,
                'interface' => (string)$item->interface,
                'source' => (string)$item->source,
                'scope' => (string)$item->scope,
                'target' => (string)$item->target,
            ];
            if ($withFlags) {
                $row['uuid'] = (string)$uuid;
                $row['firewall'] = (string)$item->firewall;
                $row['descr'] = (string)$item->descr;
            }
            $rows[] = $row;
        }
        return $rows;
    }
}
