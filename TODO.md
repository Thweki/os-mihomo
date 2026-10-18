# TODO / 状态看板

> 每轮工作结束必须更新本文件。图例：`[ ]` 待办 `[~]` 进行中 `[x]` 完成 `[!]` 阻塞 `[-]` 取消

## 阶段总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 侦察：上游源码、目标设备、OPNsense MVC 惯例 | [x] |
| P1 | 工程基建：git、AGENTS.md、远程工具、备份/回滚 | [x] |
| P2 | 设计：页面/接口/数据流、MVC 目录规划 | [x] |
| P3 | 实现：模型 + 控制器 + API | [x] |
| P4 | 实现：Volt 视图（4 页面，OPNsense 原生风格） | [x] |
| P5 | 部署到设备 + 语法/接口验证 | [x] |
| P6 | 视觉验收（agent-browser 截图、与核心页面对照） | [x] |
| P7 | 报告：docs/report.md（含真实截图） | [x] |
| P8 | 收尾：打包脚本、README、回滚演练 | [~] |
| P9 | 修复：表单布尔控件、Apply 落盘链路、补丁器最小化 | [x] |

## 交付结果（2026-10-18）

- 设备最终状态：插件已安装、4 个页面可用、**服务未启用（`mihomo_enable="NO"`）**、**零网络改动**
- 网络指纹（pf/NAT/路由/Unbound）与部署前**逐字节一致**
- 端到端验证：4 页面 200、旧链接 302、20 个 API 200、未授权 302、语法 0 错误
- 截图：`docs/screenshots/` 11 张（含核心页面对照）
- 提交：`8bfe014`（基线）→ `b21013a`（MVC 重写）→ `fa63bbb`（UI 精修）

## P8 收尾（剩余）

- [x] README 重写（指向新 UI，移除"浏览器连 :9090"的旧姿势）
- [x] 版本号提升到 1.1.0（`Makefile` / `version/mihomo`）
- [x] 部署/回滚/体检/取证脚本齐备（`scripts/`、`tools/`）
- [ ] `make package` 实机跑一次（需要一台 FreeBSD/OPNsense 构建机；当前设备侧禁止 `pkg add` 以免触发上游 post-install）
- [ ] 回滚演练（在设备上实跑一次 `cp -a` 恢复；目前备份集齐全但未实跑）
- [ ] 补 `.pot` / `zh_CN` 翻译，消除中英混杂

## 风险与决策记录

| # | 风险/决策 | 结论 |
|---|---|---|
| R1 | 上游 +POST_INSTALL 会改 config.xml/防火墙/Unbound | **不执行**；部署脚本只铺文件，服务默认不 enable |
| R2 | 默认 config.yaml `tun.auto-route: true` + 占位节点 | 服务默认关闭；仪表盘红色安全体检；文档三处警告；只用隔离 demo 实例取证 |
| R3 | `external-controller: 0.0.0.0:9090` 暴露 | 新 UI 全走 loopback 代理；设置页可改为 `127.0.0.1`；文档建议 |
| R4 | 菜单/ACL 缓存导致新页面不出现 | 部署脚本清缓存；且必须 `service configd restart` 才会重载 actions.d |
| R5 | 浏览器直连 :9090 的旧习惯 | README/报告说明新姿势；控制台仍可用但不再是必需 |
| R6 | 主题对所有输入控件加 `max-width: 348px` | 宽文本框内联覆盖 `max-width: 100%` |
| R7 | 侧边栏只支持 3 层菜单 | 菜单结构改为 `VPN → Proxy Suite → 4 项` |
| R8 | PowerShell 5.1 的 ANSI 默认编码损坏 UTF-8 脚本 | `tools/sanitize.py` + `fix_ps1_bom.py` + 传输后 sha256 校验 |
| R9 | 脚本自我调用导致进程风暴（已发生，见报告 §10） | `tools/remote.ps1` 增加"含 `__remote.sh` 即拒跑"护栏 |
| R10 | 表单布尔字段用 `<type>boolean</type>`，`base_form` 不渲染 | 改为 `<type>checkbox</type>`（核心对 base_form 都这么写）；已实测 7 个开关全部正常 |
| R11 | 误判"上游保存配置/日志必然失效" | **已更正**：WebGUI 的 PHP 以 root 运行，上游那些写法可用；文档与日志均已修正 |
| R12 | Apply 会重写受管行从而丢掉行尾注释 | 补丁器改为"值相同不动 + 改动时保留行尾注释"，Apply 实测只产生 1 行 diff |
