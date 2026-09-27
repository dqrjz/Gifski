# 阶段 C：多文字框、会话与撤销

日期：2026-09-14。实现完成，主代理最终 UI 验收通过；未提交或推送。

## 本阶段

- 文字模式顶部使用紧凑 Picker 和 +/- 选择、添加、删除文字框。新层在最上方，不提供层级重排。画布也可直接选中文字。
- 属性区域继续使用原生两列控件，增加当前字体的“中文 Aa”轻量示例。
- TextEditingSession 集中保存当前视频的图层、选择、进入会话前快照与本地 UndoManager。完成保存样式；取消恢复全部图层及选择；结束操作幂等，取消后的 mode 回调不会再次保存。
- 拖动/宽度手柄及连续滑块操作结束时只记录一项 undo；添加、删除、属性变化可撤销/重做。工具栏和编辑菜单提供 Undo/Redo，支持 Cmd+Z、Cmd+Shift+Z。
- 文字输入使用原生 NSTextView。每个图层保留独立原生文本视图，共享会话 UndoManager，因此跨框切换不会让 native undo 指向其他框。同步模型时不覆盖 marked text，中文 IME 组合期间仍不运行后台编码。
- Undo/Redo 后同步读回保留的原生编辑器 storage，再选中实际变化的图层。NSUndoManager 直接修改非焦点 NSTextView 时不会可靠发送该视图 textDidChange，若不读回会被 SwiftUI 旧模型覆盖，造成跨框 redo 丢字；该缺陷已由单测复现并修复。
- 最近样式仅包含字体 face、字号/宽度比例、填充/描边及对齐，不保存文字、位置和 UUID。新视频从无图层开始。保存字体缺失时回退到系统 PingFang SC 并提示。
- Conversion/完整预览/估算继续使用完整图层数组快照；数组或文字变化使缓存失效。文字模式完成/取消后统一刷新。
- 有文字时普通和完整预览继续保留可折叠 trimmer，沿用文字编辑中的收起状态，避免默认底部文字被展开的修剪条挡住。无文字沿用原版行为。
- 从转换结果返回编辑器时 onAppear 重新同步“有文字”状态，确保视频导出菜单仍禁用。

## 主要文件

新增：
- `Gifski/Text/TextEditingSession.swift`
- `Gifski/Text/TextOverlayTextEditor.swift`
- `Gifski/Text/TextStylePreferences.swift`
- `Tests/TextEditingSessionTests.swift`

修改：`TextInspector.swift`、`TextOverlayCanvas.swift`、`EditScreen.swift`、`AppState.swift`、`App.swift`。此前 Conversion 的图层数组和渲染器直接复用。

## 验证

`bash scripts/verify-baseline.sh test`：112 个测试、参数化共 118 次执行，0 失败/跳过。日志 `/tmp/gifski-text-stage-c-test-3.log`，主代理已经独立核对 xcresult。

新增 5 个测试覆盖：连续变化一次撤销及重做；添加/删除顺序和取消幂等；跨层 native text undo、切层后 SwiftUI 同步再 redo；marked Chinese input 不被同步覆盖；样式不包含内容/位置/标识及字体缺失回退。

首次测试因测试夹具关闭 UndoManager 自动分组后错误嵌套 begin 清理历史而异常，已修正夹具初始化顺序。第二轮捕获了真实的跨框 native text 模型同步缺陷，修复后第三轮全套通过。

SwiftLint 对全部本阶段 Swift 文件通过，`git diff --check` 通过。

主代理已实际确认：多框输入；画布拖动一条 Undo/Redo；删除后 Undo 恢复图层及位置；裁剪后普通和完整预览相对位置一致。最终 native 跨层 Undo/Redo 修复构建已经主代理重测通过，Undo 自动选择被修改的第 2 框，Redo 恢复中文。

## 开发 App

`bash scripts/build-text-dev.sh` 已通过，最终日志 `/tmp/gifski-text-stage-c-dev-final.log`。

产物：`/tmp/gifski-text-dev/Gifski Text Dev.app`。

Bundle ID：`com.dqrjz.Gifski.TextDev`。CUA 使用 bundle ID 获取 App 可正常坐标拖动。未覆盖 `/Applications/Gifski.app`。

## 后续验收

阶段 D 继续完成长文本/小尺寸、透明/旋转视频、多框导出、颜色面板、实际 IME、撤销边界、窗口尺寸和性能矩阵。当前 .serialized 的原有视频 Tests suite 延续阶段 B，不改产品并发架构。
