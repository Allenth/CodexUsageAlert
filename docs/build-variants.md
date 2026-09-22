# 双版本构建与代码管理

项目采用“单一源码、双构建版本”的管理方式。功能代码、测试和图标只维护一份，避免沙盒开发版与正常安装版长期分叉。

## 版本职责

| 项目 | App 沙盒开发版 | 正常安装版 |
| --- | --- | --- |
| 用途 | 日常开发、调试和权限验证 | GitHub 开源构建与发布验证 |
| 构建脚本 | `scripts/build_sandbox_app.sh` | `scripts/build_app.sh` |
| 输出目录 | `dist-sandbox/` | `dist/` |
| Bundle ID | `com.huijing.codex-usage-alert.sandbox-prototype` | `com.huijing.codex-usage-alert` |
| App Sandbox | 启用 | 当前未启用 |
| 日常是否运行 | 是 | 否，仅发布验证时运行 |

## 共享资源

- 两版共用 `Sources/`、`Tests/`、`Package.swift` 和功能配置。
- 应用图标的主文件是 `Resources/AppIcon.png`，高分辨率母版是 `Resources/AppIcon-master.png`。
- `Resources/AppIcon.iconset/` 和 `Resources/AppIcon.icns` 由同一主图标生成，两种构建均复制同一个 `AppIcon.icns`。
- 变更功能时先在沙盒开发版验证；测试通过后，正常安装版自动获得相同源码变更。

## 日常开发流程

```bash
swift test
./scripts/build_sandbox_app.sh
open "dist-sandbox/Codex Usage Alert.app"
```

日常只运行沙盒开发版，避免两个菜单栏进程同时读取数据、发送通知或造成界面差异判断错误。

## 开源发布流程

```bash
swift test
./scripts/build_app.sh
```

正常安装版构建完成后默认保持关闭。只有在准备 GitHub Release 时才启动做一次发布验收，并继续执行正式签名、公证和压缩包校验。

## 提交规则

1. 功能、测试和文档在同一分支中同步提交，不复制另一套源码目录。
2. `dist/`、`dist-sandbox/` 和本机构建产物不提交到 Git。
3. 图标变更时同时更新 `AppIcon.png`、`AppIcon-master.png`、完整 `AppIcon.iconset/` 和 `AppIcon.icns`。
4. 发布前确认正常安装版未混入沙盒原型专用的 Bundle ID 或显示名称。
