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
     * 覆盖基类的服务状态判定。
     *
     * 基类在「服务未启用（rcvar=NO）」时返回 "disabled"，而核心 JS
     * (updateServiceControlUI) 对 "disabled" 不渲染任何按钮 —— 于是
     * 「关掉开机自启」就等于「界面上再也无法启动/停止服务」，这在
     * 「先手动试跑、确认可用后再开自启」的场景下完全说不通。
     *
     * 这里把 "disabled" 归一到 "stopped"：启动/停止按钮始终可用；
     * 「是否开机自启」只由设置页的复选框与仪表盘的安全体检横幅表达。
     */
    public function statusAction()
    {
        $result = parent::statusAction();
        if (($result['status'] ?? '') === 'disabled') {
            $result['status'] = 'stopped';
            $result['boot_enabled'] = false;
        } else {
            $result['boot_enabled'] = (string)$this->getModel()->general->enabled === '1';
        }

        return $result;
    }

    /**
     * 重启前是否强制 stop→start（mihomo 没有 reload 命令）。
     */
    protected function reconfigureForceRestart()
    {
        return true;
    }
}
