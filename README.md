# os-mihomo

[![CI](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml/badge.svg)](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml)
[English](README.US.md)

在 OPNsense WebGUI 内管理 Mihomo 的插件。页面使用 OPNsense 原生 MVC、表单和表格，直接继承当前主题；浏览器通过插件 API 访问内核控制器。

## 功能

- **概览**：实时速率、累计流量、活动连接、代理分组、节点延迟及运行模式。
- **流量趋势**：最近 1 分钟、5 分钟、15 分钟和 1 小时切换，流量统一保留一位小数。历史仅在当前页面打开时采集，缺失样本显示为空白。
- **设置**：原生表单与逐项写入控制；高级模式收纳控制器、TUN 和 DNS 细项。
- **高级配置**：YAML 默认只读，解锁后编辑，保存前核对改动；服务端先备份并校验，再替换文件。
- **配置对照**：查看页面值、文件值和运行值，未知值单独标明。
- **路由策略**：按接口设置代理去向，支持变更预览和配置历史。
- **订阅与日志**：更新订阅，查看、下载和清空内核或订阅日志。
- **语言与主题**：英文与简体中文，提供 gettext 翻译模板。图表从当前主题的语义样式取色，无插件主题开关。

菜单入口：`VPN → Proxy Suite`。页面位于 `/ui/mihomo/*`，接口位于 `/api/mihomo/*`。不嵌入第三方面板，也不要求浏览器直接访问控制器端口。

## 环境

当前构建目标为 **OPNsense 26.7 / FreeBSD 15 amd64**。插件版本为 `1.1.0`，内核版本为 `1.19.31-vincent`。其他系统版本需要单独验证。

## 获取与安装

从 [Actions](https://github.com/Thweki/os-mihomo/actions/workflows/ci.yml) 中下载成功构建的 `os-mihomo-freebsd15-amd64` 产物，或自行构建。产物包含插件包、插件仓库压缩包、文件清单和 SHA-256 校验和。

在目标系统上核对下载文件：

```sh
while read -r expected file; do
    sha256 -c "$expected" "$file" || exit 1
done < SHA256SUMS
pkg add os-mihomo.pkg
```

新装默认不自启。安装钩子仅安装文件，不自动创建接口或防火墙规则、不修改路由和 DNS，也不启动服务。运行配置以 `.sample` 分发，只在目标文件不存在时复制，已有配置保留。

安装后先配置有效节点或订阅，再按实际网络需求配置 TUN、DNS 和策略。设置页和策略页的“应用”会写入对应配置，请先核对预览。订阅更新会根据模板重建配置，手工编辑可能被替换。

从其他来源的同名插件迁移前，请备份配置并检查原包的卸载钩子。卸载本插件前，应先解除依赖它的网络策略并停止服务；本版本卸载时保留用户配置。

## 构建与检查

在 FreeBSD 15 amd64 上运行，需要 `pkg`、`tar`、`xz`、`sha256` 和 `fetch` 或 `curl`：

```sh
make package   # dist/os-mihomo.pkg
make repo      # dist/repo/<ABI>/
```

内核使用固定版本与 SHA-256 校验，来源记录在 [binary-source.json](packaging/freebsd/binary-source.json)。构建只生成包，不安装插件或执行包钩子。

源码检查需要 Python 3、Node.js、PHP 和 POSIX shell：

```sh
python3 tools/validate.py
```

[CI/CD 说明](docs/ci-cd.md)介绍自动检查、构建产物与标签发布流程。

## 翻译

编辑 `locales/<locale>.po`，参照 `locales/os-mihomo.pot`，然后生成并提交插件翻译文件：

```sh
python3 tools/build_locales.py
python3 tools/build_locales.py --check
```

插件使用独立 gettext 域，不改系统翻译文件；没有译文时回退到系统翻译或英文。

## 来源

- [Opnwall/OPNsense-repo](https://github.com/Opnwall/OPNsense-repo)：插件运行资产与打包基础。
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)：Mihomo 内核。
- [Vincent-Loeng/clash-meta](https://github.com/Vincent-Loeng/clash-meta)：FreeBSD 内核构建。

各源文件保留其原始版权和许可声明。
