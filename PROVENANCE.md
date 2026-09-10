# 代码来源与依赖说明

记录日期：2026-09-10。

## 实现范围

本项目按用户提出的触控板绝对坐标书写、独立分笔、自由画板、轻触增强、单键操作与桌面标记需求开发，由 AI 编程助手协助实现和验证。

- 输入模型、压力响应、手势与草稿格式位于 `Sources/InkModel.swift`。
- 公开 NSTouch / Force Touch 事件适配和画布绘制位于 `Sources/CanvasView.swift`。
- 逐点宽度路径、曲线插值与缓存位于 `Sources/InkRenderer.swift`。
- 桌面透明窗口、暂停穿透、工具条和独立保存位于 `Sources/DesktopOverlay.swift`。
- 菜单、单键分发与主画板位于 `Sources/App.swift`。

本轮实现未下载、复制或移植其他手写/标记应用的源代码。当前源码目录没有第三方源码包、Swift Package 依赖或其他依赖管理文件。版本 0.4 的应用改动基于本项目早期原型继续开发，并非从外部仓库 fork。

使用了常规几何与数值方法，例如坐标变换、双指中心/距离、Catmull–Rom 插值、指数平滑及圆片与四边形组成的笔画轮廓。这里说明的是这些方法在本项目中的实现来源，不主张发明通用算法，也不以代码来源说明代替对所有互联网项目的相似性审查。

## 运行依赖和资源

应用只链接 Apple 系统框架和系统运行库：AppKit、Foundation、CoreGraphics、UniformTypeIdentifiers 以及 Swift / 系统运行时。菜单栏符号使用系统 SF Symbols；笔迹和演示图由应用代码生成，不含下载的第三方图片、字体或界面素材。

构建使用 Apple Command Line Tools。发布过程使用 Git、GitHub CLI 和 macOS 的打包/签名工具；这些开发工具没有被打入应用或源码发布包。GitHub CLI 从其官方发行版下载并核对 SHA-256，仅用于发布。

## 文档参考

- [Apple：处理触控事件](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)
- [Apple：NSPressureConfiguration](https://developer.apple.com/documentation/appkit/nspressureconfiguration)
- [Apple：primaryGeneric 压力模式](https://developer.apple.com/documentation/appkit/nsevent/pressurebehavior-swift.enum/primarygeneric)
- [Apple：ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)
- [Apple：canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- [Apple：窗口命中查询](https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:))

这些参考用于理解系统 API 与行为，没有将第三方应用的实现作为本项目的代码模板。

## 名称检索

发布前使用 GitHub 仓库名称搜索检查 `trackpad-ink`、`TrackpadInk`、`zkalan-inkdeck`，均返回空结果；公开网页精确词搜索也未发现 `Zkalan InkDeck` / `ZkalanInkDeck` 的同名软件。正式发布使用带作者标识的 **Zkalan InkDeck**，仓库名称为 **zkalan/zkalan-inkdeck**。

此次搜索是公开资料范围的重名检查，不能排除未被索引、未公开或未来出现的同名内容，不是商标权利检索或唯一性保证。内部旧草稿目录 `TrackpadInk` 保留是为了兼容已有用户数据。
