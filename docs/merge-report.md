# 源码合并报告

## 范围与来源

- A：原 A 源码工作区。按任务要求，以其**实际工作区**为准，包含未提交的菜单栏定位、图标、资源和构建脚本修改。
- B：目标目录原有的 `CodexTools.zip`，解压到本机临时解压目录。包含 `CodexUsageAlert-development-log` 和 `CodexUsageAlert` 两份源码；后者与合并前目标目录逐文件 SHA-256 完全相同，并含 10 月 4 日记录，不能仅按压缩包的 9 月目录日期判断新旧。
- 目标目录：本仓库工作区。合并前完整备份（原 ZIP 留在原位）保留在本机合并前备份目录。
- 当前为任务执行对话，复用已有日志与版本规则，不另建统筹中心。

## Git 历史

A 的 HEAD 为 `d2c7e31819a10d0b18bc56a74dfa04ef304a5daf`（6 次提交），是目标仓库原 HEAD `c0f1201`（27 次提交）的祖先。保留目标现有 `.git` 即同时保留 A 的全部历史和 B 的后续历史；没有替换 Git 数据，也没有使用 B 中的 worktree 指针。

合并在 `merge/usage-sources` 分支完成一个提交，保留原分支。工作区内容按 A 选取，不等于撤销或删除 B 的历史提交。按现有十进制规则，本次版本为 **0.2.8 / Build 28**；A 原始工作区的 `0.1.1 / Build 3` 仅作为来源记录。

## 文件对比

所有普通源码、文档和资源均按相对路径逐文件计算 SHA-256；排除 `.git`、构建目录、`dist`、`.DS_Store` 和 macOS AppleDouble 元数据。完整文件与哈希见 [merge-inventory.json](merge-inventory.json)。历史打包目录另有本机清单 `archive-dist/manifest.json`。

| B 子目录 | 与 A 相同 | 与 A 冲突 | B 独有 | A 独有 |
| --- | ---: | ---: | ---: | ---: |
| CodexUsageAlert-development-log | 5 | 23 | 14 | 18 |
| CodexUsageAlert | 3 | 25 | 16 | 18 |

## 合入内容与冲突处理

1. A 的 46 个源码、测试、资源、脚本和文档文件成为主实现。除版本字段和新增忽略规则外，保持与 A 文件内容一致。包括 A 未提交的 `MenuBarPlacement.swift`、对应测试、`AppIcon.icon`、`Assets.xcassets`、`Resources/Brand` 和图标生成脚本。
2. 保留 B 较完整的 `DEVELOPMENT_LOG.md`、`CHANGELOG.md`、现有 `AGENTS.md`、`docs/versioning.md` 与 `scripts/sync_version.sh`。两份 B 的旧日志已被完整历史记录涵盖，不重复堆叠。旧版日志描述历史分支，不表示所有旧功能仍在当前 A 实现中。
3. 补充 B 独有的 `docs/build-variants.md`、`docs/sandbox-prototype.md`、`docs/user-guide.txt`，均标明历史参考，避免误认为当前可用流程。
4. B 独有的两份 Swift 文件、沙盒权限、两份本地化资源、旧图标母版与两个打包脚本移入 [legacy/b-only](../legacy/b-only/README.md)，保留原相对路径。它们依赖 B 核心代码，不能直接编入 A。完整 B 可从 `c0f1201` 或原 ZIP 恢复。
5. 共用文件冲突均选 A。`.gitignore` 保留 A 的规则并增加 `archive-dist/`、`dist-sandbox/`；`Info.plist` 仅按仓库规则同步版本。未改动 A 原目录或原 ZIP。

### B 中值得后续移植的差异

| 文件/组件 | B 中有价值的内容 | 本次处理 |
| --- | --- | --- |
| `Sources/CodexUsageAlert/CodexUsageAlertApp.swift`、`UsageMonitor.swift` | 中英文切换、沙盒授权 UI、昨日预算结转；B 主项目还有后台驻留、四档自定义阈值、说明浮窗和 Token 图表悬停 | 运行实现选 A，保留 B Git 历史供单独移植 |
| `Sources/UsageCore/CodexAppServerClient.swift` | 用户选择 Codex 可执行文件/认证目录、沙盒下启动与访问处理 | 选 A，B 的 `CodexAccessStore.swift` 保留为历史源码 |
| `Sources/UsageCore/UsageSnapshot.swift` | 预算结转与缓存策略；B 主项目还有 Token 本机日期适配 | 选 A；日期顺序映射会改变统计语义，未擅自移植 |
| `Tests/UsageCoreTests/UsageCoreTests.swift` | B 上述功能的测试 | 选 A，避免引入当前实现不存在的 API；保留 A 新增的菜单栏定位测试 |
| `Resources/Info.plist`、图标集 | B 的 CoMex 品牌及旧图标；A 的原生图标组合与新版图标资源 | 保留 A 品牌、图标、系统设置；版本单独同步 |
| `README.md`、`docs/README.md`、开发计划/商店资料/开发提示词 | B 的沙盒、品牌、分发与新增功能说明 | 共用文档选 A，独有文档加历史说明保留 |
| `scripts/build_app.sh` | B 的版本同步、正式签名/本地化资源打包；A 的原生图标编译与 SDK 参数 | 当前脚本选 A；B 的 DMG/沙盒脚本保留作参考，本次未发布或签名打包 |

### 逐文件结果

#### CodexUsageAlert-development-log

| 相对路径 | 比较结果 | 处理 |
| --- | --- | --- |
| `LICENSE` | 相同 | 采用 A |
| `Package.swift` | 相同 | 采用 A |
| `Sources/CodexUsageCLI/main.swift` | 相同 | 采用 A |
| `docs/app-store-metadata.md` | 相同 | 采用 A |
| `docs/development-prompt.md` | 相同 | 采用 A |
| `.gitignore` | 冲突 | 保留 A，并补充归档忽略规则 |
| `README.md` | 冲突 | 采用 A |
| `Resources/AppIcon.icns` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_128x128.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_128x128@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_16x16.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_16x16@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_256x256.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_256x256@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_32x32.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_32x32@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_512x512.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_512x512@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.png` | 冲突 | 采用 A |
| `Resources/Info.plist` | 冲突 | 保留 A，仅同步版本为 0.2.8 / Build 28 |
| `Sources/CodexUsageAlert/CodexUsageAlertApp.swift` | 冲突 | 采用 A |
| `Sources/CodexUsageAlert/UsageMonitor.swift` | 冲突 | 采用 A |
| `Sources/UsageCore/CodexAppServerClient.swift` | 冲突 | 采用 A |
| `Sources/UsageCore/UsageSnapshot.swift` | 冲突 | 采用 A |
| `Tests/UsageCoreTests/UsageCoreTests.swift` | 冲突 | 采用 A |
| `docs/README.md` | 冲突 | 采用 A |
| `docs/app-store-development-plan.md` | 冲突 | 采用 A |
| `scripts/build_app.sh` | 冲突 | 采用 A |
| `AGENTS.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `CHANGELOG.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `DEVELOPMENT_LOG.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/AppIcon-master.png` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/AppStorePrototype.entitlements` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/en.lproj/InfoPlist.strings` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/zh-Hans.lproj/InfoPlist.strings` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Sources/CodexUsageAlert/AppLocalization.swift` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Sources/CodexUsageAlert/CodexAccessStore.swift` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `docs/build-variants.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `docs/sandbox-prototype.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `docs/user-guide.txt` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `scripts/build_dmg.sh` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `scripts/build_sandbox_app.sh` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/AppIcon.icon/Assets/Brand.png` | A 独有 | 采用 A |
| `Resources/AppIcon.icon/icon.json` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` | A 独有 | 采用 A |
| `Resources/Brand/AppIcon-source.png` | A 独有 | 采用 A |
| `Resources/Brand/README.md` | A 独有 | 采用 A |
| `Sources/UsageCore/MenuBarPlacement.swift` | A 独有 | 采用 A |
| `Tests/UsageCoreTests/MenuBarPlacementTests.swift` | A 独有 | 采用 A |
| `scripts/produce_icons.py` | A 独有 | 采用 A |

#### CodexUsageAlert

| 相对路径 | 比较结果 | 处理 |
| --- | --- | --- |
| `LICENSE` | 相同 | 采用 A |
| `Package.swift` | 相同 | 采用 A |
| `Sources/CodexUsageCLI/main.swift` | 相同 | 采用 A |
| `.gitignore` | 冲突 | 保留 A，并补充归档忽略规则 |
| `README.md` | 冲突 | 采用 A |
| `Resources/AppIcon.icns` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_128x128.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_128x128@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_16x16.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_16x16@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_256x256.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_256x256@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_32x32.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_32x32@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_512x512.png` | 冲突 | 采用 A |
| `Resources/AppIcon.iconset/icon_512x512@2x.png` | 冲突 | 采用 A |
| `Resources/AppIcon.png` | 冲突 | 采用 A |
| `Resources/Info.plist` | 冲突 | 保留 A，仅同步版本为 0.2.8 / Build 28 |
| `Sources/CodexUsageAlert/CodexUsageAlertApp.swift` | 冲突 | 采用 A |
| `Sources/CodexUsageAlert/UsageMonitor.swift` | 冲突 | 采用 A |
| `Sources/UsageCore/CodexAppServerClient.swift` | 冲突 | 采用 A |
| `Sources/UsageCore/UsageSnapshot.swift` | 冲突 | 采用 A |
| `Tests/UsageCoreTests/UsageCoreTests.swift` | 冲突 | 采用 A |
| `docs/README.md` | 冲突 | 采用 A |
| `docs/app-store-development-plan.md` | 冲突 | 采用 A |
| `docs/app-store-metadata.md` | 冲突 | 采用 A |
| `docs/development-prompt.md` | 冲突 | 采用 A |
| `scripts/build_app.sh` | 冲突 | 采用 A |
| `AGENTS.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `CHANGELOG.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `DEVELOPMENT_LOG.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/AppIcon-master.png` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/AppStorePrototype.entitlements` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/en.lproj/InfoPlist.strings` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/zh-Hans.lproj/InfoPlist.strings` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Sources/CodexUsageAlert/AppLocalization.swift` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Sources/CodexUsageAlert/CodexAccessStore.swift` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `docs/build-variants.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `docs/sandbox-prototype.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `docs/user-guide.txt` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `docs/versioning.md` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `scripts/build_dmg.sh` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `scripts/build_sandbox_app.sh` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `scripts/sync_version.sh` | B 独有 | 保留；实现相关文件放入 legacy/b-only，文档与规则保留在原路径 |
| `Resources/AppIcon.icon/Assets/Brand.png` | A 独有 | 采用 A |
| `Resources/AppIcon.icon/icon.json` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png` | A 独有 | 采用 A |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` | A 独有 | 采用 A |
| `Resources/Brand/AppIcon-source.png` | A 独有 | 采用 A |
| `Resources/Brand/README.md` | A 独有 | 采用 A |
| `Sources/UsageCore/MenuBarPlacement.swift` | A 独有 | 采用 A |
| `Tests/UsageCoreTests/MenuBarPlacementTests.swift` | A 独有 | 采用 A |
| `scripts/produce_icons.py` | A 独有 | 采用 A |

## 历史打包归档

A 和 B 中的三个 `dist` 树按来源分别复制到 `archive-dist/A/dist/`、`archive-dist/B/dist/` 和 `archive-dist/B/CodexUsageAlert/dist/`，保留同名版本，避免相互覆盖。共 3,083 个文件（含 A 的构建缓存和图标验证产物），约 351 MB 磁盘占用，全部被 Git 忽略；根目录没有历史 `dist`。原 A 的 dist 和原 ZIP 均保持不变。

## 验证

- `swift build && swift test`：成功；10 项 XCTest 通过，0 失败（菜单栏定位 4 项、核心用量 6 项）。
- 编译保留 A 原有的一条警告：`UsageMonitor.swift:137` 内层 `[weak self]` 与外层隐式强捕获不一致。为保持 A 冲突优先，本次未改动该代码。
- `plutil -lint Resources/Info.plist` 与 `zsh -n scripts/build_app.sh scripts/sync_version.sh` 通过；版本为 `0.2.8 / Build 28`。
- A 共 44 个文件逐字节一致；其余两个文件仅有版本同步和忽略规则追加，Info.plist 其他键值完全一致。
- B 的 8 个历史实现文件与 ZIP 内主项目哈希一致；3,083 个归档文件逐一与来源核对一致，全部受 Git 忽略。
- A 全目录（含 `.git`）及原 ZIP 的 SHA-256 完整性检查通过；根目录没有历史 dist，Git 不追踪 ZIP 或归档目录。
- 未进行 GUI、安装、签名或发布验证；本任务交付为可编译、已通过现有测试的源码合并。
- 任务状态：验证通过，随本报告提交一个合并提交（提交号见 Git 历史及外部任务交接记录）。
