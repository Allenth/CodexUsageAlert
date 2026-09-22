# Codex Usage Alert / Codex 用量预警

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Codex Usage Alert icon">
</p>

一个原生 macOS 菜单栏用量监控器。它通过本机 `codex app-server` 读取当前 ChatGPT/Codex 额度窗口与 Token 活动数据，并在用量偏高时发送系统通知。

> 本项目是独立的开源工具，不是 OpenAI 官方产品。应用不会要求或保存你的账号密码、Cookie 或 API Key。

## 功能

- 菜单栏显示当前周期已用百分比
- 菜单栏使用 16pt 专用无阴影矢量图标
- 点击应用图标打开完整仪表盘，同时保留菜单栏入口
- 自动刷新频率可设置，默认 15 分钟；也可选择固定时间刷新
- 显示已用额度、剩余额度、额度周期和重置时间
- 按本地自然日记录基线，估算当天增加的额度百分点
- 按额度窗口计算可持续日均预算；若昨日低于日均，未用部分会加到今天的 20% 基础上限
- 仪表盘保留 5、10、15、20 规则刻度，并展示周日均、昨日已用、昨日余量和今日上限及其来源
- 当日增量达到 5、10、15、20 个百分点时发送分级通知
- 同一阈值当天只通知一次，避免重复打扰
- 显示 Token 日汇总的实际截止日期、本月累计、单日峰值、历史累计、连续使用天数和最近 7 个活跃日趋势
- Token 数量单位可切换中文（万、亿）或英文（K、M、B）
- 内置通知测试、通知设置入口和登录时自动启动
- 附带 `codex-usage` JSON 命令行读取器

## 系统要求

- macOS 13 或更高版本
- Swift 6 工具链
- 本机已安装 Codex CLI 或 ChatGPT/Codex macOS 应用
- 已使用支持 Codex 服务的 ChatGPT 身份登录

## 数据来源

应用启动本机 `codex app-server`，使用官方 JSON-RPC 方法：

- `account/rateLimits/read`：额度窗口、已用百分比和重置时间
- `account/usage/read`：Token 活动摘要和每日数据

可持续日均按 `100 ÷ 额度窗口天数` 在本机计算。昨日已用优先来自应用保存的本机额度快照，公式为 `今日上限 = 20% + max(0, 可持续日均 - 昨日已用)`（最高 100%）。例如七日窗口的日均约为 14.3%，昨日用了 7%，则昨日余量为 7.3%，今日上限为 27.3%。若当前额度窗口恰好从昨日开始但缺少完整昨日记录，应用可用今天首次周累计基线作带 `≈` 标记的估算，并注明它可能包含首次快照前的今日用量；其他缺失情形不按零用量结转。

Token 每日数据以 `account/usage/read` 返回的 `dailyUsageBuckets` 为准。官方文档没有说明 `startDate` 的时区，因此界面同时显示“服务端日桶日期”和本地北京时间，不擅自换算，也不会补一个 0 值作为本地今天用量。

Token 活动接口不可用时，额度监控仍会继续工作。`20%` 是应用默认的个人每日预算，不是 OpenAI 官方硬限制。

参考：[Codex App Server 文档](https://learn.chatgpt.com/docs/app-server)

## 构建与运行

日常开发和调试使用 App 沙盒开发版：

```bash
swift test
./scripts/build_sandbox_app.sh
open "dist-sandbox/Codex Usage Alert.app"
```

GitHub 开源发布使用正常安装版：

```bash
swift test
./scripts/build_app.sh
open "dist/Codex Usage Alert.app"
```

两版来自同一套源码并共用 `Resources/AppIcon.icns`，但使用不同的 Bundle ID、权限和输出目录。开发时只运行沙盒版；正常安装版仅在发布验证时启动。首次启动时，请在 macOS 权限提示中允许系统通知。详细规则见[双版本构建与代码管理](docs/build-variants.md)。

命令行读取器：

```bash
swift run codex-usage --pretty
```

## 项目结构

```text
Sources/UsageCore/          数据模型、规则与 App Server 客户端
Sources/CodexUsageAlert/    SwiftUI 应用、监控和系统通知
Sources/CodexUsageCLI/      JSON 命令行读取器
Tests/UsageCoreTests/       核心逻辑测试
Resources/                  Info.plist 与应用图标
scripts/build_app.sh        .app 构建及临时/Developer ID 签名脚本
scripts/build_sandbox_app.sh App 沙盒开发版构建脚本
scripts/build_dmg.sh        Developer ID 签名、DMG 打包与可选公证脚本
docs/                       开发计划、提示词和项目文档
```

## 项目文档

项目文档统一保存在 [`docs`](docs/README.md) 目录，包括：

- [Mac App Store 开发计划](docs/app-store-development-plan.md)
- [Mac App Store 上架资料](docs/app-store-metadata.md)
- [双版本构建与代码管理](docs/build-variants.md)
- [从零生成 Codex 用量预警的完整开发提示词](docs/development-prompt.md)

## 分发说明

日常 `.app` 构建默认使用临时签名。`scripts/build_dmg.sh` 会自动查找 Developer ID Application 证书，为正常安装版和 DMG 正式签名，并在设置 `NOTARY_PROFILE` 时提交 Apple 公证。Mac App Store 版本仍需要完成正式 Xcode 分发工程改造，详见[开发计划](docs/app-store-development-plan.md)。

## 隐私

- 用量数据仅在本机展示和保存必要的每日基线。
- 不收集账号邮箱、凭据或完整 App Server 日志。
- 不包含遥测或第三方分析 SDK。

## License

[MIT](LICENSE)
