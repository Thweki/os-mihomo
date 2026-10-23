<?php

/*
 * os-mihomo 二次开发 —— 订阅页控制器
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

class SubscriptionController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->mihomoLang = new Translator();
        $this->view->pick('OPNsense/Mihomo/subscription');
    }
}
