# 本地开发准备

准备日期：2026-09-13。

- Fork：https://github.com/dqrjz/Gifski
- 本地目录：`/Users/dqrjz/Documents/gif-maker/Gifski`
- 开发分支：`feature/text-overlay`
- 基线提交：`e184b284886929b9401e2442629a57650d3231f4`（3.0.6）。
- `origin` 指向个人 fork，`upstream` 指向 `sindresorhus/Gifski`，默认 push remote 为 `origin`。
- 开发范围见 `docs/TEXT-OVERLAY-PLAN.md`。文字编辑已实现并完成分阶段验证；改动尚未提交或推送。

## 已安装

Homebrew 安装 GitHub CLI 2.100.0、SwiftLint 0.65.1、rustup 1.29.1；rustup 安装 stable Rust 1.98.1（Apple Silicon）。

Rustup 为 Homebrew keg-only 包。已在 `~/.cargo/bin` 放置指向 Homebrew rustup 工具的链接，使项目已有的 Rust 构建脚本可找到它们。没有修改 shell 配置。终端可临时使用：

```sh
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
```

## 已完成的环境验证

- Xcode 26.6（17F113）已安装，命令行已选择完整 Xcode。
- GitHub CLI 已登录 `dqrjz`，使用 HTTPS。
- 首次构建发现缺少 Metal Toolchain，已通过 `xcodebuild -downloadComponent MetalToolchain` 安装 17F109。
- Swift Package 依赖解析通过，完整 Debug 无签名构建通过。
- 现有测试通过：96 个测试，含参数化测试共 100 次执行，0 失败、0 跳过。
- 测试使用 ad-hoc 签名和空 entitlements，仅验证本地基线；不代表分享扩展、App Group 或分发签名已验收。

## 可复现的基线验证

在仓库根目录执行：

```sh
bash scripts/check-dev-env.sh
xcodebuild -resolvePackageDependencies -project Gifski.xcodeproj -scheme Gifski
xcodebuild -project Gifski.xcodeproj -scheme Gifski -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/gifski-derived-data CODE_SIGNING_ALLOWED=NO build
```

最后一条验证无签名编译。Swift Package 依赖沿用仓库的 Package.resolved。测试可通过命令行覆盖使用本地 ad-hoc 签名，并清空上游 App Group entitlements；该配置仅供测试，不验证分享扩展或 App Group 功能，也不改动项目里的正式签名配置。后续交互开发版本应使用独立 bundle ID 和本地签名。

尚未改动签名设置、应用名称或安装目录，避免覆盖本机已有的 Gifski。Rust 静态库构建沿用仓库源码；本期不需要另外安装 FFmpeg 或命令行 gifski。

## 本地检查

已通过 `cargo check --locked --lib --manifest-path gifski-api/Cargo.toml --target-dir /tmp/gifski-dev-preflight-target`，验证 Rust 编码库依赖获取及类型检查正常；这不是完整静态库链接或 App 构建验证。

```sh
bash scripts/check-dev-env.sh
```

缺少 Xcode 或 CLI 登录时返回非零是预期行为。文字功能已实现；使用下文独立开发 App 验收。

无需额外中文字体即可开始，使用系统已安装的字体。真实视频样本不是开工阻塞项，后续可补充用于体验验收。

## 本地测试命令

可直接运行封装脚本：`bash scripts/verify-baseline.sh build` 或 `bash scripts/verify-baseline.sh test`。默认使用 Apple Silicon 本机目标，构建目录可由 `GIFSKI_DERIVED_DATA` 环境变量覆盖。

```sh
xcodebuild -project Gifski.xcodeproj -scheme Gifski -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/gifski-derived-data CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= test
```

构建日志：`/tmp/gifski-build.log`；测试日志：`/tmp/gifski-test.log`。派生构建产物在 `/tmp/gifski-derived-data`，未安装或覆盖 `/Applications/Gifski.app`。


## 文字编辑开发版（2026-09-14）

- 在视频编辑器工具栏点 **Text**，使用顶部 Picker 和 +/- 管理文字框。
- 文字支持多行中文、系统字体及真实 face、字号、填充和描边颜色/粗细、对齐、位置及换行框宽度。
- 可拖动文字及右侧宽度手柄；X/Y 滑块也可调整位置。完成提交会话，取消恢复进入时状态。支持 Undo/Redo 和 Cmd+Z / Cmd+Shift+Z。
- 普通预览、完整 GIF 预览、估算及最终导出使用同一文字参数。有文字时修剪条可收起，避免挡住底部字幕。
- 字体/描边等最近样式保存在本机偏好中，不保存文字内容。新视频不继承之前的文字。
- 含文字的视频导出暂未提供，菜单会禁用；GIF 导出正常。

构建并生成独立可运行版本：

```sh
bash scripts/build-text-dev.sh
```

输出 `/tmp/gifski-text-dev/Gifski Text Dev.app`，bundle ID 为 `com.dqrjz.Gifski.TextDev`。重建后退出旧进程再重开。脚本只修改构建副本的标识、名称和本地签名，并移除副本的分享扩展；不会覆盖 `/Applications/Gifski.app`。这不是发布签名或分享扩展验收。

最终全套回归：116 个测试、参数化共 123 次执行，0 失败/跳过。测试日志 `/tmp/gifski-text-stage-d-test.log`。视频集成测试所在的 Tests suite 使用串行执行，避免大量同步 AVAssetReader 占满协作线程池；纯文字测试保留并行。

开发交接与验证边界见 `docs/TEXT-OVERLAY-HANDOFF.md`；各阶段过程见 `docs/TEXT-OVERLAY-STAGE-A.md` 至 `TEXT-OVERLAY-STAGE-D.md`。
