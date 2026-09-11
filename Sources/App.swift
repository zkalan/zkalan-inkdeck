import AppKit
import UniformTypeIdentifiers

private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byWordWrapping
    field.maximumNumberOfLines = 0
    return field
}

final class PadMapView: NSView {
    var pointer: InkPoint? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        NSColor.white.withAlphaComponent(0.7).setFill()
        let pad = NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13)
        pad.fill()
        InkColor.green.nsColor.withAlphaComponent(0.3).setStroke()
        pad.lineWidth = 1.5; pad.stroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: rect.midX, y: rect.minY + 10)); cross.line(to: NSPoint(x: rect.midX, y: rect.maxY - 10))
        cross.move(to: NSPoint(x: rect.minX + 10, y: rect.midY)); cross.line(to: NSPoint(x: rect.maxX - 10, y: rect.midY))
        cross.setLineDash([3, 4], count: 2, phase: 0); cross.lineWidth = 0.6; cross.stroke()
        if let pointer {
            let x = rect.minX + pointer.x * rect.width
            let y = rect.minY + pointer.y * rect.height
            InkColor.green.nsColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - 12, y: y - 12, width: 24, height: 24)).fill()
            InkColor.green.nsColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: x - 4, y: y - 4, width: 8, height: 8)).fill()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let canvas = CanvasView(frame: .zero)
    lazy var preferences = InkPreferences(persistent: !smokeMode)
    let palettePanel = InkPalette()
    lazy var colors = ColorControls(preferences: preferences)
    let drawingModeControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let eraserButton = NSButton(title: "橡皮擦 E", target: nil, action: nil)
    lazy var desktop = DesktopOverlay(smokeMode: smokeMode, preferences: preferences, palette: palettePanel)
    var window: NSWindow!
    var statusItem: NSStatusItem?
    private var workspaceObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?
    let startButton = NSButton(title: "开始书写  ↩", target: nil, action: nil)
    let undoButton = NSButton(title: "撤销", target: nil, action: nil)
    let redoButton = NSButton(title: "重做", target: nil, action: nil)
    let clearButton = NSButton(title: "清空", target: nil, action: nil)
    let exportButton = NSButton(title: "导出 PNG", target: nil, action: nil)
    let stateLabel = label("准备就绪", size: 13, weight: .semibold)
    let messageLabel = label("", size: 12, color: .secondaryLabelColor)
    let deviceLabel = label("", size: 11, color: .secondaryLabelColor)
    let coordinateLabel = label("X —    Y —", size: 12, weight: .medium)
    let countLabel = label("0 笔画 · 0 次输入", size: 11, color: .secondaryLabelColor)
    let saveLabel = label("草稿自动保存到本机", size: 11, color: .secondaryLabelColor)
    let zoomLabel = label("100%", size: 12, weight: .medium)
    let widthLabel = label("4.0", size: 11)
    let pressureLabel = label("力度 0% · 等待按压", size: 11, color: .secondaryLabelColor)
    let pressureMeter = NSProgressIndicator()
    let handButton = NSButton(title: "拖动", target: nil, action: nil)
    let helpButton = NSButton(title: "帮助", target: nil, action: nil)
    let desktopButton = NSButton(title: "桌面标记 F", target: nil, action: nil)
    let inputMode = NSPopUpButton(frame: .zero, pullsDown: false)
    let helpPopover = NSPopover()
    private var noticeText = ""
    private var noticeUntil = Date.distantPast
    let padMap = PadMapView(frame: .zero)
    var keyboardMonitor: Any?
    var saveTimer: Timer?
    private var pendingSaveError: String?
    var dataURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrackpadInk", isDirectory: true).appendingPathComponent("draft-v2.json")
    }
    var smokeMode: Bool { ProcessInfo.processInfo.arguments.contains("--smoke-test") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApplication = front
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.lastExternalApplication = app }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 830), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Zkalan InkDeck"
        window.subtitle = "0.5 · 示意图与橡皮擦"
        window.minSize = NSSize(width: 1000, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildInterface()
        canvas.drawingMode = preferences.mode
        canvas.engine.onColorUsed = { [weak self] color in self?.preferences.record(color) }
        if !smokeMode { restore() }
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onDocumentChange = { [weak self] in self?.scheduleSave() }
        desktop.onExit = { [weak self] in self?.showDrawingWindow() }
        buildStatusMenu()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyboard(event)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
        if smokeMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.runSmokeTest() }
        }
    }

    func handleKeyboard(_ event: NSEvent) -> NSEvent? {
        // Always release the clutch, including when modifiers change before key-up.
        if event.keyCode == 49 && event.type == .keyUp && canvas.spacePressed {
            canvas.setSpacePressed(false); return nil
        }
        if desktop.isVisible { return desktop.handleKeyboard(event) }
        if helpPopover.isShown && event.type == .keyDown && event.modifierFlags.intersection([.command, .control, .option]).isEmpty && (event.keyCode == 4 || event.keyCode == 53) {
            helpPopover.close(); return nil
        }
        guard event.window === window || (event.window == nil && window.isKeyWindow),
              window.attachedSheet == nil, !(window.firstResponder is NSTextView),
              !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) else { return event }
        if event.keyCode == 49 && canvas.isWriting && !event.modifierFlags.contains(.command) {
            if !event.isARepeat { canvas.setSpacePressed(event.type == .keyDown) }; return nil
        }
        guard event.type == .keyDown else { return event }
        // Keep standard system shortcuts such as Command-H available to macOS.
        if event.modifierFlags.contains(.command), ![36, 76, 6, 16, 24, 27, 29, 25, 1].contains(event.keyCode) { return event }
        if event.isARepeat && [36, 76, 1, 4, 3, 14, 40, 46].contains(event.keyCode) { return nil }
        switch event.keyCode {
        case 36, 76: toggleWriting()
        case 53: endWriting()
        case 6: event.modifierFlags.contains(.shift) ? redoStroke() : undoStroke()
        case 16: redoStroke()
        case 24: zoomIn()
        case 27: zoomOut()
        case 29: resetView()
        case 25: fitView()
        case 1: exportPNG()
        case 4: showHelp()
        case 3: toggleDesktop()
        case 14: toggleEraser()
        case 40: showPalette()
        case 46: toggleDrawingMode()
        default: return event
        }
        return nil
    }

    func buildInterface() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.95, alpha: 1).cgColor
        window.contentView = root
        startButton.target = self; startButton.action = #selector(toggleWriting)
        startButton.bezelStyle = .rounded; startButton.controlSize = .regular
        startButton.bezelColor = InkColor.green.nsColor
        startButton.font = .systemFont(ofSize: 12, weight: .semibold)
        startButton.toolTip = "开始或结束书写 · Enter · Esc 退出"

        colors.onPick = { [weak self] in self?.showPalette() }
        colors.onSelect = { [weak self] color in self?.selectColor(color) }
        let brush = NSSegmentedControl(labels: ["普通笔", "毛笔"], trackingMode: .selectOne, target: self, action: #selector(changeBrush(_:)))
        brush.selectedSegment = 0; brush.segmentStyle = .rounded; brush.controlSize = .small
        brush.setAccessibilityLabel("笔刷类型")
        let width = NSSlider(value: 4, minValue: 0.4, maxValue: 18, target: self, action: #selector(changeWidth(_:)))
        width.setAccessibilityLabel("笔画粗细"); width.controlSize = .small
        width.widthAnchor.constraint(equalToConstant: 70).isActive = true
        widthLabel.widthAnchor.constraint(equalToConstant: 26).isActive = true
        inputMode.addItems(withTitles: ["轻触增强", "纯压感", "关闭压感"])
        inputMode.target = self; inputMode.action = #selector(changeInputMode(_:)); inputMode.controlSize = .small
        inputMode.toolTip = "轻触增强：用速度辅助粗细，无需按下；按压时叠加真实压力。纯压感：只响应实际按压。"
        inputMode.widthAnchor.constraint(equalToConstant: 110).isActive = true
        for (button, action) in [(undoButton, #selector(undoStroke)), (redoButton, #selector(redoStroke)), (clearButton, #selector(clearPage)), (exportButton, #selector(exportPNG)), (helpButton, #selector(showHelp)), (desktopButton, #selector(toggleDesktop))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded
            button.controlSize = .small; button.font = .systemFont(ofSize: 12)
        }
        undoButton.title = "↶"; redoButton.title = "↷"
        undoButton.setAccessibilityLabel("撤销笔画"); redoButton.setAccessibilityLabel("重做笔画")
        undoButton.toolTip = "撤销 · Z"
        redoButton.toolTip = "重做 · Y"
        exportButton.toolTip = "导出整幅作品 · S"
        helpButton.toolTip = "快捷键、输入方式与触控信息 · H · 菜单「帮助」中也可查看"
        desktopButton.toolTip = "在当前屏幕上透明标记 · F · 也可从系统菜单栏画笔图标进入"
        let toolbar = NSStackView(views: [startButton, colors, brush, label("笔宽", size: 11), width, widthLabel,
            inputMode, NSView(), desktopButton, undoButton, redoButton, clearButton, exportButton, helpButton])
        toolbar.orientation = .horizontal; toolbar.alignment = .centerY; toolbar.spacing = 6

        let sensitivity = NSSlider(value: 2, minValue: 0.5, maxValue: 5, target: self, action: #selector(changeSensitivity(_:)))
        sensitivity.setAccessibilityLabel("压感灵敏度"); sensitivity.controlSize = .small
        sensitivity.toolTip = "向右调节，较小的按压力度即可产生明显的粗细变化。"
        sensitivity.widthAnchor.constraint(equalToConstant: 88).isActive = true
        let grid = NSButton(checkboxWithTitle: "方格", target: self, action: #selector(toggleGrid(_:)))
        grid.state = .on; grid.controlSize = .small; grid.font = .systemFont(ofSize: 11)
        pressureMeter.isIndeterminate = false; pressureMeter.minValue = 0; pressureMeter.maxValue = 100
        pressureMeter.style = .bar; pressureMeter.controlSize = .small
        pressureMeter.setAccessibilityLabel("原始硬件压力")
        pressureMeter.widthAnchor.constraint(equalToConstant: 58).isActive = true
        pressureLabel.maximumNumberOfLines = 1
        pressureLabel.toolTip = "这里显示真实硬件压力；轻触增强的速度变化不会被当作压力显示。"
        func button(_ title: String, _ action: Selector) -> NSButton {
            let result = NSButton(title: title, target: self, action: action)
            result.bezelStyle = .rounded; result.controlSize = .small; result.font = .systemFont(ofSize: 11)
            return result
        }
        handButton.target = self; handButton.action = #selector(toggleHand)
        handButton.bezelStyle = .rounded; handButton.setButtonType(.toggle); handButton.controlSize = .small
        handButton.font = .systemFont(ofSize: 11)
        handButton.toolTip = "拖动画布；书写时可直接双指移动"
        zoomLabel.alignment = .center; zoomLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        drawingModeControl.addItems(withTitles: ["按住空格画图", "轻触连续书写"])
        drawingModeControl.target = self; drawingModeControl.action = #selector(changeDrawingMode(_:))
        drawingModeControl.controlSize = .small; drawingModeControl.toolTip = "M 切换输入方式 · 两种模式均使用绝对位置"
        eraserButton.target = self; eraserButton.action = #selector(toggleEraser)
        eraserButton.bezelStyle = .rounded; eraserButton.controlSize = .small; eraserButton.setButtonType(.toggle)
        eraserButton.toolTip = "E 切换橡皮擦 · 移动手指即可局部擦除 · Z 撤销"
        let eraserSize = NSSlider(value: 26, minValue: 6, maxValue: 80, target: self, action: #selector(changeEraserSize(_:)))
        eraserSize.controlSize = .small; eraserSize.widthAnchor.constraint(equalToConstant: 48).isActive = true
        eraserSize.setAccessibilityLabel("橡皮擦直径"); eraserSize.toolTip = "橡皮擦大小（屏幕点）"
        let navigationBar = NSStackView(views: [label("灵敏度", size: 11), sensitivity, grid, pressureMeter, pressureLabel,
            NSView(), drawingModeControl, eraserButton, eraserSize, NSView(), handButton, button("−", #selector(zoomOut)), zoomLabel,
            button("+", #selector(zoomIn)), button("原位", #selector(resetView)), button("全部", #selector(fitView))])
        navigationBar.orientation = .horizontal; navigationBar.alignment = .centerY; navigationBar.spacing = 6

        for field in [stateLabel, messageLabel, saveLabel] {
            field.font = .systemFont(ofSize: 11); field.maximumNumberOfLines = 1; field.lineBreakMode = .byTruncatingTail
        }
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [stateLabel, messageLabel, NSView(), saveLabel])
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 10
        for view in [toolbar, navigationBar, canvas, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: view === canvas ? 4 : 8).isActive = true
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: view === canvas ? -4 : -8).isActive = true
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            navigationBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 2),
            navigationBar.heightAnchor.constraint(equalToConstant: 26),
            canvas.topAnchor.constraint(equalTo: navigationBar.bottomAnchor, constant: 4),
            canvas.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -2),
            footer.heightAnchor.constraint(equalToConstant: 18),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4)
        ])
        buildHelpPanel()
    }

    func buildHelpPanel() {
        let content = NSViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 640))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.95, alpha: 1).cgColor
        root.widthAnchor.constraint(equalToConstant: 320).isActive = true
        content.view = root
        let keys = label("Enter            开始 / 结束书写\nEsc              退出书写\n按住空格      画图（默认模式）\nE                  切换橡皮擦\nK                  调色盘\nM                  切换输入方式\nZ                  撤销笔画\nY                  重做笔画\n+（=）/ −    放大 / 缩小\n0                  回到原位\n9                  显示全部笔迹\nS                  导出 PNG\nF                  进入 / 退出桌面标记\nH                  打开 / 收起帮助", size: 12)
        let stack = NSStackView(views: [label("快捷键", size: 16, weight: .semibold), keys,
            label("直接按单键即可，输入文件名时不会触发。\n常用的 Mac 组合键也兼容。", size: 11, color: .secondaryLabelColor),
            label("定位与落笔", size: 13, weight: .semibold),
            label("默认轻触只预览，按住空格画图，松开停笔。连续书写模式中轻触就写，按住空格预览。橡皮擦模式直接移动擦除，再按 E 返回画笔。轻触增强按速度辅助粗细，按压叠加真实压力。", size: 12),
            label("双指移动 / 张合可平移和缩放；两指全部抬起后，继续单指书写。", size: 11, color: .secondaryLabelColor),
            label("桌面标记", size: 13, weight: .semibold),
            label("按 F 进入透明标记；Enter 暂停并操作桌面，点「继续标记」恢复，Esc 退出。也可从系统菜单栏画笔图标进入。", size: 12),
            deviceLabel, countLabel])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        for item in stack.arrangedSubviews {
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            item.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            (item as? NSTextField)?.preferredMaxLayoutWidth = 288
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16)
        ])
        helpPopover.contentViewController = content; helpPopover.behavior = .transient
        helpPopover.animates = false
        helpPopover.contentSize = NSSize(width: 320, height: 640)
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 Zkalan InkDeck", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Zkalan InkDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; main.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (title, selector, key) in [("撤销笔画", #selector(undoStroke), "z"), ("重做笔画", #selector(redoStroke), "y"), ("导出 PNG…", #selector(exportPNG), "s")] {
            let item = edit.addItem(withTitle: title, action: selector, keyEquivalent: key); item.target = self
            item.keyEquivalentModifierMask = []
        }
        edit.addItem(.separator())
        edit.addItem(withTitle: "清空画布…", action: #selector(clearPage), keyEquivalent: "").target = self
        let writingItem = NSMenuItem(); writingItem.title = "书写"; main.addItem(writingItem)
        let writing = NSMenu(title: "书写"); writingItem.submenu = writing
        let toggleItem = writing.addItem(withTitle: "开始 / 结束书写", action: #selector(toggleWriting), keyEquivalent: "\r")
        toggleItem.target = self; toggleItem.keyEquivalentModifierMask = []
        let exitWriting = writing.addItem(withTitle: "退出书写", action: #selector(endWriting), keyEquivalent: "\u{1b}")
        exitWriting.target = self; exitWriting.keyEquivalentModifierMask = []
        let previewItem = NSMenuItem(title: "空格：默认按住画图；连续书写时按住预览", action: nil, keyEquivalent: "")
        previewItem.isEnabled = false; writing.addItem(previewItem)
        writing.addItem(.separator())
        for (title, action, key) in [("切换橡皮擦", #selector(toggleEraser), "e"), ("调色盘…", #selector(showPalette), "k"), ("切换：按住画图 / 连续书写", #selector(toggleDrawingMode), "m")] {
            let item = writing.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self; item.keyEquivalentModifierMask = []
        }
        let desktopItem = writing.addItem(withTitle: "进入 / 退出桌面标记", action: #selector(toggleDesktop), keyEquivalent: "f")
        desktopItem.target = self; desktopItem.keyEquivalentModifierMask = []
        let viewItem = NSMenuItem(); viewItem.title = "视图"; main.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图"); viewItem.submenu = viewMenu
        for (title, selector, key) in [("放大", #selector(zoomIn), "="), ("缩小", #selector(zoomOut), "-"), ("回到原位", #selector(resetView), "0"), ("显示全部", #selector(fitView), "9")] {
            let item = viewMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            item.target = self; item.keyEquivalentModifierMask = []
        }
        let helpItem = NSMenuItem(); helpItem.title = "帮助"; main.addItem(helpItem)
        let help = NSMenu(title: "帮助"); helpItem.submenu = help
        let helpShortcut = help.addItem(withTitle: "快捷键与输入说明…", action: #selector(showHelp), keyEquivalent: "h")
        helpShortcut.target = self; helpShortcut.keyEquivalentModifierMask = []
        NSApp.mainMenu = main
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if palettePanel.isOpen && NSColorPanel.shared.isVisible { return false }
        if desktop.isVisible {
            guard desktop.overlay.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
            if menuItem.action == #selector(undoStroke) { return desktop.canvas.engine.canUndo }
            if menuItem.action == #selector(redoStroke) { return desktop.canvas.engine.canRedo }
            return [#selector(toggleDesktop), #selector(resumeDesktop), #selector(showDrawingWindow), #selector(toggleWriting), #selector(endWriting), #selector(clearPage), #selector(showHelp), #selector(toggleEraser), #selector(showPalette), #selector(toggleDrawingMode)].contains(menuItem.action)
        }
        if [#selector(toggleDesktop), #selector(showDrawingWindow)].contains(menuItem.action) { return window?.attachedSheet == nil && NSApp.modalWindow == nil }
        if menuItem.action == #selector(resumeDesktop) { return false }
        guard window != nil, window.attachedSheet == nil, !(window.firstResponder is NSTextView) else { return false }
        if menuItem.action == #selector(undoStroke) { return canvas.engine.canUndo }
        if menuItem.action == #selector(redoStroke) { return canvas.engine.canRedo }
        return true
    }

    func refresh() {
        startButton.title = canvas.isWriting ? "结束书写  Esc" : "开始书写  ↩"
        stateLabel.stringValue = canvas.isWriting ? (canvas.isNavigating ? "↔  移动与缩放" : canvas.engine.tool == .eraser ? "◯  橡皮擦" : canvas.engine.preview ? "◌  预览落点" : "●  正在书写") : canvas.handTool ? "↔  拖动画布" : "○  准备就绪"
        stateLabel.textColor = canvas.isWriting ? InkColor.green.nsColor : .secondaryLabelColor
        messageLabel.stringValue = canvas.handTool ? "按住并拖动画布 · 点击开始书写后恢复落笔" : canvas.sessionMessage
        if Date() < noticeUntil { messageLabel.stringValue = noticeText }
        deviceLabel.stringValue = canvas.deviceLabel
        undoButton.isEnabled = canvas.engine.canUndo
        redoButton.isEnabled = canvas.engine.canRedo
        clearButton.isEnabled = canvas.engine.canUndo
        exportButton.isEnabled = canvas.engine.canUndo
        padMap.pointer = canvas.rawPointer
        if let point = canvas.rawPointer { coordinateLabel.stringValue = String(format: "X %5.1f%%    Y %5.1f%%", point.x * 100, point.y * 100) }
        else { coordinateLabel.stringValue = "X —    Y —" }
        countLabel.stringValue = "\(canvas.engine.document.strokes.count) 笔画 · \(canvas.receivedFrames) 次输入"
        zoomLabel.stringValue = String(format: "%.0f%%", canvas.viewport.zoom * 100)
        pressureMeter.doubleValue = canvas.currentPressure * 100
        pressureLabel.stringValue = String(format: "原始力度 %.0f%%", canvas.currentPressure * 100)
        handButton.state = canvas.handTool ? .on : .off
        colors.selected = canvas.engine.color
        eraserButton.state = canvas.engine.tool == .eraser ? .on : .off
        drawingModeControl.selectItem(at: canvas.drawingMode == .holdToDraw ? 0 : 1)
    }
    @objc func toggleWriting() {
        if desktop.isVisible { desktop.toggleInteraction(); return }
        if canvas.isWriting { canvas.stopWriting() } else { canvas.startWriting() }
    }
    func selectColor(_ color: InkColor) {
        canvas.engine.finish(); canvas.engine.color = color; canvas.changed()
    }
    @objc func showPalette() {
        if desktop.isVisible { desktop.showPalette(); return }
        canvas.stopWriting()
        palettePanel.show(color: canvas.engine.color, preferences: preferences, onSelect: { [weak self] in self?.selectColor($0) }, onDone: { [weak self] in
            guard let self else { return }
            self.window.makeKeyAndOrderFront(nil); self.canvas.startWriting()
        })
    }
    @objc func toggleEraser() {
        if desktop.isVisible { desktop.toggleEraser(); return }
        canvas.toggleEraser()
        if !canvas.isWriting { canvas.startWriting() }
    }
    @objc func changeEraserSize(_ sender: NSSlider) { canvas.engine.finish(); canvas.eraserDiameter = sender.doubleValue; canvas.changed() }
    @objc func changeDrawingMode(_ sender: NSPopUpButton) {
        preferences.mode = sender.indexOfSelectedItem == 0 ? .holdToDraw : .touchToDraw
        canvas.drawingMode = preferences.mode; desktop.canvas.drawingMode = preferences.mode
    }
    @objc func toggleDrawingMode() {
        preferences.mode = preferences.mode == .holdToDraw ? .touchToDraw : .holdToDraw
        canvas.drawingMode = preferences.mode; desktop.canvas.drawingMode = preferences.mode
    }
    @objc func changeWidth(_ sender: NSSlider) { canvas.engine.finish(); canvas.engine.width = sender.doubleValue / 1000; widthLabel.stringValue = String(format: "%.1f", sender.doubleValue) }
    @objc func changeBrush(_ sender: NSSegmentedControl) { canvas.engine.finish(); canvas.engine.brush = sender.selectedSegment == 0 ? .pen : .brush }
    @objc func changeInputMode(_ sender: NSPopUpButton) {
        canvas.engine.finish()
        canvas.engine.pressureEnabled = sender.indexOfSelectedItem != 2
        canvas.engine.lightTouchAssistance = sender.indexOfSelectedItem == 0
        showNotice(sender.indexOfSelectedItem == 0 ? "轻触增强：速度辅助粗细，按压叠加真实压力" : sender.titleOfSelectedItem ?? "")
    }
    @objc func changeSensitivity(_ sender: NSSlider) { canvas.engine.finish(); canvas.engine.pressureSensitivity = sender.doubleValue }
    @objc func zoomIn() { canvas.zoom(by: 1.25) }
    @objc func zoomOut() { canvas.zoom(by: 0.8) }
    @objc func resetView() { canvas.resetViewport() }
    @objc func fitView() { canvas.fitContent() }
    @objc func toggleHand() { canvas.stopWriting(); canvas.handTool.toggle() }
    @objc func toggleGrid(_ sender: NSButton) { canvas.showGrid = sender.state == .on }
    @objc func undoStroke() {
        if desktop.isVisible { desktop.undo(); return }
        let hadStroke = canvas.engine.canUndo
        canvas.engine.undo(); canvas.changed(); scheduleSave()
        showNotice(hadStroke ? "已撤销 · 剩余 \(canvas.engine.document.strokes.count) 笔" : "没有可撤销的笔画")
    }
    @objc func redoStroke() {
        if desktop.isVisible { desktop.redo(); return }
        let hadStroke = canvas.engine.canRedo
        canvas.engine.redo(); canvas.changed(); scheduleSave()
        showNotice(hadStroke ? "已重做 · 共 \(canvas.engine.document.strokes.count) 笔" : "没有可重做的笔画")
    }
    func showNotice(_ text: String) {
        noticeText = text; noticeUntil = Date().addingTimeInterval(1.8); refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in self?.refresh() }
    }
    @objc func endWriting() { if desktop.isVisible { desktop.finish() } else { canvas.stopWriting() } }
    @objc func showHelp() {
        if desktop.isVisible { desktop.showHelp(); return }
        canvas.stopWriting()
        if helpPopover.isShown { helpPopover.close() }
        else { helpPopover.show(relativeTo: helpButton.bounds, of: helpButton, preferredEdge: .minY) }
    }
    @objc func clearPage() {
        if desktop.isVisible { desktop.clearMarks(); return }
        canvas.stopWriting()
        guard canvas.engine.canUndo else { return }
        let alert = NSAlert()
        alert.messageText = "清空这张纸？"
        alert.informativeText = "当前草稿将被清空。需要保留的话，请先导出 PNG。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清空")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            self.canvas.engine.clear(); self.canvas.changed(); self.saveDraft()
        }
    }
    @objc func exportPNG() {
        guard !desktop.isVisible else { return }
        canvas.stopWriting()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "触控板手写.png"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let self, let url = panel.url else { return }
            do {
                guard let png = self.canvas.pngData() else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: url, options: .atomic)
                self.saveLabel.stringValue = "已导出 \(url.lastPathComponent)"
            } catch { self.showError("导出失败", error) }
        }
    }
    @objc func showAbout() {
        canvas.stopWriting()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Zkalan InkDeck", .applicationVersion: "0.5 · 示意图与橡皮擦", .credits: NSAttributedString(string: "桌面标记 · 轻触增强 · 单键操作\n画板与桌面笔迹分别保存在本机。")])
    }
    func scheduleSave() {
        guard !smokeMode else { return }
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in self?.saveDraft() }
    }
    func saveDraft() {
        guard !smokeMode else { return }
        saveTimer?.invalidate(); saveTimer = nil
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(canvas.engine.document)
            try data.write(to: dataURL, options: .atomic)
            saveLabel.stringValue = "草稿已保存到本机"
            pendingSaveError = nil
        } catch {
            pendingSaveError = error.localizedDescription
            saveLabel.stringValue = "草稿保存失败，请导出 PNG"
        }
    }
    func restore() {
        let legacyURL = dataURL.deletingLastPathComponent().appendingPathComponent("draft.json")
        let sourceURL = FileManager.default.fileExists(atPath: dataURL.path) ? dataURL : legacyURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        do {
            var doc = try JSONDecoder().decode(InkDocument.self, from: Data(contentsOf: sourceURL))
            guard doc.isValid else { throw CocoaError(.fileReadCorruptFile) }
            doc.formatVersion = 3
            for index in doc.strokes.indices where doc.strokes[index].id == nil { doc.strokes[index].id = UUID() }
            canvas.engine.document = doc
            if sourceURL == legacyURL { saveLabel.stringValue = "已读取旧版草稿，原文件保留" }
        } catch {
            // Preserve unreadable data before any future autosave.
            let backup = dataURL.deletingLastPathComponent().appendingPathComponent("draft-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: sourceURL, to: backup)
            saveLabel.stringValue = "旧草稿无法读取，已保留备份"
        }
    }
    func showError(_ title: String, _ error: Error) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }
    func applicationWillResignActive(_ notification: Notification) { canvas.stopWriting(); desktop.pause() }
    func windowDidResignKey(_ notification: Notification) { canvas.stopWriting() }
    func windowWillMiniaturize(_ notification: Notification) { canvas.stopWriting() }
    func windowWillStartLiveResize(_ notification: Notification) { canvas.stopWriting() }
    func windowWillMove(_ notification: Notification) { canvas.stopWriting() }
    func windowWillClose(_ notification: Notification) { canvas.stopWriting(); saveDraft() }
    // The menu bar entry remains available when the drawing window is hidden or closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        palettePanel.close(); canvas.stopWriting(); saveDraft(); desktop.finish(restoreMainWindow: false)
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }

    func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "触控板桌面标记")
        statusItem?.button?.toolTip = "触控板手写 · 桌面标记"
        let menu = NSMenu()
        for (title, action) in [("开始 / 退出桌面标记", #selector(toggleDesktop)), ("继续标记", #selector(resumeDesktop)), ("返回画板", #selector(showDrawingWindow))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Zkalan InkDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem?.menu = menu
    }
    @objc func toggleDesktop() {
        if desktop.isVisible { desktop.finish(); return }
        guard window.attachedSheet == nil, NSApp.modalWindow == nil,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? window.screen ?? NSScreen.main else { return }
        canvas.stopWriting(); saveDraft(); helpPopover.close()
        window.orderOut(nil)
        desktop.begin(on: screen, settings: canvas.engine, previous: smokeMode ? nil : lastExternalApplication)
    }
    @objc func resumeDesktop() { if desktop.isVisible { desktop.resume() } }
    @objc func showDrawingWindow() {
        palettePanel.close(); canvas.drawingMode = preferences.mode
        if desktop.isVisible { desktop.finish(restoreMainWindow: false) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas)
    }

    func runSmokeTest() {
        let output = ProcessInfo.processInfo.environment["TRACKPAD_INK_ARTIFACTS"] ?? NSTemporaryDirectory()
        var results: [String: Any] = [:]
        canvas.drawingMode = .touchToDraw; preferences.mode = .touchToDraw
        // LaunchServices activation is asynchronous; wait for this test window before capture.
        let activationDeadline = Date().addingTimeInterval(3)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        while (!NSApp.isActive || !window.isKeyWindow) && Date() < activationDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        results["testWindowHasForeground"] = NSApp.isActive && window.isKeyWindow
        let cursorBefore = CGEvent(source: nil)?.location
        results["enteredWritingMode"] = canvas.startWriting()
        results["cursorHideAccepted"] = canvas.cursorHidden
        results["cursorDisassociationAccepted"] = canvas.cursorDetached
        canvas.stopWriting()
        results["exitedWritingMode"] = !canvas.isWriting
        results["cursorRestoreAccepted"] = canvas.lastCursorRestoreSucceeded
        results["cursorHideBalanced"] = !canvas.cursorHidden
        if let before = cursorBefore, let after = CGEvent(source: nil)?.location {
            results["cursorRestored"] = hypot(before.x - after.x, before.y - after.y) < 2
        }
        func finger(_ id: Int, _ x: Double, _ y: Double) -> FingerSample { FingerSample(id: id, point: InkPoint(x, y)) }
        canvas.processTouchFrame([finger(1, 0.3, 0.4)], timestamp: 1)
        canvas.processTouchFrame([finger(1, 0.3, 0.4), finger(2, 0.7, 0.4)], timestamp: 1.03)
        canvas.processTouchFrame([finger(1, 0.2, 0.6), finger(2, 0.9, 0.6)], timestamp: 1.1)
        results["pinchAndPanTogether"] = abs(canvas.viewport.zoom - 1.75) < 1e-8 && canvas.viewport.center.y < 0.5
        results["navigationLeavesNoInk"] = canvas.engine.document.strokes.isEmpty
        canvas.processTouchFrame([finger(1, 0.2, 0.6)], timestamp: 1.2)
        results["remainingFingerDoesNotDraw"] = canvas.engine.document.strokes.isEmpty
        canvas.processTouchFrame([], timestamp: 1.3)
        let expected = canvas.viewport.worldPoint(at: InkPoint(0.7, 0.3))
        canvas.processTouchFrame([finger(3, 0.7, 0.3)], timestamp: 1.4)
        results["newStrokeUsesTransformedCoordinates"] = canvas.engine.document.strokes.last?.points.first == expected
        canvas.processTouchFrame([], timestamp: 1.5)
        func key(_ code: UInt16, _ text: String, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        let undoItem = NSApp.mainMenu!.items.flatMap { $0.submenu?.items ?? [] }.first { $0.action == #selector(undoStroke) }!
        let singleKeys: Set<String> = ["z", "y", "s", "\r", "\u{1b}", "=", "-", "0", "9", "h", "f", "e", "k", "m"]
        let shortcutItems = NSApp.mainMenu!.items.flatMap { $0.submenu?.items ?? [] }.filter { singleKeys.contains($0.keyEquivalent) && ($0.target as AnyObject?) === self }
        results["shortcutMenuEntries"] = shortcutItems.map { $0.title + ":" + $0.keyEquivalent }
        results["shortcutsDiscoverableInMenus"] = shortcutItems.count == singleKeys.count && shortcutItems.allSatisfy { $0.keyEquivalentModifierMask.isEmpty }
        results["plainZUndoOutsideWriting"] = handleKeyboard(key(6, "z")) == nil && canvas.engine.document.strokes.isEmpty
        results["plainYRedoOutsideWriting"] = handleKeyboard(key(16, "y")) == nil && canvas.engine.document.strokes.count == 1
        NSApp.sendEvent(key(6, "z"))
        results["nativeEventDispatchUndoOnce"] = canvas.engine.document.strokes.isEmpty
        _ = handleKeyboard(key(16, "y"))
        results["commandZCompatibility"] = handleKeyboard(key(6, "z", flags: .command)) == nil && canvas.engine.document.strokes.isEmpty
        _ = handleKeyboard(key(6, "z", flags: [.command, .shift]))
        results["commandShiftZCompatibility"] = canvas.engine.document.strokes.count == 1
        results["menuKeyEquivalentUndo"] = NSApp.mainMenu!.performKeyEquivalent(with: key(6, "z")) && canvas.engine.document.strokes.isEmpty
        _ = handleKeyboard(key(16, "y"))
        results["commandHPassesThrough"] = handleKeyboard(key(4, "h", flags: .command)) != nil
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 180, height: 24))
        window.contentView!.addSubview(field); window.makeFirstResponder(field)
        results["textEntryDoesNotUndo"] = window.firstResponder is NSTextView && handleKeyboard(key(6, "z")) != nil
            && !validateMenuItem(undoItem) && canvas.engine.document.strokes.count == 1
        window.makeFirstResponder(canvas); field.removeFromSuperview()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        window.beginSheet(sheet)
        results["sheetDoesNotTriggerShortcuts"] = handleKeyboard(key(6, "z")) != nil && !validateMenuItem(undoItem)
            && canvas.engine.document.strokes.count == 1
        window.endSheet(sheet); sheet.orderOut(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas)
        _ = handleKeyboard(key(36, "\r"))
        results["enterStartsWriting"] = canvas.isWriting
        _ = handleKeyboard(key(49, " "))
        results["spacePreview"] = canvas.engine.preview
        _ = handleKeyboard(key(49, " ", type: .keyUp))
        results["spaceReleaseResumesInk"] = !canvas.engine.preview
        _ = handleKeyboard(key(6, "z")); _ = handleKeyboard(key(16, "y"))
        results["plainUndoRedoWhileWriting"] = canvas.isWriting && canvas.engine.document.strokes.count == 1
        _ = handleKeyboard(key(36, "\r"))
        results["enterEndsWritingAndRestoresCursor"] = !canvas.isWriting && !canvas.cursorHidden && !canvas.cursorDetached
        canvas.resetViewport(); _ = handleKeyboard(key(24, "="))
        results["singleKeyZoom"] = abs(canvas.viewport.zoom - 1.25) < 1e-8
        _ = handleKeyboard(key(29, "0"))
        results["singleKeyReset"] = canvas.viewport.zoom == 1
        canvas.engine.clear(); canvas.resetViewport()
        // Synthetic model input checks rendering/export, not physical touch capture.
        canvas.engine.pressureEnabled = false
        for (id, x, y) in [(1, 0.18, 0.23), (2, 0.58, 0.68)] {
            canvas.engine.frame([FingerSample(id: id, point: InkPoint(x, y))])
            canvas.engine.frame([FingerSample(id: id, point: InkPoint(x + 0.23, y))])
            canvas.engine.frame([])
        }
        canvas.engine.pressureEnabled = true
        canvas.engine.brush = .brush
        canvas.engine.width = 0.010
        for i in 0...120 {
            let t = Double(i) / 120
            canvas.engine.frame([FingerSample(id: 3, point: InkPoint(0.14 + t * 0.70, 0.43 + sin(t * 2 * .pi) * 0.09),
                pressure: pow(sin(t * .pi), 2), timestamp: 10 + t)])
        }
        canvas.engine.frame([])
        canvas.engine.color = .blue
        canvas.engine.brush = .pen
        canvas.engine.width = 0.012
        for i in 0...60 {
            let t = Double(i) / 60
            canvas.engine.frame([FingerSample(id: 4, point: InkPoint(1.04 + t * 0.30, 0.27 + t * 0.46), pressure: t, timestamp: 12 + t)])
        }
        canvas.engine.frame([])
        canvas.fitContent()
        canvas.changed()
        results["separateStrokes"] = canvas.engine.document.strokes.count == 4
        results["offscreenContentIncluded"] = canvas.engine.document.contentBounds.maxX > 1.34
        let brushStroke = canvas.engine.document.strokes[2]
        let brushPath = InkRenderer.path(for: brushStroke, aspect: canvas.engine.document.aspect, active: false)
        results["brushPathHasArea"] = !brushPath.isEmpty && brushPath.boundingBoxOfPath.height > 0.05
        let linePath = InkRenderer.path(for: canvas.engine.document.strokes[0], aspect: canvas.engine.document.aspect, active: false)
        results["solidLineHasNoHoles"] = (1..<300).allSatisfy { i in
            linePath.contains(CGPoint(x: 0.18 + Double(i) / 300 * 0.23, y: 0.23 / canvas.engine.document.aspect))
        }
        results["brushCenterlineHasNoHoles"] = brushStroke.points.dropFirst().dropLast().allSatisfy { point in
            brushPath.contains(CGPoint(x: point.x, y: point.y / canvas.engine.document.aspect))
        }
        if let png = canvas.pngData() {
            try? png.write(to: URL(fileURLWithPath: output).appendingPathComponent("export-smoke.png"))
            results["pngExported"] = true
        }
        window.contentView?.layoutSubtreeIfNeeded()
        if let root = window.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("window-smoke.png"))
        }
        canvas.viewport = InkViewport(zoom: 2.5, center: InkPoint(0.49, 0.43))
        canvas.changed()
        if let root = window.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("window-detail.png"))
        }
        if let root = window.contentView {
            let ratio = canvas.paperRect.width * canvas.paperRect.height / (root.bounds.width * root.bounds.height)
            results["canvasContentAreaRatio"] = ratio
            results["compactCanvasOver84Percent"] = ratio > 0.84
            results["canvasSizePoints"] = [canvas.paperRect.width, canvas.paperRect.height]
            results["windowContentSizePoints"] = [root.bounds.width, root.bounds.height]
        }
        noticeUntil = .distantPast; refresh()
        _ = handleKeyboard(key(4, "h"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        results["singleHOpensHelp"] = helpPopover.isShown
        if let helpRoot = helpPopover.contentViewController?.view {
            helpRoot.layoutSubtreeIfNeeded()
            let descendants = helpRoot.subviews.flatMap { $0.subviews }
            results["helpContentFits"] = helpRoot.bounds.width <= 321 && descendants.allSatisfy { helpRoot.bounds.insetBy(dx: 0, dy: -1).contains($0.convert($0.bounds, to: helpRoot)) }
            if let bitmap = helpRoot.bitmapImageRepForCachingDisplay(in: helpRoot.bounds) {
                helpRoot.cacheDisplay(in: helpRoot.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("help-smoke.png"))
            }
        }
        _ = handleKeyboard(key(4, "h"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        results["singleHClosesHelp"] = !helpPopover.isShown
        canvas.engine.clear(); canvas.resetViewport(); canvas.engine.color = .graphite; canvas.engine.brush = .pen
        canvas.engine.width = 0.008; canvas.engine.lightTouchAssistance = true
        for row in 0..<3 {
            for i in 0...180 {
                let t = Double(i) / 180
                let x = 0.10 + 0.80 * t
                // At zero hardware pressure, alternating slow and fast movement changes width.
                let time = 20 + Double(row) * 5 + t * 2 + sin(t * 4 * .pi) * 0.14
                canvas.engine.frame([FingerSample(id: 20 + row, point: InkPoint(x, 0.24 + Double(row) * 0.25),
                    pressure: [0, 0.02, 0.10][row], timestamp: time)])
            }
            canvas.engine.frame([])
        }
        let factors = canvas.engine.document.strokes.map { $0.widthFactors! }
        results["zeroPressureStrokeHasWidthVariation"] = factors[0].max()! - factors[0].min()! > 0.2
        results["lightPressureStrokesGrow"] = zip(factors[0], factors[1]).allSatisfy { $0 < $1 } && zip(factors[1], factors[2]).allSatisfy { $0 < $1 }
        canvas.changed()
        if let root = window.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("light-touch-smoke.png"))
        }
        window.setContentSize(NSSize(width: 1000, height: 612)); window.contentView?.layoutSubtreeIfNeeded()
        if let root = window.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("window-minimum.png"))
        }
        let comparisonEncoder = JSONEncoder(); comparisonEncoder.outputFormatting = .sortedKeys
        let boardBeforeDesktop = try! comparisonEncoder.encode(canvas.engine.document)
        _ = handleKeyboard(key(3, "f"))
        results["singleFEntersDesktop"] = desktop.isVisible && !window.isVisible
        results.merge(desktop.runSmokeChecks(output: output)) { _, value in value }
        results["desktopExitRestoresBoardWindow"] = window.isVisible && !desktop.isVisible
        results["desktopDoesNotChangeBoard"] = boardBeforeDesktop == (try! comparisonEncoder.encode(canvas.engine.document))
        results["desktopMenuBarEntryExists"] = statusItem?.menu?.items.contains { $0.action == #selector(toggleDesktop) } == true
        results.merge(runFeatureChecks(output: output)) { _, value in value }
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try? data.write(to: URL(fileURLWithPath: output).appendingPathComponent("smoke-results.json"))
        print(String(data: data, encoding: .utf8)!)
        if results.values.contains(where: { ($0 as? Bool) == false }) {
            canvas.stopWriting(); desktop.finish(restoreMainWindow: false)
            exit(EXIT_FAILURE)
        }
        NSApp.terminate(nil)
    }
}
