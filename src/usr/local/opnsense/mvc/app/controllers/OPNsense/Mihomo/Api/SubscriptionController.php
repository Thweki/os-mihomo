<?php

/*
 * os-mihomo 二次开发 —— 订阅接口
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Mihomo\RequestParamsTrait;
use OPNsense\Mihomo\Subscription;
use OPNsense\Mihomo\WriteCoordinator;
use OPNsense\Mihomo\ActionResult;

class SubscriptionController extends ApiControllerBase
{
    use RequestParamsTrait;

    /** 读取订阅设置（来自 env 文件）+ 上游脚本是否存在 */
    public function getAction()
    {
        $lock = new WriteCoordinator();
        $env = Subscription::env();
        return [
            'version' => WriteCoordinator::revision(Subscription::ENV_FILE),
            'url' => (string)($env['mihomo_URL'] ?? ''),
            'secret' => (string)($env['mihomo_secret'] ?? ''),
            'envFile' => Subscription::ENV_FILE,
            'scriptAvailable' => is_file('/usr/local/etc/mihomo/sub/sub.sh'),
            'runnerAvailable' => is_file('/usr/local/opnsense/scripts/mihomo/subscription_run.sh'),
        ];
    }

    /**
     * 先保存模型里的订阅设置，再同步到 env 文件。
     * （模型保存由 /api/mihomo/settings/set 负责，这里只同步 env。）
     */
    public function saveAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $this->throwReadOnly();

        $url = $this->stringParam('url');
        $secret = $this->stringParam('secret');

        if ($url !== '' && !preg_match('@^https?://\S+$@i', $url)) {
            return [
                'status' => 'failed',
                'message' => gettext('Only HTTP or HTTPS subscription URLs are allowed.'),
            ];
        }

        $version = $this->stringParam('version');
        if ($version === '') {
            return ActionResult::make('failed', false, 'conflict', 'Reload the subscription settings before saving.');
        }
        return ActionResult::parse(Subscription::saveEnv($url, $secret, $version));
    }

    public function statusAction()
    {
        return Subscription::status();
    }

    /** 触发订阅更新 */
    public function runAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $this->throwReadOnly();

        $env = Subscription::env();
        if (trim((string)($env['mihomo_URL'] ?? '')) === '') {
            return [
                'status' => 'failed',
                'message' => gettext('Set a subscription URL before starting an update.'),
            ];
        }

        $restart = $this->boolParam('restart');
        return ActionResult::parse(Subscription::run($restart));
    }

    /** 读取订阅日志 */
    public function logAction()
    {
        return [
            'status' => 'ok',
            'content' => Subscription::log($this->intParam('lines', 300)),
        ];
    }

    /** 清空订阅日志 */
    public function clearLogAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $this->throwReadOnly();
        $output = Subscription::clearLog();
        return [
            'status' => 'ok',
            'message' => $output === '' ? gettext('Log file cleared.') : $output,
        ];
    }
}
