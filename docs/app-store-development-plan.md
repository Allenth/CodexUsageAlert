# Codex Usage Alert：Mac App Store 开发计划

## 1. 目标

把当前可本机安装的 SwiftUI 菜单栏应用升级为可通过 Mac App Store 提交、审核、安装和更新的正式产品，同时保持以下核心能力：

- 展示 Codex 当前额度、剩余额度、重置时间和 Token 活动。
- 按用户配置自动刷新，并在用量达到阈值时发送系统通知。
- 提供菜单栏入口、完整仪表盘、登录时启动和本地隐私保护。
- 不收集用户的账号密码、Cookie、API Key 或完整运行日志。

## 2. 当前基线

当前版本已经具备：

- SwiftUI 原生应用、`WindowGroup` 和 `MenuBarExtra`。
- `codex app-server` JSON-RPC 数据读取。
- 额度和 Token 数据展示、分级通知、自动刷新和登录时启动。
- Swift Package、单元测试、构建脚本和临时签名。
- 有效的 Developer ID Application 证书，可用于商店外签名和公证。

当前尚不满足 Mac App Store 提交要求：

- 工程没有启用 App Sandbox。
- 数据层会从 `/Applications`、Homebrew 或 `PATH` 启动外部 `codex` 可执行文件。
- 当前构建脚本使用临时签名，不是 Mac App Store 分发签名。
- 还没有正式 Xcode App 工程、App Store Connect 记录、商店素材和审核说明。
- 尚未在沙盒环境验证 Codex 登录状态、网络访问和子进程行为。

## 3. 核心技术风险

### R1：沙盒无法启动或使用外部 Codex CLI

Mac App Store 应用必须启用 App Sandbox。当前应用直接执行另一个应用或 Homebrew 目录中的 `codex`，这是整个上架计划的首要风险。

验证方向：

1. 通过 `NSOpenPanel` 让用户明确选择 `Codex.app`、`ChatGPT.app` 或 `codex` 可执行文件。
2. 保存 security-scoped bookmark，并在下次启动时恢复授权。
3. 在启用沙盒后测试是否能启动进程、访问其所需登录数据并完成 JSON-RPC 请求。
4. 测试子进程是否继承沙盒限制，以及网络和凭据访问是否正常。
5. 如果该方式不可靠，评估受支持的 API、内嵌已获授权的 Helper，或改走商店外 Developer ID 分发。

验收门槛：沙盒 Release 构建连续完成 20 次真实额度读取，并在重启应用和重启系统后仍能恢复授权。

### R2：第三方品牌和产品依赖

- 应用名称、图标和商店描述必须明确说明它是独立第三方工具。
- 不使用 OpenAI 官方商标或容易造成官方产品误解的视觉元素。
- 审核备注需说明 Codex 是功能依赖，并提供审核人员可复现的测试步骤。

### R3：审核环境无法复现数据

审核人员可能没有安装或登录 Codex。应用需要提供清晰的首次使用说明，并评估加入不伪造真实数据的只读演示模式，让审核人员可以检查界面和设置，同时明确标注“演示数据”。

## 4. 分阶段计划

### 阶段 0：建立发布基线

预计：0.5 天

- [ ] 为当前可用版本创建 Git 标签和基线 Release。
- [ ] 记录 Bundle ID、版本号规则、最低系统版本和隐私边界。
- [ ] 确认 Apple Developer 账号、Team ID 和 App Store Connect 权限。
- [ ] 在 App Store Connect 预留应用名称和 Bundle ID。

交付物：可回退的基线版本、发布参数清单。

### 阶段 1：App Sandbox 可行性原型

预计：1～2 天

- [ ] 创建最小 Xcode 沙盒原型，不先迁移完整界面。
- [ ] 启用 `com.apple.security.app-sandbox` 和必要的网络客户端权限。
- [ ] 实现用户选择 Codex 程序与 security-scoped bookmark。
- [ ] 在沙盒中启动 `codex app-server` 并读取额度与 Token 数据。
- [ ] 验证应用重启、系统重启、Codex 更新后的授权恢复。
- [ ] 记录失败原因、系统日志和可接受的解决方案。

决策点：

- 通过：继续 Mac App Store 路线。
- 部分通过：先修正数据读取架构，再进入阶段 2。
- 不通过：停止商店改造，改为 Developer ID 签名、公证和独立更新渠道。

交付物：沙盒可行性报告和可运行原型。

### 阶段 2：迁移为正式 Xcode 工程

预计：1～2 天

- [ ] 创建 macOS App Xcode 工程和正式 App Target。
- [ ] 保留 `UsageCore` 和测试模块，接入现有 Swift 源码与资源。
- [ ] 配置 App Sandbox、Hardened Runtime、签名和版本号。
- [ ] 将命令行 Helper 作为嵌入式签名组件管理，或在验证后移除不必要的 Helper。
- [ ] 配置 Debug、Release、App Store 三套构建环境。
- [ ] 保证 `swift test` 与 Xcode Test 均可运行。

验收标准：Xcode Archive 成功；主程序和嵌套代码签名完整；现有功能无明显回归。

### 阶段 3：实现沙盒兼容的数据层

预计：2～4 天

- [ ] 把 Codex 路径解析改为用户授权驱动，不再扫描并直接执行任意系统路径。
- [ ] 实现书签失效、程序移动、Codex 未安装和未登录时的恢复流程。
- [ ] 将数据读取错误划分为安装、权限、登录、网络、接口和超时错误。
- [ ] 保持 Token 接口失败时额度功能可继续工作的降级策略。
- [ ] 验证沙盒容器中的 UserDefaults、通知状态和每日基线迁移。
- [ ] 为路径授权、书签恢复和错误映射增加测试。

验收标准：全新安装流程无需终端操作；用户可以在界面中完成授权并读取真实数据。

### 阶段 4：产品与审核准备

预计：1～2 天

- [ ] 完善首次启动引导、权限说明和 Codex 选择流程。
- [ ] 增加隐私政策、支持页面和应用内“关于”。
- [ ] 检查应用名称、图标、免责声明和商标风险。
- [ ] 确认登录时启动只在用户主动开启后注册。
- [ ] 移除独立更新机制；商店版本只通过 Mac App Store 更新。
- [ ] 加入审核可用的演示说明或明确的测试账号/环境步骤。
- [ ] 完成简体中文和英文的关键界面及错误提示。

验收标准：首次使用者不看终端也能完成设置；隐私说明与实际行为一致。

### 阶段 5：质量验证

预计：1～2 天

- [ ] 单元测试覆盖额度解析、Token 解析、阈值、重置和设置持久化。
- [ ] 测试 macOS 13 至当前系统版本。
- [ ] 测试浅色/深色、高对比度、不同显示缩放和菜单栏空间不足。
- [ ] 测试通知拒绝、Codex 未安装、未登录、离线和接口变化。
- [ ] 使用沙盒 Release 构建做至少 24 小时后台运行测试。
- [ ] 使用 `codesign`、`spctl` 和 Xcode Organizer 检查签名与归档。

验收标准：没有阻断级缺陷；崩溃、数据方向错误和重复通知问题为零。

### 阶段 6：App Store Connect 与 TestFlight

预计：1～2 天，测试和审核等待时间不计入

- [ ] 创建 App Store Connect 应用记录、SKU、分类和年龄分级。
- [ ] 准备应用名称、副标题、描述、关键词和更新说明。
- [ ] 制作所需尺寸的截图和可选预览视频。
- [ ] 填写隐私问卷、加密出口合规和内容版权信息。
- [ ] 通过 Xcode Organizer 上传构建。
- [ ] 先进行内部 TestFlight，再邀请少量外部测试者。
- [ ] 修复 TestFlight 反馈后冻结候选版本。

交付物：可供 TestFlight 安装的候选版本和完整商店页面。

### 阶段 7：提交审核与发布

预计：0.5 天提交，审核时间由 Apple 决定

- [ ] 编写审核备注，说明 Codex 依赖、数据来源、授权步骤和演示方式。
- [ ] 提交审核并跟踪 App Store Connect 状态。
- [ ] 对审核问题建立逐条记录，优先提供可复现证据。
- [ ] 审核通过后选择手动发布，先小范围验证下载和首次启动。
- [ ] 创建 GitHub Release、版本标签和对应发布说明。

验收标准：用户可以从 Mac App Store 安装、启动、授权、读取数据并收到通知。

## 5. 时间与里程碑

在沙盒原型成功的前提下：

| 里程碑 | 预计累计时间 | 结果 |
| --- | ---: | --- |
| M1 沙盒可行性确认 | 1～2 天 | 确定是否继续商店路线 |
| M2 Xcode 工程和数据层完成 | 4～8 天 | 可用的沙盒 Release 构建 |
| M3 商店候选版本 | 7～12 天 | 可上传 TestFlight |
| M4 正式发布 | 取决于审核 | Mac App Store 可下载 |

以上为开发工作日估算，不包含 Apple 审核等待时间。若阶段 1 失败，应立即切换到商店外公证方案，避免继续投入无效的商店适配工作。

## 6. 发布所需账号和材料

- Apple Developer Program 有效会员资格。
- App Store Connect 的 Account Holder、Admin 或 App Manager 权限。
- 注册完成的 Bundle ID 和 Mac App Distribution 签名能力。
- 中英文应用名称、描述、关键词、支持网址和隐私政策网址。
- 商店截图、应用图标、版权信息和审核说明。
- 可供审核人员复现功能的 Codex 环境说明。

不得把 Apple ID 密码、App Store Connect API 私钥、签名证书私钥或 Codex 登录凭据提交到 Git 仓库。

## 7. 完成定义

只有同时满足以下条件，才视为 App Store 项目完成：

- App Sandbox 环境能够稳定读取真实数据。
- Xcode Archive、签名和 App Store Connect 上传全部成功。
- 全新安装无需命令行即可完成首次设置。
- 所有自动化测试通过，关键异常场景已验证。
- 隐私政策、商店描述和应用实际行为一致。
- TestFlight 验证通过并处理阻断反馈。
- Apple 审核通过，正式版本可在 Mac App Store 下载。

## 8. 官方参考

- [配置 macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [准备应用用于分发](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [创建 macOS 分发签名代码](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
