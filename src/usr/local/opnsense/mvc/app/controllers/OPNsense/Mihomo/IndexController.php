<?php

/*
 * os-mihomo 二次开发 —— 概览页控制器
 *
 * 页面本身只负责挂载 Volt 视图；所有数据经 /api/mihomo/* 取回。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

class IndexController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->mihomoLang = new Translator();
        $this->view->pick('OPNsense/Mihomo/index');
    }
}
