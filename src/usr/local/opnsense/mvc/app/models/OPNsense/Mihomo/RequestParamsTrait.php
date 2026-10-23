<?php

/*
 * os-mihomo 二次开发 —— API 参数读取辅助
 *
 * OPNsense 前端有两套 POST 约定：
 *   · UIBootgrid / SimpleActionButton → application/x-www-form-urlencoded（$_POST 有值）
 *   · ajaxCall / ajaxPost            → application/json（$_POST 为空，需读原始 body）
 * 两种都可能在插件里被用到，这里统一兼容。
 *
 * Copyright (C) 2026  os-mihomo contributors
 * All rights reserved.
 * 详见 Config.php 头部的 BSD 许可条款。
 */

namespace OPNsense\Mihomo;

trait RequestParamsTrait
{
    /** @var array|null 解析后的 JSON body 缓存 */
    private ?array $mihomoJsonBody = null;

    protected function mihomoJsonBody(): array
    {
        if ($this->mihomoJsonBody === null) {
            $decoded = $this->request->getJsonRawBody();
            $this->mihomoJsonBody = is_array($decoded) ? $decoded : [];
        }
        return $this->mihomoJsonBody;
    }

    /**
     * 依次从 POST、JSON body、GET 中取值。
     */
    protected function param(string $name, mixed $default = null): mixed
    {
        $value = $this->request->getPost($name, null, null);
        if ($value === null) {
            $body = $this->mihomoJsonBody();
            $value = array_key_exists($name, $body) ? $body[$name] : null;
        }
        if ($value === null) {
            $value = $this->request->getQuery($name, null, null);
        }
        return $value ?? $default;
    }

    protected function boolParam(string $name, bool $default = false): bool
    {
        $value = $this->param($name, null);
        if ($value === null) {
            return $default;
        }
        return in_array(strtolower((string)$value), ['1', 'yes', 'true', 'on'], true);
    }

    protected function intParam(string $name, int $default = 0): int
    {
        $value = $this->param($name, null);
        return $value === null || !is_numeric($value) ? $default : (int)$value;
    }

    protected function stringParam(string $name, string $default = ''): string
    {
        $value = $this->param($name, null);
        return $value === null ? $default : trim((string)$value);
    }

    /** 请求是否携带了该参数（用于区分「显式传空」与「没传」） */
    protected function hasParam(string $name): bool
    {
        return $this->request->hasPost($name) || array_key_exists($name, $this->mihomoJsonBody()) || $this->request->hasQuery($name);
    }
}
