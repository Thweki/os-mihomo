<?php

/*
 * os-mihomo 二次开发 —— 服务控制接口
 *
 * 继承 OPNsense 标准的 ApiMutableServiceControllerBase，
 * 因此 /api/mihomo/service/{start,stop,restart,status,reconfigure} 与
 * 前端的 updateServiceControlUI('mihomo') 天然兼容。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Mihomo\RequestParamsTrait;
use OPNsense\Mihomo\Safety;

class ServiceController extends ApiMutableServiceControllerBase
{
    use RequestParamsTrait;

    protected static $internalServiceName = 'mihomo';
    protected static $internalServiceClass = '\OPNsense\Mihomo\Mihomo';
    protected static $internalServiceEnabled = 'general.enabled';

    /**
     * 安全体检。validate=1 时额外执行一次配置语法校验（约 1 秒）。
     */
    public function safetyAction()
    {
        return Safety::report($this->boolParam('validate'));
    }

    /**
     * 重启前是否强制 stop→start（mihomo 没有 reload 命令）。
     */
    protected function reconfigureForceRestart()
    {
        return true;
    }
}
