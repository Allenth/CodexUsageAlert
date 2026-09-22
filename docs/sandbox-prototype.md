# App Sandbox 可行性原型

## 目标

验证 Mac App Store 强制沙盒环境下，用户能否主动授权 `Codex.app`、`ChatGPT.app` 或 `codex` 可执行文件，以及本机 `.codex` 登录资料文件夹，并继续通过 `codex app-server` 读取额度与 Token 数据。

## 实现范围

- 增加用户选择 Codex 程序与登录资料文件夹的两步原生授权。
- 使用 security-scoped bookmark 保存授权，并在应用重启后恢复。
- 数据客户端在启动 `codex app-server` 前激活两个安全作用域，通过 `CODEX_HOME` 指向用户授权的 `.codex` 文件夹，结束后及时释放。
- 非沙盒版本继续自动查找本机 Codex，不破坏现有使用方式。
- 沙盒中找不到 Codex 时，主界面直接显示授权入口。
- 设置面板显示当前数据来源，并支持恢复自动查找。
- 增加 App Sandbox、用户选择文件读写和网络客户端权限。Codex 启动时会在 `.codex` 中维护运行状态，因此仅只读授权不足以运行；应用自身不解析或展示 `auth.json` 内容。
- 提供独立的沙盒原型构建脚本，不覆盖当前正式安装包。

## 构建

```bash
./scripts/build_sandbox_app.sh
open "dist-sandbox/Codex Usage Alert.app"
```

原型使用临时签名，仅用于验证沙盒行为。正式 Mac App Store 构建仍需要 Xcode 工程、分发证书和 provisioning profile。

## 验证清单

- [x] 沙盒应用首次启动时显示 Codex 授权入口。
- [x] 选择 `/Applications/ChatGPT.app` 与 `~/.codex` 后可以读取真实额度。
- [x] Token 数据可以读取，失败时额度功能仍然可用。
- [x] 退出并重新打开应用后，安全作用域授权可以恢复。
- [ ] 重启 macOS 后授权仍然有效。
- [ ] 连续完成 20 次刷新，无进程残留或权限丢失。
- [ ] Codex 应用升级后，失效授权能通过界面重新选择。

## 2026-09-22 实机结论

- 临时签名的 Release 沙盒构建成功启动 `ChatGPT.app` 内置的 `codex app-server`。
- 仅授权 Codex 程序时会正确提示缺少账户认证；再由用户授权 `~/.codex` 后，真实额度和 Token 汇总均读取成功。
- 关闭并重新打开应用后，两个 security-scoped bookmark 均可恢复，数据无需再次选择即可刷新。
- 原型不读取、输出或提交 `auth.json` 内容；该文件只由获授权的本机 Codex 子进程使用。
- 结论：Mac App Store 沙盒路线具备可行性，可以进入正式 Xcode 工程迁移；系统重启、20 次连续刷新和 Codex 升级场景仍需继续验证。

## 决策标准

只有真实额度和 Token 读取在沙盒 Release 构建中稳定通过，才继续完整 Mac App Store 工程迁移。若外部 `codex` 子进程无法在沙盒中访问其登录状态，应停止该路线并重新评估受支持的数据接口或商店外公证分发。
