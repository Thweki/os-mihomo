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
        $subnets = Config::interfaceSubnets();
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

    /** 应用网络侧变更（写 config.xml + filter reload） */
    public function netapplyAction()
    {
        $result = ['status' => 'failed', 'messages' => []];
        if (!$this->request->isPost()) {
            $result['message'] = gettext('POST required.');
            return $result;
        }
        $this->throwReadOnly();

        $payload = $this->netPayload();
        if ($payload['interfaces'] === []) {
            $result['message'] = gettext(
                'No row requests automatic policy routing: enable a row and set its policy routing to "Automatic".'
            );
            return $result;
        }

        $staging = null;
        try {
            $staging = $this->writeStaging($payload);
            return $this->configdJson('policy-net-apply', [$staging]);
        } catch (\Throwable $e) {
            $result['message'] = $e->getMessage();
            return $result;
        } finally {
            if ($staging !== null) {
                @unlink($staging);
            }
        }
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
