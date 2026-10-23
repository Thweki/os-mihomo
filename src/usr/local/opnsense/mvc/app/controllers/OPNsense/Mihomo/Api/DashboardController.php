<?php

/*
 * os-mihomo 二次开发 —— 概览页数据接口
 *
 * 所有数据由服务端（php-fpm, www 用户）通过 loopback 从 mihomo 的 RESTful
 * 控制器取回，再以 OPNsense API 的形式返回给浏览器。
 * 浏览器端不会、也不需要直连 127.0.0.1:9090。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Mihomo\Config;
use OPNsense\Mihomo\Controller;
use OPNsense\Mihomo\RequestParamsTrait;
use OPNsense\Mihomo\Safety;

class DashboardController extends ApiControllerBase
{
    use RequestParamsTrait;

    public function runtimeStatusAction()
    {
        $raw = (new \OPNsense\Core\Backend())->configdRun('mihomo runtime-status');
        $data = json_decode((string)$raw, true);
        return is_array($data) ? $data : ['status' => 'failed'];
    }

    /** 概览卡片 + 运行态摘要 */
    public function overviewAction()
    {
        $version = Controller::version();
        $running = Controller::runningConfig();
        $snapshot = Controller::snapshot();
        $configured = Config::scan();

        return [
            'controller' => [
                'alive' => $version !== null,
                'version' => (string)($version['version'] ?? ''),
                'meta' => (bool)($version['meta'] ?? false),
            ],
            'runtime' => [
                'mode' => (string)($running['mode'] ?? ($configured['mode'] ?? '')),
                'logLevel' => (string)($running['log-level'] ?? ($configured['log-level'] ?? '')),
                'downloadTotal' => (int)($snapshot['downloadTotal'] ?? 0),
                'uploadTotal' => (int)($snapshot['uploadTotal'] ?? 0),
                'memory' => (int)($snapshot['memory'] ?? 0),
                'connections' => $snapshot['ready'] ? count($snapshot['connections']) : 0,
                'ready' => $snapshot['ready'],
                'error' => (string)($snapshot['error'] ?? ''),
            ],
            'config' => [
                'file' => Config::FILE,
                'exists' => Config::exists(),
                'controllerBase' => (string)(Config::controllerBase() ?? ''),
                'tunEnabled' => Config::bool('tun.enable'),
                'tunDevice' => (string)($configured['tun.device'] ?? ''),
                'tunAutoRoute' => Config::bool('tun.auto-route'),
                'allowLan' => Config::bool('allow-lan'),
                'bootEnabled' => Safety::bootEnabled(),
            ],
        ];
    }

    /** 代理分组与成员 */
    public function proxiesAction()
    {
        $result = Controller::proxyGroups();
        return [
            'ready' => $result['ready'],
            'error' => $result['error'],
            'groups' => $result['groups'],
        ];
    }

    /** 选择分组内的节点 */
    public function selectProxyAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $group = $this->stringParam('group');
        $member = $this->stringParam('member');
        if ($group === '' || $member === '') {
            return ['status' => 'failed', 'message' => gettext('Group and member are required.')];
        }
        $result = Controller::selectProxy($group, $member);
        return [
            'status' => $result['ok'] ? 'ok' : 'failed',
            'message' => $result['ok']
                ? sprintf(gettext('Switched "%s" to "%s".'), $group, $member)
                : $result['error'],
        ];
    }

    /** 单节点延迟测速 */
    public function testDelayAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $name = $this->stringParam('name');
        if ($name === '') {
            return ['status' => 'failed', 'message' => gettext('A node name is required.')];
        }
        $result = Controller::testDelay($name);
        return [
            'status' => $result['ok'] ? 'ok' : 'failed',
            'delay' => $result['delay'],
            'message' => $result['ok'] ? '' : $result['error'],
        ];
    }

    /** 切换运行模式 */
    public function setModeAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $mode = $this->stringParam('mode');
        $result = Controller::setMode($mode);
        return [
            'status' => $result['ok'] ? 'ok' : 'failed',
            'message' => $result['ok']
                ? sprintf(gettext('Mode switched to %s.'), $mode)
                : $result['error'],
        ];
    }

    /** 连接列表（服务端分页/搜索/排序，直接对接 UIBootgrid） */
    public function connectionsAction()
    {
        $result = Controller::connectionRows();

        $rows = $this->searchRecordsetBase(
            $result['rows'],
            ['host', 'source', 'destination', 'network', 'type', 'rule', 'rulePayload', 'chain', 'outbound'],
            'start'
        );

        return $rows + [
            'downloadTotal' => (int)($result['downloadTotal'] ?? 0),
            'uploadTotal' => (int)($result['uploadTotal'] ?? 0),
            'memory' => (int)($result['memory'] ?? 0),
            'ready' => (bool)$result['ready'],
            'error' => (string)($result['error'] ?? ''),
        ];
    }

    /** 关闭单条连接（id 为空表示全部） */
    public function closeConnectionAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('POST required.')];
        }
        $id = $this->stringParam('id');
        $result = Controller::closeConnection($id);
        return [
            'status' => $result['ok'] ? 'ok' : 'failed',
            'message' => $result['ok']
                ? ($id === '' ? gettext('All connections closed.') : gettext('Connection closed.'))
                : $result['error'],
        ];
    }

    /** 安全体检（validate=1 时额外做一次配置语法校验，较慢） */
    public function safetyAction()
    {
        return Safety::report($this->boolParam('validate'));
    }
}
