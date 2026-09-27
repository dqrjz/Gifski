# 文字编辑开发交接

2026-09-14。基于上游 `e184b284886929b9401e2442629a57650d3231f4`，分支 `feature/text-overlay`。所有功能改动保留在工作区，未提交/推送。

## 结果

视频转换 GIF 的多文字框编辑已贯通：系统字体/face、中文、多行、字号、颜色、描边、对齐、拖动、宽度、会话取消、撤销/重做及最近样式。普通和完整预览、文件大小估算、真实 GIF 输出均包含文字。暂不支持 GIF 文件导入或含文字的视频输出。

本地 App：`/tmp/gifski-text-dev/Gifski Text Dev.app`。

重建：`bash scripts/build-text-dev.sh`；测试：`bash scripts/verify-baseline.sh test`。

## 结构与维护约定

- `TextOverlay` 为 Codable/Hashable/Sendable 值模型。数组顺序即绘制顺序；具体 PostScript face 表示真实字体样式，不另造伪字重。
- 坐标采用最终裁剪输出画布的左上角，位置/框宽为比例，字号/描边为画布高度比例。UI 显示输出像素值。窗口 backing scale 不参与文字输出尺寸。
- `TextOverlayRenderer` 使用 Core Text，先轮廓后填充，生成 sRGB 透明 CGImage 并返回未裁切字形边界。描边 px 表示路径的总宽度，露出填充之外的部分约为一半。
- `GIFGenerator.readFrames` 在方向、裁剪、尺寸完成后合成。静态图层只在每个转换中生成一次，正向和 bounce 共用合成帧；无文字直接走原图，不为文字额外解码首帧或分配图层。
- `SettingsForFullPreview` 的快照/比较/回转包括图层数组；不要只在编辑器画面绘字而漏掉完整 GIF 预览或估算。
- `TextEditingSession` 属于当前视频，管理图层、选择、进入会话快照与 UndoManager。连续 slider/drag 在结束时登记一项历史；文本输入不重复登记模型快照。
- `TextEditorPool` 每个图层保留原生 NSTextView，同一个会话 UndoManager。跨框 native undo 不可靠触发非焦点视图的 textDidChange，所以 Undo/Redo 后必须先从所有保留编辑器读回 storage，再让 SwiftUI 更新；不能移除此同步步骤。
- `TextEditorPool.synchronize` 不覆盖 marked text。文字模式期间不发起后台编码，结束/取消后刷新。
- `TextStylePreferences` 只存样式，不存文字、UUID、位置；缺字体回退并提示。
- `TextOverlayCanvas` 把输出坐标映射到实际视频区域中的 crop rect。画布重布局跟随 videoBounds，支持窗口和裁剪变化。有文字时 trimmer 保留可折叠。
- `AppState.hasTextOverlays` 是视频导出菜单状态，进入编辑器/参数变化/返回转换结果时都要同步；视频导出闭包仍保留独立防丢字检查。

## 最终验证

116 个测试、参数化 123 次执行，全部通过；改动 Swift 文件的 SwiftLint 和 `git diff --check` 通过。

覆盖：模型快照/缓存失效、中文字体/描边、几何和 alpha、图层叠放、真实视频裁剪/bounce/估算、两层文字在带 90° preferredTransform 视频上的方向与位置、透明视频叠字仍保留透明角、非法尺寸/超大参数、连续操作合并撤销、跨层 native undo/redo、marked Chinese input、样式隐私及字体缺失回退。

主代理实际 UI 验收：多框中文和宋体/描边、拖动/宽度、取消、跨框 Undo/Redo、删除/恢复、裁剪普通/完整预览一致、320×180 多框 GIF 和 360×640 旋转竖屏 GIF 实际导出/解码、新视频仅继承样式。

日志：`/tmp/gifski-text-stage-d-test.log`，最终构建日志 `/tmp/gifski-text-stage-d-dev-final.log`。验收视频/图片/GIF 在 `/tmp/gifski-text-qa`；这些临时产物不是仓库依赖，测试自建视频。

## 实际边界

文字渲染单边不超过 32768、总像素不超过 67108864（仅一张 RGBA 图层约 256 MiB）；字号/描边最多 4096 px、排版框上限 65536 px、最多 100000 UTF-16 单元。超限有明确错误，不默默缩字号。该限制针对含文字输出，无文字路径保持原行为。

使用系统原生颜色面板和 ColorPicker binding，颜色模型往返/实际彩色图层编码已有测试；主代理尚未通过 CUA 完成系统颜色面板选色的完整交互流程。真实输入法用户连续输入体验及长时间 4K 压力测试不等同于当前自动化 marked-text/边界测试，需要后续使用中继续观察。

AVFoundation 视频集成测试套件暂串行，避免同步首帧读取使协作线程池饥饿；未为此修改生产并发架构。开发副本使用独立标识和 ad-hoc 签名，分享扩展、App Groups、发布签名未作为本期交付验收。
