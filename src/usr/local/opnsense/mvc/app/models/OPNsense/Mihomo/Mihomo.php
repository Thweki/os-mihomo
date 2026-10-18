<?php

/*
 * os-mihomo 二次开发 —— 设置模型
 *
 * 存储位置: /conf/config.xml 的 <OPNsense><mihomo> 节点（OPNsense 原生模型机制）。
 * 该节点不参与任何网络行为，仅由 /ui/mihomo/settings 读写。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

use OPNsense\Base\BaseModel;

class Mihomo extends BaseModel
{
}
