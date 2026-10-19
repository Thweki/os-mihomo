<?php

/*
 * os-mihomo 二次开发 —— 设置接口
 *
 * 分工：
 *   · get/set（继承自 ApiMutableModelControllerBase）读写 /conf/config.xml 中的
 *     <OPNsense><mihomo> 节点，作为「期望状态」的暂存区；
 *   · apply 把暂存区真正落到系统文件：
 *       config.yaml（configd + `mihomo -t` 校验 + 备份）
 *       /etc/rc.conf.d/mihomo（开机自启开关）
 *       /usr/local/etc/mihomo/sub/env（订阅地址与密钥）
 *   · import 反向：把系统现状读回暂存区。
 *
 * 服务重启永远是显式动作（restart=1），绝不会因为「保存设置」而自动发生。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Mihomo\Config;
use OPNsense\Mihomo\Inspector;
use OPNsense\Mihomo\RequestParamsTrait;
use OPNsense\Mihomo\Safety;

class SettingsController extends ApiMutableModelControllerBase
{
    use RequestParamsTrait;

    protected static $internalModelName = 'mihomo';
    protected static $internalModelClass = '\OPNsense\Mihomo\Mihomo';
    /** 不在保存时做全模型校验，避免首屏空模型无法落盘 */
    protected static $internalSaveRequiresAdmin = true;

    /**
     * 本插件管理的键：yaml 键 => [值, 来自哪个页面字段, 显示名]。
     *
     * 页面字段 id 必须与表单里的 id 一致（`mihomo.tun.mtu` 这种），
     * 这样「只写入我改过的项」才能把字段名对应到 YAML 键。
     */
    private function managedKeys(): array
    {
        $mdl = $this->getModel();
        $flag = fn ($node) => ((string)$node === '1');
        $keys = [];
        $add = function (string $yamlKey, $value, array $fields, string $label) use (&$keys): void {
            $keys[$yamlKey] = ['value' => $value, 'fields' => $fields, 'label' => $label];
        };

        $add('log-level', (string)$mdl->general->logLevel, ['mihomo.general.logLevel'], gettext('Log Level'));
        $add('mode', (string)$mdl->general->mode, ['mihomo.general.mode'], gettext('Mode'));
        $add('allow-lan', $flag($mdl->general->allowLan), ['mihomo.general.allowLan'], gettext('Allow LAN'));
        $add(
            'external-controller',
            sprintf('%s:%s', (string)$mdl->general->controllerBind, (string)$mdl->general->controllerPort),
            ['mihomo.general.controllerBind', 'mihomo.general.controllerPort'],
            gettext('External Controller')
        );
        $add('secret', (string)$mdl->general->secret, ['mihomo.general.secret'], gettext('Secret'));
        $add('tun.enable', $flag($mdl->tun->enabled), ['mihomo.tun.enabled'], gettext('TUN Mode'));
        $add('tun.device', (string)$mdl->tun->device, ['mihomo.tun.device'], gettext('Device Name'));
        $add('tun.stack', (string)$mdl->tun->stack, ['mihomo.tun.stack'], gettext('Stack'));
        $add('tun.auto-route', $flag($mdl->tun->autoRoute), ['mihomo.tun.autoRoute'], gettext('Automatic Route'));
        $add('tun.strict-route', $flag($mdl->tun->strictRoute), ['mihomo.tun.strictRoute'], gettext('Strict Route'));
        $add('tun.mtu', (int)(string)$mdl->tun->mtu, ['mihomo.tun.mtu'], gettext('MTU'));
        $add('dns.enable', $flag($mdl->dns->enabled), ['mihomo.dns.enabled'], gettext('DNS Module'));
        $add('dns.listen', (string)$mdl->dns->listen, ['mihomo.dns.listen'], gettext('Listen Address'));
        $add('dns.enhanced-mode', (string)$mdl->dns->enhancedMode, ['mihomo.dns.enhancedMode'], gettext('Enhanced Mode'));
        $add('dns.ipv6', $flag($mdl->dns->ipv6), ['mihomo.dns.ipv6'], gettext('DNS over IPv6'));
        $add('ipv6', $flag($mdl->general->ipv6), ['mihomo.general.ipv6'], gettext('IPv6 handling'));
        foreach (Config::snifferKeys($flag($mdl->general->sniffer)) as $key => $value) {
            $add($key, $value, ['mihomo.general.sniffer'], gettext('Domain sniffing'));
        }

        return $keys;
    }

    /**
     * 模型 → config.yaml 的映射。
     * 只列出本插件管理的键；其余内容（proxies / proxy-groups / rules …）原样保留。
     */
    private function modelPatch(): array
    {
        $patch = [];
        foreach ($this->managedKeys() as $key => $info) {
            $patch[$key] = $info['value'];
        }
        return $patch;
    }

    /**
     * 把设置落到系统文件。
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

        $mdl = $this->getModel();
        $backend = new Backend();

        /* ---- 0. 应用方式：默认只写"这次改过的项"（避免把文件里没动过的值覆盖掉）---- */
        $mode = (string)$this->request->getPost('mode', null, 'all');
        $onlyChanged = $mode === 'changed';
        $changedRaw = (string)$this->request->getPost('changed', null, '[]');
        $changedFields = json_decode($changedRaw, true);
        if (!is_array($changedFields)) {
            $changedFields = [];
        }
        $changedFields = array_map('strval', $changedFields);
        [$write, $writtenLabels, $skippedLabels] = Config::selectManagedKeys(
            $this->managedKeys(),
            $changedFields,
            $onlyChanged,
            Config::scan()
        );
        $touched = fn (string $field): bool => !$onlyChanged || in_array($field, $changedFields, true);

        /* ---- 1. config.yaml ---- */
        if ($write === []) {
            $result['messages'][] = gettext('Nothing was changed on this page, so the file was left alone.');
        } else {
            $patch = [];
            foreach ($write as $key => $info) {
                $patch[$key] = $info['value'];
            }
            try {
                $content = Config::patchKeys(Config::rawText(), $patch);
                $staging = Config::createStagingFile($content);
            } catch (\Throwable $e) {
                $result['message'] = $e->getMessage();
                return $result;
            }

            $output = trim((string)$backend->configdpRun('mihomo config-install', [$staging]));
            if (stripos($output, 'installed successfully') === false) {
                $result['message'] = sprintf(
                    gettext('The configuration file was not written. mihomo rejected it:%s'),
                    $output === '' ? ' ' . gettext('(no output)') : "\n" . $output
                );
                return $result;
            }
            $result['messages'][] = sprintf(
                gettext('Configuration file updated: %d item(s) written — %s'),
                count($writtenLabels),
                implode('、', $writtenLabels)
            );
        }
        if ($skippedLabels !== []) {
            $result['messages'][] = sprintf(
                gettext('The page and the file disagree on %d item(s), but you did not touch them, so they were left as they are: %s — press Import to use the file values in the page, or pick "takes precedence" to write them.'),
                count($skippedLabels),
                implode('、', $skippedLabels)
            );
        }

        /* ---- 2. 开机自启 ---- */
        if ($touched('mihomo.general.enabled')) {
            $enabled = (string)$mdl->general->enabled === '1';
            $backend->configdpRun('mihomo set-enabled', [$enabled ? 'yes' : 'no']);
            $result['messages'][] = $enabled
                ? gettext('Service will start automatically on boot.')
                : gettext('Service will not start automatically on boot.');
        }

        /* ---- 3. 订阅凭据（仅在填写时写入，避免清空既有值）---- */
        $url = trim((string)$mdl->subscription->url);
        $secret = trim((string)$mdl->subscription->secret);
        if (($touched('mihomo.subscription.url') || $touched('mihomo.subscription.secret')) && ($url !== '' || $secret !== '')) {
            $out = trim((string)$backend->configdpRun('mihomo env-set', [$url, $secret]));
            if ($out !== '') {
                $result['messages'][] = $out;
            }
        }

        /* ---- 4. 订阅自动更新（写 OPNsense 原生 Cron 任务）---- */
        if ($touched('mihomo.subscription.updateEnabled') || $touched('mihomo.subscription.updateInterval')) {
            try {
                $cronMessage = $this->syncSubscriptionCron(
                    (string)$mdl->subscription->updateEnabled === '1',
                    (string)$mdl->subscription->updateInterval
                );
                if ($cronMessage !== '') {
                    $result['messages'][] = $cronMessage;
                }
            } catch (\Throwable $e) {
                $result['messages'][] = sprintf(gettext('Scheduled task could not be updated: %s'), $e->getMessage());
            }
        }

        /* ---- 5. 显式重启 ---- */
        if ($this->boolParam('restart')) {
            if (!$enabled) {
                $result['messages'][] = gettext('Service is not enabled; nothing to restart.');
            } else {
                $out = trim((string)$backend->configdRun('mihomo restart'));
                $result['messages'][] = $out === ''
                    ? gettext('Service restart requested.')
                    : $out;
            }
        } else {
            $result['messages'][] = gettext(
                'The running service keeps its current in-memory configuration until it is restarted.'
            );
        }

        $result['status'] = 'ok';
        return $result;
    }

    /**
     * 订阅自动更新：在 OPNsense 原生 Cron 里维护一个任务（command = mihomo sub-update）。
     * 关闭时删除该任务；开启时创建/更新。改完让 cron 重新生成 crontab。
     */
    private function syncSubscriptionCron(bool $enabled, string $interval): string
    {
        $hours = ['v6' => '0,6,12,18', 'v12' => '0,12', 'v24' => '0'][$interval] ?? '0';
        $cron = new \OPNsense\Cron\Cron();
        $uuid = null;
        foreach ($cron->jobs->job->iterateItems() as $id => $job) {
            if (str_contains((string)$job->command, 'mihomo sub-update')) {
                $uuid = $id;
                break;
            }
        }

        if ($enabled) {
            $job = $uuid === null
                ? $cron->jobs->job->Add()
                : $cron->getNodeByReference('jobs.job.' . $uuid);
            $job->enabled = '1';
            $job->origin = 'mihomo';
            $job->minutes = '0';
            $job->hours = $hours;
            $job->days = '*';
            $job->months = '*';
            $job->weekdays = '*';
            $job->who = 'root';
            $job->command = 'mihomo sub-update';
            $job->parameters = '';
            $job->description = 'Mihomo subscription update';
        } elseif ($uuid !== null) {
            $cron->jobs->job->del($uuid);
        } else {
            return '';
        }

        $messages = $cron->performValidation();
        foreach ($messages as $message) {
            if ($message->getType() === 'error') {
                throw new \RuntimeException((string)$message);
            }
        }
        $cron->serializeToConfig();
        \OPNsense\Core\Config::getInstance()->save();
        $backend = new Backend();
        $backend->configdRun('cron restart');

        return $enabled
            ? sprintf(gettext('Scheduled task enabled: subscription update (%s).'), $hours)
            : gettext('Scheduled task removed: subscription update.');
    }

    /**
     * 「配置对照」：页面值 / 文件值 / 运行值 三方对照（只读）。
     */
    public function inspectAction()
    {
        return Inspector::report();
    }

    /**
     * 把系统现状读回模型（用于首次使用或手工改过 config.yaml 之后重新同步）。
     */
    public function importAction()
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

        $scan = Config::scan();
        $mdl = $this->getModel();
        $yesNo = fn ($value, string $default = 'false') => in_array(
            strtolower((string)($value ?? $default)),
            ['true', 'yes', 'on', '1'],
            true
        ) ? '1' : '0';

        $mdl->general->enabled = Safety::bootEnabled() ? '1' : '0';
        $mdl->general->logLevel = (string)($scan['log-level'] ?? 'info');
        $mdl->general->mode = (string)($scan['mode'] ?? 'rule');
        $mdl->general->allowLan = $yesNo($scan['allow-lan'] ?? null);

        $controller = (string)($scan['external-controller'] ?? '');
        if ($controller !== '') {
            $parts = explode(':', $controller);
            $port = array_pop($parts);
            $host = trim(implode(':', $parts), '[]');
            if ($host !== '' && in_array($host, ['0.0.0.0', '*', '::'], true)) {
                $host = '127.0.0.1';
            }
            if ($host !== '') {
                $mdl->general->controllerBind = $host;
            }
            if (ctype_digit((string)$port)) {
                $mdl->general->controllerPort = (string)$port;
            }
        }
        $mdl->general->secret = (string)($scan['secret'] ?? '');

        $mdl->tun->enabled = $yesNo($scan['tun.enable'] ?? null);
        $mdl->tun->device = (string)($scan['tun.device'] ?? 'tun_mihomo');
        $mdl->tun->stack = (string)($scan['tun.stack'] ?? 'gvisor');
        $mdl->tun->autoRoute = $yesNo($scan['tun.auto-route'] ?? null);
        $mdl->tun->strictRoute = $yesNo($scan['tun.strict-route'] ?? null);
        if (isset($scan['tun.mtu']) && is_numeric($scan['tun.mtu'])) {
            $mdl->tun->mtu = (string)(int)$scan['tun.mtu'];
        }

        $mdl->dns->enabled = $yesNo($scan['dns.enable'] ?? null);
        $mdl->dns->listen = (string)($scan['dns.listen'] ?? '127.0.0.1:1053');
        $mdl->dns->enhancedMode = (string)($scan['dns.enhanced-mode'] ?? 'fake-ip');

        $env = \OPNsense\Mihomo\Subscription::env();
        if (!empty($env['mihomo_URL'])) {
            $mdl->subscription->url = (string)$env['mihomo_URL'];
        }
        if (array_key_exists('mihomo_secret', $env)) {
            $mdl->subscription->secret = (string)$env['mihomo_secret'];
        }

        $save = $this->save();
        $result['messages'][] = gettext('Settings imported from the active configuration.');
        $result['status'] = 'ok';
        $result['save'] = $save;
        return $result;
    }

    /**
     * 读取原始 config.yaml。
     */
    public function configGetAction()
    {
        return [
            'status' => Config::exists() ? 'ok' : 'failed',
            'file' => Config::FILE,
            'content' => Config::rawText(),
            'bytes' => Config::exists() ? filesize(Config::FILE) : 0,
            'editable' => Config::exists(),
        ];
    }

    /**
     * 校验一段配置内容（不落盘）。
     */
    public function configValidateAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $content = (string)$this->param('content', '');
        if (trim($content) === '') {
            return ['status' => 'failed', 'message' => gettext('Configuration content must not be empty.')];
        }
        try {
            $staging = Config::createStagingFile($content);
        } catch (\Throwable $e) {
            return ['status' => 'failed', 'message' => $e->getMessage()];
        }
        $output = trim((string)(new Backend())->configdpRun('mihomo config-check', [$staging]));
        $ok = str_contains($output, 'validation passed');
        return [
            'status' => $ok ? 'ok' : 'failed',
            'message' => $output === '' ? gettext('No output from the configuration test.') : $output,
        ];
    }

    /**
     * 落盘一段配置内容（先校验，再备份，最后安装）。
     */
    public function configSetAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $this->throwReadOnly();
        $content = (string)$this->param('content', '');
        if (trim($content) === '') {
            return ['status' => 'failed', 'message' => gettext('Configuration content must not be empty.')];
        }
        try {
            $staging = Config::createStagingFile($content);
        } catch (\Throwable $e) {
            return ['status' => 'failed', 'message' => $e->getMessage()];
        }
        $output = trim((string)(new Backend())->configdpRun('mihomo config-install', [$staging]));
        $ok = str_contains($output, 'installed successfully');
        return [
            'status' => $ok ? 'ok' : 'failed',
            'message' => $output === '' ? gettext('No output from the configuration test.') : $output,
        ];
    }

    /**
     * 校验当前已安装的配置。
     */
    public function configTestAction()
    {
        $output = trim((string)(new Backend())->configdRun('mihomo config-current'));
        $ok = !str_contains($output, 'invalid') && !str_contains($output, 'error');
        return [
            'status' => $ok ? 'ok' : 'failed',
            'message' => $output === ''
                ? gettext('No output from the configuration test.')
                : Safety::shorten($output, 12),
        ];
    }
}
