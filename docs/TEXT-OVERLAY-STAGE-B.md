# 阶段 B：单文字框端到端

日期：2026-09-13。待主代理最终验收。本阶段未提交或推送。

## 已实现

- 工具栏 Text 入口，文字模式替换原转换设置区域；两列原生 TextEditor、Picker、ColorPicker、Slider 和数字输入。完成、取消和删除文字；非文字模式不占属性面板空间。
- 系统字体家族/真实 face，字号（输出 px）、填充与描边颜色、描边粗细、对齐、宽度、带 X/Y 标签的位置；字体缺少中文时提示系统回退。
- 普通视频上的文字预览复用渲染器，按实际视频区域中的 crop rect 显示。原生画布可拖动文字、拖右边手柄调整换行宽度；调整位置按字形边界限位；文字太大/滑块移到画布外时显示越界提示。
- 文字模式不运行后台估算或 GIF 编码；完成或取消后刷新。文字模式中 Convert 禁用，避免输入法组合期间直接转换。
- 真正 GIFGenerator 在方向/裁剪/缩放后绘字；每个转换只渲染一张静态文字层，各视频采样帧合成一次，正向和 bounce 复用同一结果。无文字时不提前解码首帧，不创建文字层。
- Conversion、SettingsForFullPreview 传递并比较文字参数，完整 GIF 预览及估算自动包含文字；完整预览期间隐藏轻量叠层，防止重复绘字。
- 文字非空时禁用 Export as Video 菜单，并给说明；回调也防止绕过后静默丢字。
- 播放器视频区域改变时更新 overlay 布局，支持窗口尺寸变化。

## 文件

新增 `Gifski/Text/SystemFontCatalog.swift`、`TextInspector.swift`、`TextOverlayCanvas.swift`、`TextOverlayGeometry.swift`。

修改 `EditScreen.swift`、`AppState.swift`、`App.swift`、`Components/TrimmingAVPlayer.swift`、`GIFGenerator.swift`、`Preview/SettingsForFullPreview.swift`、`Tests/Tests.swift`、`Tests/TextOverlayTests.swift`。阶段 A 的同步 Text 目录自动包含新增文件。

## 验证

- `bash scripts/verify-baseline.sh test`：107 个测试、参数化共 113 次执行，0 失败、0 跳过，约 13 秒。
- 新增阶段 B 覆盖：预览快照往返和缓存失效、真实视频 crop/bounce 后文字像素与无文字基线帧数一致、同一 generator 后续转换无文字残留、估算中确有文字、拖动缩放换算和四边限位、宽度限制、RGBA 与 NSColor 往返。
- `swiftlint lint --quiet` 对全部改动 Swift 文件通过；`git diff --check` 通过。
- 最终测试日志 `/tmp/gifski-text-stage-b-test-final.log`。
- 主代理 UI 验收已经操作系统字体切换（宋体）、中文多行输入、字号、取消恢复和真实 GIF 导出。结果 `/tmp/gifski-text-qa/stage-b-ui-songti.gif.gif`：640×360、31 帧、LoopCount 0、422592 字节；首帧 `/tmp/gifski-text-qa/ui-export-frame.png`。完整 GIF 预览也包含文字。

## 测试调度问题

新增视频测试首次全并行运行时，6 个 AVAssetReader 在首帧 `copyNextSampleBuffer` 等待，涉及新增文字测试和原有无文字测试，发生在文字渲染之前。取样 `/tmp/gifski-text-stage-b-sample.txt` 表明协作线程池被同步读帧占满，异步 compositor 无法推进。

现有真实视频测试与纯函数测试共用一个 `Tests` struct 和其私有 helper，因此暂将该 suite 标记 `.serialized`，没有为此大规模拆分上游测试，也没有修改产品并发架构。单独 `TextOverlayTests` 仍并行。串行运行解决阻塞且全套约 13 秒。生产端极端并发读帧的底层风险不在本阶段宣称已修复。

## 独立开发 App

执行 `bash scripts/build-text-dev.sh`：先构建，再复制到 `/tmp/gifski-text-dev/Gifski Text Dev.app`，设置独立 bundle ID `com.dqrjz.Gifski.TextDev`、显示名称，并以 ad-hoc 签名。移除副本分享扩展和 URL scheme，仅验证本地文字编辑，不验证 App Groups/分享扩展/发布签名。

不修改或覆盖 `/Applications/Gifski.app`。重建后须退出旧开发 App 进程再重新打开。最终构建日志 `/tmp/gifski-text-dev-build-final.log`。

主代理提供验收视频 `/tmp/gifski-text-qa/landscape.mp4`（640×360）和 `portrait.mp4`（360×640）。

## 验收限制与后续

- CUA 当前坐标 drag/click 报 noWindowsAvailable，因此真实拖动手感未完成自动 UI 验收；已用纯函数测试覆盖换算和限位，不能代替真实手感验收。
- CUA 未读到系统颜色面板，因此实际选色面板交互待人工验证；ColorPicker 的原生 binding 与颜色模型往返已有测试。
- 单文字框，暂不做多框、会话撤销/重做、最近样式持久化（阶段 C）。普通 TextEditor 的文本编辑行为由系统处理。
- 超大画布连续拖动的性能、极端字体/长文、透明和宽色域视频等完整矩阵留阶段 D。渲染器基础限制沿用阶段 A。
