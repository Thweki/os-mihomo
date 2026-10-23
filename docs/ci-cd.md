# CI/CD

仓库：<https://github.com/Thweki/os-mihomo>。工作流：`.github/workflows/ci.yml`。

每次 push / pull request / 手动运行，先检查 PHP 语法、XML、翻译目录、包含引号的译文在 JavaScript 中的安全编码、流量计算与断线/重置/缓存场景，以及维护中的部署和构建脚本语法。全部通过后，在隔离的 FreeBSD 15.1 amd64 VM 内打包，读取包清单确认页面、JS、翻译齐全且不包含运行配置。构建不安装插件，不执行包钩子。

产物保存 14 天：`os-mihomo.pkg`、`os-mihomo-repository.tar.gz`、`SHA256SUMS`、`package-files.txt`。仓库压缩包可解开后由静态服务器托管；内部客户端配置中的 URL 需要填写实际地址，当前未发布静态仓库站点。校验和用于检测下载损坏，当前未配置独立签名密钥。

推送 `v<版本>` 标签时，必须与 Makefile 的 VERSION 相同；成功后自动创建附带以上产物的 GitHub Release **草稿**。确认版本、校验和及变更说明后再发布草稿。普通分支推送只产生构建产物，不发版。没有到真实路由器的自动部署任务，也不保存设备凭据。

```sh
python3 tools/build_locales.py --check
python3 tools/validate.py
# 在 FreeBSD 上构建，不安装：
sh scripts/ci_build.sh
```

Windows 无 PHP 时可执行 `python tools/validate.py --frontend-only`；它不替代 CI 的 PHP 检查。真机 UI-only 部署会先对暂存的 PHP 文件执行 `php -l`。

所有 Actions 固定到提交 SHA，由 Dependabot 每周检查更新。工作流默认只读，只有标签发布草稿的 job 拥有 `contents: write`；检出代码不持久化凭据。参考：[GitHub artifact action](https://github.com/actions/upload-artifact)、[FreeBSD VM action](https://github.com/vmactions/freebsd-vm)。

翻译：编辑 `locales/<locale>.po`，运行 `python tools/build_locales.py`，提交生成的插件 `.mo`。`locales/os-mihomo.pot` 提供待译词条。插件使用独立 gettext 域，不修改系统 OPNsense.mo；没有译文时回退到系统翻译或英文。前端译文通过 JSON 编码，支持引号、反斜杠和非 ASCII 字符。

公开发布前核验（2026-10-24）：检查 1299 个历史文本 blob，未发现 GitHub token、私钥或带账号密码的 URL；用户提供的设备口令不在 Git 历史中。历史配置内三类凭据样例逐字节匹配公开上游固定提交 `f181fdc5432bdfbfe71e23d32401b1d5db2b6f61` 的 [config.yaml](https://github.com/Opnwall/OPNsense-repo/blob/f181fdc5432bdfbfe71e23d32401b1d5db2b6f61/src/os-mihomo/src/usr/local/etc/mihomo/config.yaml)，并非从当前设备导出的值。当前随包配置已统一使用 `example-*`、全零 UUID 和示例公钥，控制器默认仅监听回环。日志、本地配置、设备导出参考资料不纳入 Git。
