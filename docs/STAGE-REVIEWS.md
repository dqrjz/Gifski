# 分阶段开发与验收记录

由一个实现子代理开发，主代理逐阶段验收。每阶段实现完成后暂停，验收通过再继续。所有改动保持在本地 feature/text-overlay，未授权自动发布。

## UI 验收原则

- 沿用 Gifski 原生 SwiftUI/AppKit 控件、字体层级、材料背景和系统配色。
- 文字入口与现有 Preview / Crop 工具栏入口一致，使用清晰名称与 SF Symbol。
- 普通转换界面维持原有两列设置组和底部 Convert 操作；文字属性仅在需要时显示。
- 面板标签和输入控件对齐，字体/样式同组，填充/描边同组；不使用新主题或无意义装饰。
- 预览区域始终可见，文字选框不遮挡时间段选择器；窄窗口下不截断控件。
- 实际验证中文输入、字体选择、描边、字号、拖动、取消与导出，截图检查整齐程度。

## 基线

- 提交 e184b28；Xcode 26.6；完整构建通过；96 个测试/100 次执行通过。
- 已通过原生 UI 查看原版编辑器，确认顶部 Preview / Crop、底部两列设置组和 Convert 布局。

## 阶段 A：模型与渲染探针

状态：主代理验收通过。已检查值模型、渲染器、Xcode target 接入及测试代码，核实 xcresult 全套 101 个测试通过（106 次执行）。已查看 `/tmp/gifski-text-overlay-stage-a/chinese-composite.png`，中文及混排白字黑边清晰、方向正确；GIF 探针由测试确认三帧和循环。空文字直通、缩放、透明度和非法输入有针对性验证。尚未接入正式视频导出/UI，允许进入阶段 B。

## 阶段 B：单文字框端到端

状态：主代理验收通过。实际操作独立开发 App，验证 Text 入口、两列原生面板、多行简体中文/英文、PingFang SC 与 Songti SC、face、字号、描边粗细、位置滑块、Done/Cancel、返回重编和完整 GIF 预览。保存实际 GIF 并独立解码：640×360、31帧、422592字节、无限循环，首帧文字位置/方向正确。修正版 X/Y 轴名已截图确认。独立读取 xcresult：107个测试/113次执行全通过，零失败/跳过。视频测试并发导致 AVAssetReader 首帧阻塞，Tests suite 串行后13秒通过，产品并发未改。

验收证据：`/tmp/gifski-text-qa/screenshots/01-original-editor.png` 至 `06-stage-b-drag.png`、`/tmp/gifski-text-qa/ui-export-frame.png`、`/tmp/gifski-text-qa/stage-b-ui-songti.gif.gif`。补充实测：CUA改用bundle ID连接后鼠标拖动和宽度手柄均正常，位置y从0.85变为0.4899，宽度从0.9变为0.4540；早先noWindowsAvailable是工具按App路径定位问题。剩余交互限制：颜色面板未能被工具展示，输入法组合未实测；颜色以聚焦测试补充，不宣称这两项已实测。

## 阶段 C：完整编辑与预览

状态：主代理验收通过。112个测试/118次执行全通过，已独立核对xcresult。修复版实际跨框Undo会切换到第2框，Redo恢复“第二行：独立文字”；原生两列UI新增紧凑选择器及加减按钮，截图09-multiple-text-final.png已查看。初版已通过多框拖动/删除撤销；会话取消、marked text同步保护及样式持久化由新增聚焦测试覆盖，最终端到端多框/竖屏输出进入D检查。

初版UI已发现并退回修正：输入第2框后切到第1框，Undo实际修改第2框却未同步选择；切回第2框再Redo未恢复文本。子代理以native测试复现并定位为非焦点NSTextView撤销通知缺失，待修复版重验。已通过的初版交互：多框添加/Picker选择、整次画布拖动Undo/Redo、删除及Undo恢复位置。原版展开的trimmer遮挡底部文字问题，已要求有文字时默认保持可折叠。

## 阶段 D：回归与打磨

状态：主代理最终验收通过。独立读取最终xcresult：116个测试/123次执行全通过，零失败/跳过；最终本地构建成功，diff检查无误。新增回归涵盖多层文字+旋转+裁剪、透明视频加字alpha、图层叠放和尺寸边界。

实际UI验证并解码查看：320×180多文字框GIF与360×640带track旋转的竖屏GIF均31帧，文字方向和位置正确；缩放后字号比例正确、Done后trimmer收起不遮挡底部文字；新视频只记住样式而不带入旧文本。多框和竖屏截图保存在工作区`../验收产物`，最终App在`../builds/Gifski Text Dev.app`，签名验证通过。原App未覆盖，未提交或推送。

保留验收范围说明：系统颜色面板未能通过CUA完整展示，真实拼音输入法组合未人工覆盖；分别已有颜色/编码和native marked-text保护测试。本次是本地开发验收，不包括App Group、分享扩展、公证或发布。

## 布局 BUG 修复：240×240 裁剪后退出文字编辑

状态：2026-09-15 主代理验收通过。面板高度切换后，叠加层仍可能使用 AVKit 尚未更新的 videoBounds；改为实际父视图坐标中的 frame 放置，在 layout 与下一主队列同步更新，并对画布尺寸变化完整重绘。棋盘背景明确转换到 SwiftUI 顶部原点坐标，缓存同时依赖宿主 bounds。

主代理实际 UI：自定义精确 240×240 裁剪，底部添加“怎么回事”（Y=0.85），连续三次进入/退出文字编辑，裁剪区域保持正方形、底部留白与相对文字位置一致。实际导出 GIF 首帧独立解码为 240×240 并检查完整底部。证据见 ../验收产物/布局修复240.gif、布局修复-编辑中.png、布局修复-退出编辑.png。

独立核对 xcresult：118 项测试/125 次执行通过，0 失败/跳过；新增画布缩放与非对称原点、70px 高度变化测试。最终 App：../builds/Gifski Layout Fix.app，独立 bundle com.dqrjz.Gifski.LayoutFix，签名检查通过。保留用户旧 App 与编辑会话，未覆盖 /Applications/Gifski.app，未提交/推送。

## 微信预设与加字体积异常修复（2026-09-15）

主代理验收通过。新增 Dimensions 首项“240 × 240 · WeChat Sticker”，按用户确认在当前选区内居中裁方再输出240×240；小于240的源选区禁用，沿用不放大的规则。新增横竖视频选区中心/包含关系、尺寸下限和预设识别回归。

体积异常定位：DimensionsSetting随文字面板切换重建，onAppear原先无条件恢复maximumDimensions。初始尺寸改为由_EditScreen初始化，控件出现时仅同步现有尺寸和类型。主代理实测选择预设→输入“怎么回事”→Done及连续两次Text/Done，始终240×240。界面证据 ../验收产物/微信预设-加字后尺寸保持.png。

子代理经真实GIFGenerator对14027相同0–3秒/居中裁方/10FPS/q80基准：240无字469199B、240有字460850B、474有字1457581B；全部31帧。编码本身没有复现暴增；未保留无证据的颜色空间改动、未降低FPS或Quality。保留H264加字后文字外像素一致的回归。对照GIF与说明位于 ../验收产物/加字体积对照。

主代理独立核对最终xcresult：121项/129次执行全部通过，0失败/跳过，diff检查及独立App签名验证通过。最终包 ../builds/Gifski Sticker Dev.app，bundle com.dqrjz.Gifski.StickerDev。原用户应用与编辑会话保留，未提交或推送。

## JSON工程文件（2026-09-16）

主代理最终验收通过。完成Save Project与Save GIF区分、编辑页Import Project、版本化JSON/原视频metadata与SHA256/全部渲染配置/实际字体及fallback文件指纹。实际UI恢复2倍速、非零trim0.5–2秒、240裁剪与中文，导出前后GIF完整字节一致，SHA256 616150a0d903b4ba591bd1ac2b14de5948fbbbc35a6143148cc678bf0b651db0。最终导出的工程settings与原工程完全一致。工程、两份GIF、截图与报告保存在 ../验收产物/工程文件往返。

验收中发现AVKit已有trim会话时canBeginTrimming持续false，修改为复用已有AVTrimView完成requestedTimeRange；真实手柄确认0.5/2且继续编辑正常。保存/导入对话框文案均已实际确认。

macOS/Xcode升级到27后补齐Metal27A266a。全套回归发现PreviewRenderer静态缓存并发创建/替换导致析构崩溃；以NSLock保护共享实例并新增64并发同实例测试。最终独立核对xcresult Test-Gifski-2026.09.16_22-25-13-+0800：123项/131次执行通过，无失败/跳过。SwiftLint与diff检查通过；最终已构建并启动 ../builds/Gifski Project Dev.app，签名验证通过，未覆盖原用户App，未提交/推送。

严格复现边界：同视频内容、同渲染器/应用/macOS和字体指纹；不兼容时拒绝导入。配置未改则转换完成校验原GIF SHA256，不一致不宣称导出成功。详见PROJECT-FILES.md。


## 2026-09-27 — Fixed timeline below video

- Replaced the collapsible overlay with a fixed 76pt timeline below the player. Retains native thumbnail strip, trim handles and play/pause. No expand/collapse button.
- Text editing, crop editing and project import disable timeline input; Done/Cancel restores it. Disabled accessibility exposes only the Timeline group to avoid AVKit virtual-slider actions.
- UI acceptance on macOS 27: default Chinese text → Done retains timeline; 0.5–3.0s trim edits work; square crop and exit retain timeline; project import restores trim, square crop and text. GIF re-export hash matches the saved project: `af7c396438d2bf6d663820b375557f13db47a0270463e97a2225af453e487177`.
- Baseline test suite: 123 tests / 131 executions passed, zero failures. Final accessibility amendment additionally passed parse, typecheck, SwiftLint, full build and live AX restore verification. `git diff --check` clean. Mouse drag automation was unavailable (CUA windowNotFoundAtPosition); trim changes were verified through native accessibility value actions.
- Runnable build: `../builds/Gifski Timeline Dev.app`, ad hoc signature verified. Evidence: `../验收产物/timeline-20260927/`.
