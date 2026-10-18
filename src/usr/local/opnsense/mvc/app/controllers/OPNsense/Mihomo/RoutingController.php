<?php

/*
 * os-mihomo —— 路由策略页面控制器
 *
 * 页面形态与核心「防火墙: 规则」一致：UIBootgrid 表格 + 行编辑对话框 + 底部应用按钮，
 * 数据存 config.xml 的 <OPNsense><mihomo><policyRouting> 节点，
 * 「应用」时由 Api\RoutingController 渲染成 mihomo 规则并交给 configd 落盘。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved. 详见 models/OPNsense/Mihomo/Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

class RoutingController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->formDialogPolicyRule = $this->getForm('policy_rule');
        $this->view->formGridPolicy = $this->getFormGrid('policy_rule');
        $this->view->pick('OPNsense/Mihomo/routing');
    }
}
