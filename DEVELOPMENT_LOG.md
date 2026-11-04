# CoMex 开发日志

本日志记录已经完成并可验证的开发工作。时间统一采用北京时间
`Asia/Shanghai`，最新记录排列在最前。未完成或尚未提交的并行工作不记为
“已完成”。

每次开发完成必须记录：完成时间、应用版本与构建号、改动内容、主要文件、
验证结果以及分支/提交信息。版本来源以 `Resources/Info.plist` 为准。

## 进行中版本

### 2026-11-04 14:35:05 CST (UTC+08:00) — 统一 Codex 服务名称与双服务菜单栏

- 版本：`0.3.1`（Build `31`），由 `scripts/sync_version.sh` 同步，源 plist 与最终安装包一致。
- 完成内容：先统一界面、通知及文档中的 Codex 服务名称，保持 Grok Bot 不变；再新增默认 C / G 双进度条、双服务数字与最高值三种菜单栏模式。悬停提示分别显示已用和剩余，关闭、过期、读取失败及无效数据不显示旧比例；每分钟重新检查时效。选择持久化保存。
- 主要文件：`Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、`UsageMonitor.swift`、`MenuBarUsageController.swift`、`Sources/UsageCore/MenuBarUsage.swift`、`Tests/UsageCoreTests/MenuBarUsageTests.swift`、`Resources/Info.plist`、README、服务及界面说明、更新日志和本日志。
- 验证：最终 `swift build && swift test` 通过，23 项 XCTest 零失败；Release 打包、安装包 `codesign --verify --deep --strict`、源／安装包 plist 校验及可执行文件一致性比较通过。源码及最终安装 App bundle 的旧服务名称 `grep -R -a -l` 均返回 1（零匹配）。`git diff --check` 通过。
- 界面验证：安装版主窗口和菜单栏弹出面板的 Codex 文案正确；三种设置选项可选择、保存，最高值模式跨重启保留，数字模式重新打开设置后保留；交付时已恢复双进度条。源绘制器在浅／深色背景与 1×／2× 下检查正常和灰色禁用状态，预览仅留在被忽略的 `.impeccable/review/menubar-render/`，不是屏幕截图。
- 安装：备份旧安装到被忽略的 `archive-dist/pre-menubar/`，覆盖 `/Applications/Codex Usage Alert.app` 并重启；实际版本 `0.3.1 / 31`。
- 发布检查：74 个跟踪及未忽略文件的常见密钥、凭据、个人主目录路径及敏感文件名规则扫描零命中；本机用量数据、预览与备份未纳入提交。目标为 `Allenth/CodexUsageAlert` 的 `main`，使用普通推送，结果以远端提交核对为准。
- 限制：区域和整屏 `screencapture` 分别返回 `could not create image from rect`、`could not create image from display`，原生工具仅提供应用窗口／弹出面板截图，未能生成任务指定的 `~/agent-tools/menubar.png`。未实机验证系统深浅模式切换、悬停提示弹出和 VoiceOver 朗读；绘制检查不等同于这些实机验证。
- 分支：`main`；提交：pending commit。

### 2026-11-04 14:00:15 CST (UTC+08:00) — 按双服务设计图校准界面并覆盖安装

- 版本：`0.3.0`（Build `30`），由 `scripts/sync_version.sh` 同步并与安装包核对。
- 完成内容：将两张指定原图移入 `docs/design-v2/`，校准横向双环卡片、全宽服务切换、独立指标、绿色预算条、紧凑用量摘要、双服务状态、刷新按钮与页脚；显示最近更新时间和需注意服务数量。保留 Codex、Grok Bot 和应用名称。Token 图表可展开查看，月度统计明确标为“本月”。
- 主要文件：`Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、`Resources/Info.plist`、`docs/design-v2/`、`docs/usage-v2-ui.md`、`CHANGELOG.md`、本日志。
- 验证：最终 `swift build && swift test` 通过，19 项 XCTest 零失败；`scripts/build_app.sh` Release 打包通过；安装包 `codesign --verify --deep --strict`、源／安装包 plist 校验、可执行文件一致性比较及 `git diff --check` 通过。原生主窗口和菜单栏面板视觉检查双服务状态、切换、加载态、Token 展开／收起与设置入口；本机截图保留于被忽略的 `.impeccable/review/`。
- Grok 数据：安装后实际界面显示 `42.8%`、`11月10日 重置`，详情为剩余 `57.2%`、今日／本周期均 `0` 次；读取标准 Application Support 目录中的 `grok-usage.json`，修改前后 SHA-256 一致，未替换为设计示例数据。
- 安装：旧安装可恢复备份位于被忽略的 `archive-dist/pre-design-v2/`；覆盖安装 `/Applications/Codex Usage Alert.app` 并重启，实读版本 `0.3.0 / 30`。
- 发布检查：71 个跟踪及未忽略文件的常见密钥、凭据、个人主目录路径和敏感文件名规则扫描无命中；两张新 PNG 无文本／EXIF 元数据。数据 JSON、本机截图与应用备份均未纳入提交。以普通快进推送发布到 `Allenth/CodexUsageAlert` 的 `main`，推送结果以远端提交为准。
- 限制：本机系统通知仍为“未允许”，未验证通知横幅送达、VoiceOver 朗读或其他 macOS 版本。原图的示例预测文字以真实用量／重置状态替代；未对未提供的周期 Token 数据作推算。
- 分支：`release/usage-v2`；目标远端分支：`main`。
- 提交：pending commit。

### 2026-11-04 13:47:27 CST (UTC+08:00) — 双服务用量监控与本机安装

- 版本：`0.2.9`（Build `29`）。
- 完成内容：标题改为“用量预警”，新增 Codex 与 Grok Bot 双环卡片、详情切换、共用预警及来源页脚；菜单栏取已开启且有效服务的最高百分比。Grok Bot 读取本地 JSON，提供手动百分比／重置时间填写与独立监控开关；缺失、无效、超过 24 小时数据均安全显示状态。独立记录每日 5/10/15/20 阈值，跨重启和周期重置去重，迁移旧版 Codex 基线。
- 主要文件：`Sources/CodexUsageAlert/`、`Sources/UsageCore/GrokUsage.swift`、`Tests/UsageCoreTests/GrokUsageTests.swift`、`Resources/Info.plist`、`scripts/build_app.sh`、`README.md`、`docs/grok-usage-format.md`、`docs/usage-v2-ui.md`、`.gitignore`、更新日志；清理合并说明与旧日志中的本机路径。
- 验证：最终 `swift build && swift test` 通过，19 项 XCTest 零失败；`scripts/build_app.sh` Release 打包通过，安装包 `codesign --verify --deep --strict`、plist 校验、Shell 语法检查和 `git diff --check` 通过。实际界面验证 Codex 真实额度／Token、服务切换、Grok 未接入／18% 手动记录／过期状态、越界 101 拒绝、独立关闭与重启持久化；测试文件与 Grok 基线已恢复。原生截图复核后修正预算刻度，修复复核结果 ship。未将规则测试等同于系统通知展示。
- 安装：原进程从旧源码的打包目录运行，标准应用目录没有旧安装。退出原进程后安装并启动 `/Applications/Codex Usage Alert.app`，实读版本 0.2.9 / 29；原源码和历史包未删除。
- 发布准备：MIT LICENSE 已确认；现有公开远端为 `Allenth/CodexUsageAlert`（账号显示名称 `Kingway_Meng`），默认分支 `main`。在独立发布分支保留已发布历史、重建尚未发布的合并提交以去除本机路径，不强推。基础历史 207 个唯一文件对象和最终工作树 69 个文件的常见密钥／凭据／个人路径扫描无命中，未跟踪 `archive-dist/` 或 legacy 安装包。推送结果以远端提交为准。
- 限制：任务指定的两张设计图不在工作区，按文字布局与现有深色样式实现，未做原稿像素比对；当前 macOS 通知权限为“未允许”，未验证通知横幅送达。Grok 需要外部更新或手动填写，本次不包含自动采集器。
- 分支：开发 `merge/usage-sources`；脱敏发布 `release/usage-v2`。
- 提交：pending commit。

### 2026-11-04 13:30:02 CST (UTC+08:00) — 按 A 为主合并项目并归档历史包

- 版本：`0.2.8`（Build `28`）。
- 完成内容：采用 A 的源码、菜单栏定位修复和图标资源；保留 A 全部 Git 历史及原目标仓库后续历史；保留 B 的开发日志、更新日志和独有文档。依赖 B 核心实现的沙盒、本地化与打包文件收录于 `legacy/b-only/`。历史打包目录按来源放入被忽略的 `archive-dist/`；原 A 目录和 ZIP 不变。
- 主要文件：`Sources/`、`Tests/`、`Resources/`、构建及图标脚本、`.gitignore`、`legacy/b-only/`、`docs/merge-report.md`、`docs/merge-inventory.json`、历史文档和更新日志。
- 验证：`swift build && swift test` 成功，10 项 XCTest 全部通过（菜单栏定位 4 项、核心用量 6 项）；保留 A 原有的 `UsageMonitor.swift:137` 捕获语义警告。Info.plist 校验和当前 Shell 脚本语法检查通过。逐文件 SHA-256 确认 44 个 A 文件完全一致，其余两个文件仅调整版本或忽略规则；8 个历史文件与 B 一致；3,083 个归档文件与来源一致且全部被 Git 忽略；A（含 .git）与原 ZIP 完整性检查通过。没有执行安装、签名、发布或 GUI 验证。
- 分支：`merge/usage-sources`。
- 提交：pending commit。
- 交付与冲突详情：[合并报告](docs/merge-report.md)；原目标备份保留在本机合并前备份目录。

### 2026-10-04 15:23:59 CST (UTC+08:00) — 应用更名为 CoMex

- 版本：`0.2.7`（Build `27`）。
- 完成内容：将应用的对外品牌名称统一更名为 `CoMex`；同步更新
  窗口标题、主页标题、测试通知、App Server 客户端标题、应用包、DMG
  命名、中英文使用说明与开发文档。保留原 Bundle ID、Swift 模块名和
  GitHub 仓库名，避免破坏用户设置、授权数据和工程兼容性。
- 主要文件：`Resources/Info.plist`、本地化名称、
  `Sources/CodexUsageAlert/`、`Sources/UsageCore/CodexAppServerClient.swift`、
  构建脚本、更新日志和项目文档。
- 验证：17 项 Swift 测试全部通过；沙盒 Release 构建、Info.plist 和
  代码签名验证通过；覆盖安装 V0.2.7（Build 27）后确认安装路径为
  `~/Applications/CoMex.app`，窗口、主页、macOS 菜单和运行中应用均显示
  `CoMex`；旧应用已移到废纸篓保留可恢复备份。
- 分支：`app-store/sandbox-prototype`。
- 提交：pending commit。

### 2026-09-25 00:47:54 CST (UTC+08:00) — Token 最近七日本机日期

- 版本：`0.2.6`（Build `26`）。
- 完成内容：Token 图表固定显示截至今天的最近 7 个本机自然日；服务端最新 7 条
  数据按顺序映射为连续日期，最后一列始终为今天；前六列显示星期与日期，最后一列
  标记“今天”，详情浮窗同步显示适配后的星期和日期。
- 主要文件：`Sources/UsageCore/UsageSnapshot.swift`、
  `Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、测试、更新日志和用户文档。
- 验证：17 项 Swift 测试全部通过；沙盒 Release 构建和代码签名验证通过；覆盖安装
  V0.2.6（Build 26）后确认图表连续显示周六 09/19 至今天 09/25，最后一列
  为“今天”；详情浮窗显示 `2026-09-25 · 今天`，引导线准确指向最后一柱。
- 分支：`app-store/sandbox-prototype`。
- 提交：`17606a7`。

### 2026-09-23 11:00:32 CST (UTC+08:00) — Token 柱状图悬停引导线

- 版本：`0.2.5`（Build `25`）。
- 完成内容：把 Token 柱状图悬停浮窗移到图表上方的独立空间，避免遮挡柱形；
  增加从浮窗指向当前柱形的引导线和高亮端点，并保证首尾柱形的浮窗不超出卡片。
- 主要文件：`Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、更新日志和用户文档。
- 验证：16 项 Swift 测试全部通过；沙盒 Release 构建和代码签名验证通过；覆盖安装
  V0.2.5（Build 25）后分别测试首列、中间最高柱和末列，确认浮窗不遮挡图表、
  首尾不越界，引导线与高亮端点准确指向当前柱形；点击和辅助功能标签正常。
- 分支：`app-store/sandbox-prototype`。
- 提交：`f815d68`。

### 2026-09-23 02:26:23 CST (UTC+08:00) — 分区 info 说明浮窗

- 版本：`0.2.4`（Build `24`）。
- 完成内容：为额度概览、今日预算、Token、重置时间、额度周期和预警刻度增加
  独立 info 浮窗；把计算公式、数据来源、日期适配、阈值含义和隐私说明从主页面
  移入对应浮窗；连接错误、Token 不可用和沙盒授权区域也提供说明入口。
- 主要文件：`Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、更新日志和用户文档。
- 验证：16 项 Swift 测试全部通过；沙盒 Release 构建和代码签名验证通过；覆盖安装
  V0.2.4（Build 24）后逐项点击额度概览、今日预算和 Token 浮窗，确认主页面说明
  已收纳、浮窗内容完整；临时切换英文验证长文本排版后恢复“跟随系统”。
- 分支：`app-store/sandbox-prototype`。
- 提交：`22fca84`。

### 2026-09-23 02:13:31 CST (UTC+08:00) — Token 日期强制适配本机

- 版本：`0.2.3`（Build `23`）。
- 完成内容：将服务端最新一条 Token 每日统计固定作为本机今天、上一条作为昨天；
  图表日期按相同偏移整体适配，本月累计也按适配后的本机日期统计；服务端原始
  `startDate` 继续保留在帮助信息中用于排查。
- 主要文件：`Sources/UsageCore/UsageSnapshot.swift`、
  `Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、测试、更新日志和用户文档。
- 验证：16 项 Swift 测试全部通过；沙盒 Release 构建和代码签名验证通过；覆盖安装
  V0.2.3（Build 23）后人工确认服务端原始 09/22 的 4036 万显示为今日、上一日
  1 亿显示为昨日，图表最后两列显示为本机 09/22 与 09/23。
- 分支：`app-store/sandbox-prototype`。
- 提交：`ee333f9`。

### 2026-09-23 01:58:09 CST (UTC+08:00) — Token 每日用量与自定义预警阈值

- 版本：`0.2.2`（Build `22`）。
- 完成内容：Token 卡片改为显示今日、昨日和本月累计；每日柱状图支持悬停查看
  日期与精确 Token 数；新增四档阈值独立设置，并在基础上限变化时按当前比例缩放
  前三档；将“日桶”等后端术语替换为自然中文，并明确区分服务端统计日期与
  macOS 本机系统日期。
- 主要文件：`Sources/UsageCore/UsageSnapshot.swift`、
  `Sources/CodexUsageAlert/UsageMonitor.swift`、
  `Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、测试、更新日志和用户文档。
- 验证：16 项 Swift 测试全部通过；沙盒 Release 构建和代码签名验证通过；人工验证
  Token 三项指标、缺失今日数据的“待更新”说明、柱状图悬停详情、阈值设置界面，
  以及基础上限 15% 对应 `3.8 / 7.5 / 11.3 / 15` 的比例结果。
- 分支：`app-store/sandbox-prototype`。
- 提交：`040d06a`。

### 2026-09-23 01:20:45 CST (UTC+08:00) — 后台驻留、版本管理与应用内更新记录

- 版本：`0.2.1`（Build `21`）。
- 完成内容：关闭主窗口或按 `Command + Q` 后隐藏界面与 Dock 并继续菜单栏监控；
  菜单栏电源按钮可完全退出；设置页显示当前版本并提供中英文完整更新记录；
  构建前根据提交次数自动同步版本号与 Build。
- 主要文件：`Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、
  `Resources/Info.plist`、`scripts/sync_version.sh`、构建脚本、用户及版本文档。
- 验证：14 项 Swift 测试全部通过；沙盒 Release 构建、代码签名验证通过；人工验证
  红色关闭、`Command + Q`、重新打开、电源完全退出、版本和更新记录界面均符合预期。
- 分支：`app-store/sandbox-prototype`。
- 提交：`b498ab0`。

### 2026-09-23 01:06:28 CST (UTC+08:00) — 建立开发日志制度

- 版本：`0.2.0`（Build `3`），本次仅维护项目文档，版本未变更。
- 完成内容：建立统一开发日志和面向用户的版本更新日志，并将日志更新时间、
  版本号、验证结果和提交信息设为每次开发任务的必填项。
- 主要文件：`AGENTS.md`、`DEVELOPMENT_LOG.md`、`CHANGELOG.md`。
- 验证：核对 `Resources/Info.plist`；按北京时间回溯 Git 历史；检查未将共享
  工作区中的并行未提交改动计入日志。
- 分支：`docs/development-log`。
- 提交：随本次日志制度变更一并提交，提交号以本文件 Git 历史为准。

## 历史回溯

以下内容根据既有 Git 提交整理，用于补齐建立日志制度之前的开发轨迹。

### 2026-09-23 00:24:04 CST (UTC+08:00) — 版本 0.2.0（Build 3）

- 统一额度圆环和状态的颜色语义，减少同一状态出现多种颜色的歧义。
- 完成中英文界面、本机 Codex 授权入口和隐藏目录选择引导。
- 相关提交：`79e6753`、`2425090`、`5ae2be2`。

### 2026-09-22 22:49:29 CST (UTC+08:00) — 服务端数据说明与启动引导

- 明确区分服务端额度、Token 每日统计和本机计算数据。
- 增加 Codex/ChatGPT 启动与登录状态引导。
- 相关提交：`12a8d53`。

### 2026-09-22 22:05:32–22:10:33 CST (UTC+08:00) — 图标与分发

- 更新应用图标并整理普通版、沙盒版构建说明。
- 增加签名 DMG 的分发流程。
- 相关提交：`0cd5510`、`9c43b4a`。

### 2026-09-22 20:41:30–21:35:21 CST (UTC+08:00) — 沙盒、数据与状态栏

- 修正结转预算上限、Token 日期状态和缺失昨日数据时的估算逻辑。
- 增加沙盒安全的 Codex 可执行文件与登录资料授权。
- 验证沙盒环境可读取真实额度与 Token 数据。
- 状态栏采用彩色迷你应用图标，并在基线补齐后重新计算结转预算。
- 相关提交：`7d2f4d2`、`938420c`、`4321af6`、`67980b4`、
  `3d83654`、`cad287b`。

### 2026-09-22 20:21:41–20:31:11 CST (UTC+08:00) — 每日预算结转

- 增加每日可持续预算、昨日未用预算结转和数据来源说明。
- 启动 Mac App Store 沙盒授权原型。
- 相关提交：`cd9757f`、`f4e6377`、`8afa63f`。

### 2026-09-22 19:25:16–20:04:21 CST (UTC+08:00) — App Store 规划

- 建立 App Store 开发计划、元数据及文档库。
- 记录免费分发和产品网站方向。
- 相关提交：`8aafd93`、`d2c7e31`。

### 2026-09-22 16:36:53–16:58:11 CST (UTC+08:00) — 版本 0.1.0（Build 1）

- 完成首个开源版本。
- 修复设置保存、状态栏图标和菜单栏弹窗内的设置交互。
- 统一普通窗口与菜单栏弹窗的设置界面。
- 相关提交：`f20b7ad`、`18630b5`、`72464cd`、`d18faef`。

## 新记录模板

```markdown
### YYYY-MM-DD HH:mm:ss CST (UTC+08:00) — 标题

- 版本：`x.y.z`（Build `n`）。
- 完成内容：说明用户可见结果。
- 主要文件：列出核心文件或组件。
- 验证：列出测试、构建、签名或人工检查结果。
- 分支：`branch-name`。
- 提交：`commit` 或 pending commit。
```
