# Codex 用量预警：开发复盘与可复用提示词

这份文档用于从零生成一个可安装、可运行、可分发的原生 macOS Codex 用量监控应用。

## 一、我们实际完成了什么

项目最终形态是一个 SwiftUI 原生 macOS 应用，包含完整仪表盘、菜单栏入口和一个附带的命令行读取器。

核心能力：

- 通过本机 `codex app-server` 读取当前登录账号的数据，不索取或保存用户凭据。
- 使用 `account/rateLimits/read` 读取真实额度窗口：已用百分比、剩余百分比、窗口长度和重置时间。
- 使用 `account/usage/read` 读取 Token 活动：累计 Token、单日峰值、连续使用天数、最长连续天数和每日 Token 桶。
- 按本地自然日保存当天基线，用“当前周期已用百分比 - 今日基线”估算当天增加的额度百分点。
- 在当天增加达到 5、10、15、20 个百分点时发送分级 macOS 系统通知；同一阈值当天只提醒一次。
- 每 5 分钟后台刷新，也支持立即刷新和测试通知。
- 支持登录时自动启动。
- 同时提供普通应用窗口和菜单栏入口；点击 Dock 图标会重新显示窗口。
- 提供暗色科技风界面、额度圆环、每日预算进度、Token 趋势图、重置时间和通知状态。
- 提供多尺寸应用图标、Swift 单元测试、构建脚本、临时签名和 ZIP 分发包。

## 二、开发过程总结

1. 先验证数据来源：确认 Codex CLI 的 App Server 能返回真实额度，而不是根据订阅价格猜测。
2. 先做最小命令行读取器：启动 `codex app-server`、完成 JSON-RPC 初始化、读取 `account/rateLimits/read`。
3. 抽离 `UsageCore`：统一数据模型、百分比计算、错误处理和 App Server 客户端。
4. 实现监控状态机：保存自然日基线、识别额度重置、判断阈值并避免重复通知。
5. 制作 macOS 原生界面：先做菜单栏工具，再补标准窗口，解决“点击图标没有反应”的问题。
6. 制作图标和视觉系统：统一青蓝色发光风格，并增大菜单栏图标的可识别度。
7. 修复主题兼容问题：强制仪表盘使用暗色配色，并显式设置主要文字颜色，避免浅色系统下出现黑字看不清。
8. 增加 Token 数据：在同一次 App Server 会话中顺序请求额度和 Token；Token 读取失败时仍保留额度功能。
9. 完成测试、安装和分发：运行单元测试、构建 `.app`、临时签名、安装到用户应用目录并生成 ZIP。

## 三、可直接使用的一次性总提示词

复制下面整段到一个新的 Codex 编程任务中即可。最好在一个空目录中执行。

```text
请在当前目录从零开发并交付一个名为“Codex 用量预警”的原生 macOS 应用。不要只给方案或代码片段，要持续执行直到应用完成构建、通过测试、安装并实际打开验证。

一、产品目标

开发一个 SwiftUI 菜单栏用量监控器，同时提供普通应用窗口。它从本机已经登录的 Codex CLI 读取 ChatGPT/Codex 额度和 Token 活动数据，定时刷新，并通过 macOS 系统通知提醒用户当天的额度增量偏高。

默认配置：
- 产品名：Codex 用量预警
- 英文名：Codex Usage Alert
- Bundle ID：com.huijing.codex-usage-alert
- 最低系统：macOS 13
- 安装位置：~/Applications/Codex Usage Alert.app
- 自动刷新：300 秒，把该值定义成易修改的常量
- 当日个人预算上限：20 个额度百分点
- 预警阈值：5、10、15、20 个百分点
- 界面语言：简体中文

二、数据来源与安全边界

1. 必须使用本机 `codex app-server` 的 JSON-RPC 接口，不要直接请求 chatgpt.com 的内部 backend-api，不要抓网页，不要要求用户提供 Cookie、Access Token 或 OpenAI API Key。
2. 启动 App Server 后依次发送：
   - `initialize`，包含 clientInfo；等待对应响应。
   - `initialized` 通知。
   - `account/rateLimits/read`，读取额度窗口。
   - `account/usage/read`，读取 Token 活动。
3. 按 JSON-RPC `id` 匹配响应，忽略不相关通知；逐行解析 stdout JSON；设置约 15 秒超时，并确保进程、管道和文件句柄可靠关闭。
4. Codex 可执行文件按以下顺序查找：
   - /Applications/ChatGPT.app/Contents/Resources/codex
   - /Applications/Codex.app/Contents/Resources/codex
   - /opt/homebrew/bin/codex
   - /usr/local/bin/codex
   - PATH 中的 codex
5. 额度解析优先使用 `result.rateLimitsByLimitId.codex`，不存在时回退到 `result.rateLimits`。从 primary 中读取：
   - usedPercent
   - windowDurationMins
   - resetsAt
   - 可选 planType
6. `usedPercent` 表示“已消耗”，`remainingPercent = 100 - usedPercent`，两者都限制在 0...100。不得把已用误写成剩余。
7. Token 接口读取：
   - summary.lifetimeTokens
   - summary.peakDailyTokens
   - summary.longestRunningTurnSec
   - summary.currentStreakDays
   - summary.longestStreakDays
   - dailyUsageBuckets[].startDate
   - dailyUsageBuckets[].tokens
8. Token summary 字段和 dailyUsageBuckets 都可能为 null，必须安全处理。Token 请求失败时不要让额度读取和预警功能一起失败；界面显示“Token 数据暂不可用”，保留上一次成功数据。
9. 所有数据仅在本机处理，不记录账号标识、邮箱、凭据或完整 App Server 日志。

三、工程结构

使用 Swift Package Manager，建立以下结构：

- Package.swift
- Sources/UsageCore/UsageSnapshot.swift
- Sources/UsageCore/CodexAppServerClient.swift
- Sources/CodexUsageAlert/UsageMonitor.swift
- Sources/CodexUsageAlert/CodexUsageAlertApp.swift
- Sources/CodexUsageCLI/main.swift
- Tests/UsageCoreTests/UsageCoreTests.swift
- Resources/Info.plist
- Resources/AppIcon.icns
- scripts/build_app.sh
- README.md

Package 至少包含：
- `UsageCore` library
- `CodexUsageAlert` executable
- `codex-usage` executable
- `UsageCoreTests`

四、监控和通知规则

1. 使用 UserDefaults 保存：
   - baselineDay
   - baselineUsedPercent
   - notifiedThresholds
2. 用用户当前时区的自然日作为基线日期。
3. 当天增加量 = 当前 usedPercent - 当天首次有效快照的 usedPercent。
4. 只有存在同一天的较早基线时才能声称“今日增加”。如果当前 usedPercent 小于基线，视为额度窗口重置，重新建立基线，今日增加归零。
5. 当今日增加首次达到 5、10、15、20 时，通过 UserNotifications 发送通知。同一天同一阈值只发一次；一次刷新跨过多个阈值时记录所有已跨阈值，只发送最高级别通知。
6. 分级文字：正常、用量提醒、用量偏高、接近每日上限、达到每日上限。
7. 通知正文必须同时说明“今天增加了多少额度百分点”和“当前周期累计使用百分比”。20% 是用户个人预算，不要称为 OpenAI 官方硬上限。
8. 首次启动申请通知权限；提供“测试通知”按钮和打开系统通知设置的按钮。
9. 使用 `SMAppService.mainApp` 提供“登录时自动启动”开关。
10. 自动刷新默认每 300 秒一次，并提供“立即刷新”。定时刷新不会生成模型回答，也不要把它描述成消耗模型 Token。

五、界面要求

同时使用：
- `WindowGroup`：点击应用或 Dock 图标可打开完整仪表盘。
- `MenuBarExtra`：菜单栏持续显示 18×18 应用图标和当前周期已用百分比。

窗口建议宽度 380，高度约 750，内容宽度约 344。界面为深蓝黑渐变背景、青蓝色高亮、圆角卡片、轻微发光效果。必须在浅色和深色 macOS 系统主题下都保持清晰：对主要文字显式使用白色或白色透明度，并为该面板设置 dark color scheme。

完整仪表盘包含：

1. 顶部：42×42 应用图标、标题、最后更新时间、当前状态胶囊。
2. 大圆环：显示本周期已用百分比。
3. 三个指标：今日增加、周期剩余、通知状态。
4. 今日额度预算卡：
   - 显示“今日增加 / 20%”
   - 进度条
   - 5、10、15、20 四个刻度
5. Token 使用量卡：
   - 累计 Token
   - 单日峰值
   - 当前连续使用天数与最长连续天数
   - 最近 7 个活跃日柱状趋势
   - Token 数字使用 K、M、B 紧凑格式，鼠标提示可显示精确值
6. 三个信息卡：下次重置、额度周期、预警刻度。
7. 错误提示条：错误信息可换行，不允许黑字压在深色背景上。
8. 操作区：立即刷新、测试通知、登录时自动启动、通知设置、退出应用。
9. 底部说明：“数据仅从本机 Codex CLI 读取”和刷新周期。

窗口重新打开规则：
- `applicationDidFinishLaunching` 后显示仪表盘。
- 应用已经运行时再次点击 Dock 图标，窗口必须重新出现。
- 不要把程序做成只有菜单栏、点击应用图标无反应的 LSUIElement-only 应用。

六、应用图标

创建一个原创的 1024×1024 macOS 应用图标：深蓝圆角方形底座，中间是青蓝渐变的字母 C / 环形仪表，右上角有一个小型金色预警光点；质感简洁、现代、轻微玻璃和发光效果，不使用 OpenAI 官方商标。

生成 16、32、128、256、512、1024 对应的 @1x/@2x iconset，并转换为 AppIcon.icns。菜单栏内使用同一图标，尺寸 18×18，确保肉眼可见。

如果当前环境没有图像生成工具，就使用 Core Graphics、SVG 或可复现的矢量绘制脚本生成原创图标，不要省略图标资源。

七、CLI、Info.plist 和 URL Scheme

1. `codex-usage` 默认输出归一化额度快照 JSON，支持 `--pretty`。
2. Info.plist 至少包含显示名、可执行文件、Bundle ID、版本、最低系统版本、AppIcon 和 URL Scheme `codexusagealert`。
3. 支持 URL 动作：
   - codexusagealert://show
   - codexusagealert://refresh
   - codexusagealert://test-notification
   - codexusagealert://launch-at-login?enabled=1

八、构建、测试与分发

1. 为以下逻辑编写单元测试：
   - 百分比限制和 remainingPercent
   - 额度窗口天数
   - 5/10/15/20 阈值分级
   - 重置后不产生负的今日增加
   - Token K/M/B 格式
   - Token 响应包含 null 时仍能解析
2. 运行 `swift test`，修复全部失败。
3. `scripts/build_app.sh` 必须：
   - 执行 release 构建
   - 创建标准 `.app/Contents/{MacOS,Helpers,Resources}` 结构
   - 复制主程序、codex-usage helper、Info.plist 和 AppIcon.icns
   - 使用临时签名 `codesign --force --deep --sign -`
4. 构建完成后安装到 `~/Applications/Codex Usage Alert.app`。替换旧版本前先结束旧进程并把旧应用移到废纸篓备份，不要不可恢复地删除用户文件。
5. 注册并打开应用，确认进程存活、签名验证通过、窗口实际出现。
6. 做一次真实界面检查：确保所有文字可读、窗口不裁切、Token 图表出现、菜单栏图标足够大、按钮可用。
7. 生成：
   - `dist/CodexUsageAlert-0.1.0-macOS.zip`
   - 可选的完整 release ZIP
8. 用 `unzip -t` 验证压缩包。
9. README 说明依赖、功能、构建、安装和分发限制。明确当前临时签名适合本机或测试分发；正式公开分发仍需要 Developer ID 签名和 Apple 公证。

九、执行方式

- 先检查当前目录和已有文件，保护用户已有改动。
- 需要查 Codex 接口时，只依据当前官方 OpenAI 文档，不要凭记忆臆造字段。
- 直接创建文件、实现、测试、构建、安装和验证；不要停留在计划阶段。
- 每完成一个关键阶段给我一句简短进度说明。
- 遇到可以自行修复的编译、权限或布局问题要继续迭代，不要把未验证的半成品交付给我。
- 最终回复只需说明：完成了什么、测试结果、应用安装位置、分发包位置、已知限制。
```

## 四、分阶段提示词

如果一次性生成遇到问题，可以按顺序发送下面的提示词。每一条都默认在同一个项目目录中继续工作。

### 阶段 1：项目骨架和数据读取

```text
创建一个 macOS 13+ Swift Package，包含 UsageCore、SwiftUI 主应用、codex-usage CLI 和测试 Target。实现 CodexAppServerClient：可靠启动本机 codex app-server、完成 initialize/initialized、按 JSON-RPC id 读取 account/rateLimits/read。优先解析 rateLimitsByLimitId.codex，回退到 rateLimits。输出已用、剩余、窗口分钟数、重置时间和 planType。设置 15 秒超时、明确中文错误、可靠清理子进程和管道。完成后运行测试和 CLI 实测。
```

### 阶段 2：每日基线和通知

```text
在现有工程中实现 UsageMonitor。每 5 分钟自动刷新，支持立即刷新。用 UserDefaults 保存本地自然日的 baselineDay、baselineUsedPercent、notifiedThresholds。计算同日额度增量；发现百分比回落时视为额度重置并重建基线。在 5、10、15、20 个百分点发送分级 macOS 通知，同一阈值同一天只提醒一次。加入通知授权、测试通知、通知设置入口和 SMAppService 登录启动开关。补齐单元测试。
```

### 阶段 3：原生界面

```text
为现有监控器实现完整 SwiftUI 界面：同时提供 WindowGroup 和 MenuBarExtra。窗口宽 380 左右，深蓝黑渐变、青蓝高亮、白色文字；包含标题、状态、额度圆环、今日增加、剩余额度、通知状态、20% 每日预算进度、重置时间、额度周期、预警刻度、错误提示、刷新/测试通知按钮、登录启动和退出。强制暗色配色并显式设置文字颜色，确保 macOS 浅色模式下也不出现黑字看不清。点击应用图标或 Dock 图标必须重新显示窗口。
```

### 阶段 4：Token 数据和图表

```text
在同一次 codex app-server 会话中，在额度读取成功后调用 account/usage/read。建立可选字段模型，解析 lifetimeTokens、peakDailyTokens、longestRunningTurnSec、currentStreakDays、longestStreakDays 和 dailyUsageBuckets。Token 请求失败不能拖垮额度功能。界面加入 Token 卡片：累计、单日峰值、当前/最长连续天数和最近 7 个活跃日柱状图；用 K/M/B 格式并提供精确数值提示。为 null 字段和格式化补测试。
```

### 阶段 5：图标和视觉打磨

```text
为应用创建原创 1024×1024 图标：深蓝圆角方形、青蓝渐变 C 形仪表环、右上角金色预警光点、轻微玻璃和发光质感。生成完整 macOS iconset 和 AppIcon.icns。主界面图标 42×42，菜单栏图标 18×18。然后实际打开应用进行视觉检查，修复裁切、间距、对比度、按钮颜色和浅色系统主题问题。
```

### 阶段 6：打包和安装

```text
补齐 Info.plist、URL Scheme、README 和 scripts/build_app.sh。release 构建后组装标准 .app，内含主程序、codex-usage helper、Info.plist 和 AppIcon.icns，使用临时签名。运行全部测试，将应用安装到 ~/Applications，注册并打开，验证签名和进程。生成 dist/CodexUsageAlert-0.1.0-macOS.zip，并用 unzip -t 检验。替换旧版本时先移到废纸篓备份。
```

### 阶段 7：最终验收

```text
对整个 Codex Usage Alert 做最终验收，不要新增无关功能。检查：额度方向是否正确；重置时间和周期是否正确；Token 数据是否显示；Token 请求失败是否降级；今日基线与跨日/重置逻辑；重复通知抑制；测试通知；登录启动；窗口重新打开；菜单栏图标尺寸；浅色/深色主题文字；应用签名；测试；ZIP 完整性。发现问题直接修复并重新构建、安装、打开验证，最后给出结果和文件路径。
```

## 五、常用后续修改提示词

### 改成自适应刷新

```text
把固定 5 分钟刷新改为自适应：正常状态每 15 分钟；当今日增量距离下一个阈值小于 2 个百分点，或周期总用量达到 85% 时，每 5 分钟；连续失败后退避到 30 分钟；手动刷新始终可用。界面显示当前刷新策略，并补测试。不要改变预警阈值。
```

### 增加设置页

```text
为应用增加原生设置页，让用户配置刷新间隔、每日预算上限和四级阈值。提供合理校验，保持阈值递增，保存到 UserDefaults，修改后立即应用。默认值仍为 5、10、15、20 和 20% 上限。保持主界面简洁。
```

### 做正式可分发版本

```text
把现有测试分发流程升级为正式 macOS 发布流程：保持 Bundle ID 和版本规范，提供 Developer ID Application 签名、Hardened Runtime、必要 entitlements、公证和 staple 的脚本模板。不要伪造证书；如果本机缺少签名身份，只完成可验证的脚本和文档，并明确需要用户提供的 Apple Developer 前提。
```

## 六、验收标准速查

- `swift test` 全部通过。
- 应用无需 API Key，读取的是当前本机 Codex 登录状态。
- 已用与剩余方向明确且相加为 100%。
- 当天增量没有同日基线时不伪造。
- 额度重置后不会出现负增量。
- Token 字段为 null 或接口失败时应用不崩溃。
- 通知不会每 5 分钟重复轰炸。
- Dock 图标、窗口和菜单栏入口都可用。
- 浅色系统主题下文字仍清晰。
- 图标在 Dock 和菜单栏中都足够明显。
- `.app` 可启动、签名可验证、ZIP 可解压。

## 七、官方接口依据

实现前应再次核对当前官方 OpenAI 文档：

- Codex App Server：<https://learn.chatgpt.com/docs/app-server>

其中 `account/rateLimits/read` 返回额度窗口；`account/usage/read` 返回 Token 活动摘要和可选每日桶。官方文档说明 Token 摘要值和每日桶可能为 null，并且该接口需要 Codex 服务支持的身份验证。
