<?php

/*
 * os-mihomo 二次开发 —— 日志接口
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Mihomo\Logs;
use OPNsense\Mihomo\RequestParamsTrait;

class LogController extends ApiControllerBase
{
    use RequestParamsTrait;

    /** 读取日志尾部 */
    public function tailAction()
    {
        $key = $this->stringParam('key', 'mihomo');
        if (!in_array($key, Logs::KEYS, true)) {
            return ['status' => 'failed', 'message' => gettext('Unknown log file.'), 'content' => ''];
        }
        return [
            'status' => 'ok',
            'key' => $key,
            'content' => Logs::tail($key, $this->intParam('lines', 300)),
        ];
    }

    /** 清空日志 */
    public function clearAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $this->throwReadOnly();
        $key = $this->stringParam('key', 'mihomo');
        if (!in_array($key, Logs::KEYS, true)) {
            return ['status' => 'failed', 'message' => gettext('Unknown log file.')];
        }
        $output = Logs::clear($key);
        return [
            'status' => 'ok',
            'message' => $output === '' ? gettext('Log file cleared.') : $output,
        ];
    }
}
