# 阶段 A：文字值模型与渲染探针

日期：2026-09-13。本阶段未接入应用 UI 或正式 GIFGenerator 主路径。

## 实现

- `Gifski/Text/TextOverlay.swift`：可序列化、可比较、Sendable 的静态文字参数。系统字体具体 PostScript face 同时表示字体样式/字重；默认 PingFangSC-Semibold。
- `Gifski/Text/TextOverlayRenderer.swift`：Core Text 多行排版、独立描边后填充、sRGB 透明图层、CGImage 合成；返回未裁切的 top-left 字形边界（包括 overhang、描边和 1 px 安全余量）。纯函数式调用，不含全局缓存。导出接入时每个任务缓存一个 Layer。
- `Gifski.xcodeproj/project.pbxproj`：Text 文件夹按 Crop 同样方式加入同步 target。
- `Tests/TextOverlayTests.swift`：5 个聚焦测试、参数化共 6 次执行。

位置/宽度相对最终输出画布，字号/总描边宽度相对画布高度。描边是路径两侧的总宽度，先画轮廓再画填充后，可见外轮廓约为该宽度的一半。面板阶段必须明确实际显示单位。

## 输入与越界

- 空文本/全空白不生成图层；nil 图层直接返回原 CGImage，不分配和复制。
- 画布必须为正整数，每边不超过 32768，像素总数不超过 67108864（单层 RGBA 约 256 MiB），超限抛错。
- 比例数值须有限，宽度/字号须大于零，描边须非负。
- 防异常参数上限：字号和描边 4096 px；排版宽高 65536 px；中心比例绝对值 100；文字最多 100000 个 UTF-16 单元。后续 UI 正常范围应更收敛。
- 合成要求图层与源图尺寸一致，否则抛错。
- 超出画布的正常文字不静默缩小；绘制统一由画布裁切。返回未裁切边界，供后续 UI 限位/越界提示。
- 颜色分量限制在 0...1，非有限分量取 0。
- 不可用字体由 Core Text 回退；字体缺字提示、字体列表属于后续 UI 阶段。

## 验证

`bash scripts/verify-baseline.sh test`：101 个测试、参数化共 106 次执行，0 失败，0 跳过。日志 `/tmp/gifski-text-stage-a-test.log`。

`/opt/homebrew/bin/swiftlint lint --quiet Gifski/Text Tests/TextOverlayTests.swift` 与 `git diff --check` 通过。Xcode 仍有基线 Frameworks 搜索目录不存在的链接警告；新增文件无 lint 警告。

覆盖模型快照、空文字直通、PingFang/Songti 两种系统字体、描边扩大可见像素、透明画布、像素与 top-left 边界吻合、尺寸比例、非法输入，以及合成帧经过实际 libgifski 编码后仍包含文字、帧数和无限循环。

## 图像验收

探针采用三张合成背景帧（移动方块），编码器使用应用的 Gifski 类；没有替换正式视频解码或导出链路。不是视频输入端到端验收；阶段 B 接入 GIFGenerator 后验证真实视频。

测试写入应用沙盒 temporaryDirectory 下 `gifski-text-overlay-stage-a`；本次已复制到方便验收的路径：

- `/tmp/gifski-text-overlay-stage-a/chinese-composite.png`
- `/tmp/gifski-text-overlay-stage-a/chinese-animation.gif`

PNG 已人工查看：多行中文、英文和标点白色填充、黑色描边清晰，位置正确，无上下颠倒。GIF 通过解码像素和元数据验证；动态播放交给主代理验收。

## 后续接入约束

渲染器统一 sRGB，保留 alpha；宽色域/HDR 转换实际视频的色彩验证留到正式链路接入。应用 UI 中避免在连续拖动期间重新编码。字体控件只列真实 face，不制造伪粗体/斜体。正式参数快照与预览缓存必须加入文字数据。
