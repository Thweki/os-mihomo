<?php

/*
 * os-mihomo 二次开发 —— 设置页控制器
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

class SettingsController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->formSettings = $this->getForm('settings');
        /* 「不修改」开关只装在 config.yaml 的键上：插件自己的状态（开机自启/订阅/自动更新）
           与写死的项（设备名/协议栈）不给开关，始终由插件写 */
        $this->view->alwaysOwnedFields = implode(',', Config::fieldsWithoutSwitch());
        $pairs = [];
        foreach (Config::FIXED_SETTINGS as $field => $info) {
            $pairs[] = $field . '=' . $info['value'];
        }
        $this->view->fixedSettingPairs = implode(',', $pairs);
        $this->view->pick('OPNsense/Mihomo/settings');
    }
}
