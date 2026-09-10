import AppKit

private final class MarkingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class MarkingToolbar: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DesktopOverlay: NSObject, NSWindowDelegate {
    let canvas = CanvasView(frame: .zero)
    private(set) var overlay: NSPanel!
    private(set) var toolbar: NSPanel!
    private(set) var isVisible = false
    var onExit: (() -> Void)?
    var onChange: (() -> Void)?
    private let smokeMode: Bool
    private var screenID = ""
    private var documents: [String: InkDocument] = [:]
    private var saveTimer: Timer?
    private var previousApplication: NSRunningApplication?
    private let modeButton = NSButton(title: "操作桌面 ↩", target: nil, action: nil)
    private let undoButton = NSButton(title: "撤销 Z", target: nil, action: nil)
    private let redoButton = NSButton(title: "重做 Y", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "")
    private let help = NSPopover()
    private var saveError: String?
    var dataURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrackpadInk/desktop-draft.json")
    }

    init(smokeMode: Bool) {
        self.smokeMode = smokeMode
        super.init()
        canvas.desktopSurface = true; canvas.showGrid = false
        canvas.engine.color = .coral; canvas.engine.width = 0.004
        canvas.setAccessibilityLabel("桌面透明标记画布")
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onDocumentChange = { [weak self] in self?.scheduleSave() }
        buildWindows()
        if !smokeMode { restore() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func buildWindows() {
        overlay = MarkingPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.title = "桌面标记"
        overlay.isOpaque = false
        // A visually imperceptible backing keeps transparent areas eligible for touch routing.
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        overlay.hasShadow = false; overlay.isReleasedWhenClosed = false
        overlay.level = .floating; overlay.hidesOnDeactivate = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        overlay.delegate = self; overlay.contentView = canvas
        toolbar = MarkingToolbar(contentRect: NSRect(x: 0, y: 0, width: 760, height: 72),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toolbar.title = "桌面标记工具"
        toolbar.isOpaque = false; toolbar.backgroundColor = .clear
        toolbar.hasShadow = true; toolbar.hidesOnDeactivate = false; toolbar.isReleasedWhenClosed = false
        toolbar.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        toolbar.collectionBehavior = overlay.collectionBehavior
        toolbar.isMovableByWindowBackground = true
        let root = NSView(); root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.95, alpha: 0.98).cgColor
        root.layer?.cornerRadius = 10; toolbar.contentView = root
        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded; b.controlSize = .small; b.font = .systemFont(ofSize: 12)
            return b
        }
        for (b, action) in [(modeButton, #selector(toggleInteraction)), (undoButton, #selector(undo)), (redoButton, #selector(redo))] {
            b.target = self; b.action = action; b.bezelStyle = .rounded; b.controlSize = .small
        }
        modeButton.bezelColor = InkColor.green.nsColor
        let colors = NSSegmentedControl(labels: ["红", "蓝", "绿", "黑"], trackingMode: .selectOne, target: self, action: #selector(changeColor(_:)))
        colors.selectedSegment = 0; colors.controlSize = .small
        let brush = NSSegmentedControl(labels: ["笔", "毛笔"], trackingMode: .selectOne, target: self, action: #selector(changeBrush(_:)))
        brush.selectedSegment = 0; brush.controlSize = .small
        let width = NSSlider(value: 4, minValue: 1, maxValue: 14, target: self, action: #selector(changeWidth(_:)))
        width.controlSize = .small; width.widthAnchor.constraint(equalToConstant: 55).isActive = true
        width.setAccessibilityLabel("桌面标记笔宽")
        let row = NSStackView(views: [modeButton, colors, brush, width, undoButton, redoButton,
            button("清空 C", #selector(clearMarks)), button("换屏", #selector(nextScreen)), button("帮助 H", #selector(showHelp)), button("退出 Esc", #selector(exitMarking))])
        row.spacing = 5; row.alignment = .centerY
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail; hint.maximumNumberOfLines = 1
        let stack = NSStackView(views: [row, hint]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 9),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -7)
        ])
        let controller = NSViewController()
        let text = NSTextField(wrappingLabelWithString: "桌面标记 · 单键操作\n\nEnter　暂停标记，操作下面的软件\nZ / Y　撤销 / 重做\nC　清空标记（会先确认）\n按住空格　只预览落点\nF / Esc　退出桌面标记\nH　打开 / 收起本说明\n\n暂停后点「继续标记」恢复；工具条可拖动。\n使用菜单栏的画笔图标，可从其他应用进入。\n触控板四角对应当前屏幕四角；「换屏」切换显示器。桌面模式固定视图，双指暂停落笔。\n\n标记停留在屏幕位置，翻页或移动窗口后可清空重画。屏幕共享时请选择整个屏幕。")
        text.font = .systemFont(ofSize: 12); text.preferredMaxLayoutWidth = 288
        let helpRoot = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 350))
        helpRoot.wantsLayer = true; helpRoot.layer?.backgroundColor = root.layer?.backgroundColor
        helpRoot.widthAnchor.constraint(equalToConstant: 320).isActive = true
        text.translatesAutoresizingMaskIntoConstraints = false; helpRoot.addSubview(text)
        NSLayoutConstraint.activate([text.topAnchor.constraint(equalTo: helpRoot.topAnchor, constant: 16), text.leadingAnchor.constraint(equalTo: helpRoot.leadingAnchor, constant: 16), text.trailingAnchor.constraint(equalTo: helpRoot.trailingAnchor, constant: -16), text.bottomAnchor.constraint(lessThanOrEqualTo: helpRoot.bottomAnchor, constant: -16)])
        controller.view = helpRoot; help.contentViewController = controller
        help.behavior = .transient; help.animates = false; help.contentSize = helpRoot.frame.size
    }

    func begin(on screen: NSScreen, settings: InkEngine, previous: NSRunningApplication?) {
        guard !isVisible else { resume(); return }
        previousApplication = previous
        canvas.engine.pressureEnabled = settings.pressureEnabled
        canvas.engine.lightTouchAssistance = settings.lightTouchAssistance
        canvas.engine.pressureSensitivity = settings.pressureSensitivity
        isVisible = true
        selectScreen(screen)
        resume()
    }

    private func identifier(_ screen: NSScreen) -> String {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() { return CFUUIDCreateString(nil, uuid) as String }
        return "screen-\(number)"
    }

    private func selectScreen(_ screen: NSScreen) {
        canvas.stopWriting()
        if !screenID.isEmpty { documents[screenID] = canvas.engine.document }
        screenID = identifier(screen)
        canvas.engine.clear()
        canvas.engine.document = documents[screenID] ?? InkDocument()
        canvas.engine.document.aspect = screen.frame.width / screen.frame.height
        canvas.viewport = InkViewport()
        overlay.setFrame(screen.frame, display: true)
        let safe = screen.visibleFrame
        toolbar.setFrameOrigin(NSPoint(x: safe.midX - toolbar.frame.width / 2, y: safe.maxY - toolbar.frame.height - 12))
        canvas.changed()
    }

    @objc func nextScreen() {
        guard isVisible, NSScreen.screens.count > 1 else { return }
        let screens = NSScreen.screens
        let index = screens.firstIndex { identifier($0) == screenID } ?? 0
        selectScreen(screens[(index + 1) % screens.count]); resume()
    }

    func resume() {
        guard isVisible, overlay.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        help.close()
        NSApp.activate(ignoringOtherApps: true)
        overlay.ignoresMouseEvents = false
        overlay.makeKeyAndOrderFront(nil); overlay.makeFirstResponder(canvas)
        toolbar.orderFrontRegardless()
        if !canvas.startWriting() {
            // Activation can finish on the next turn when invoked from the menu bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.isVisible, !self.overlay.ignoresMouseEvents else { return }
                if !self.canvas.isWriting && !self.canvas.startWriting() { self.pause() }
            }
        }
        refresh()
    }

    func pause() {
        guard isVisible else { return }
        canvas.stopWriting()
        overlay.ignoresMouseEvents = true
        refresh(); save()
    }

    @objc func toggleInteraction() {
        if canvas.isWriting {
            pause()
            if let previousApplication, !previousApplication.isTerminated { previousApplication.activate(options: []) }
        } else { resume() }
    }

    @objc func exitMarking() { finish() }
    func finish(restoreMainWindow: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        canvas.stopWriting(); help.close(); save()
        overlay.ignoresMouseEvents = true; overlay.orderOut(nil); toolbar.orderOut(nil)
        if restoreMainWindow { onExit?() }
        onChange?()
    }

    func handleKeyboard(_ event: NSEvent) -> NSEvent? {
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if help.isShown, event.type == .keyDown, plain, [4, 53].contains(event.keyCode) { help.close(); return nil }
        guard isVisible, (event.window === overlay || (event.window == nil && overlay.isKeyWindow)),
              overlay.attachedSheet == nil, NSApp.modalWindow == nil, !(overlay.firstResponder is NSTextView),
              !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) else { return event }
        if event.keyCode == 49 && canvas.isWriting && plain { canvas.setPreview(event.type == .keyDown); return nil }
        guard event.type == .keyDown else { return event }
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 6: event.modifierFlags.contains(.shift) ? redo() : undo()
            default: return event
            }
            return nil
        }
        if event.isARepeat && [36, 76, 3, 53, 8, 4].contains(event.keyCode) { return nil }
        switch event.keyCode {
        case 36, 76: toggleInteraction()
        case 53, 3: finish()
        case 6: event.modifierFlags.contains(.shift) ? redo() : undo()
        case 16: redo()
        case 8: clearMarks()
        case 4: showHelp()
        default: return event
        }
        return nil
    }

    @objc func undo() { canvas.engine.undo(); canvas.changed(); scheduleSave() }
    @objc func redo() { canvas.engine.redo(); canvas.changed(); scheduleSave() }
    @objc private func changeColor(_ sender: NSSegmentedControl) {
        canvas.engine.finish(); canvas.engine.color = [InkColor.coral, .blue, .green, .graphite][sender.selectedSegment]
    }
    @objc private func changeBrush(_ sender: NSSegmentedControl) { canvas.engine.finish(); canvas.engine.brush = sender.selectedSegment == 0 ? .pen : .brush }
    @objc private func changeWidth(_ sender: NSSlider) { canvas.engine.finish(); canvas.engine.width = sender.doubleValue / 1000 }
    @objc func clearMarks() {
        guard canvas.engine.canUndo, NSApp.modalWindow == nil else { return }
        let wasWriting = canvas.isWriting
        pause()
        let alert = NSAlert(); alert.messageText = "清空这块屏幕上的标记？"
        alert.informativeText = "普通画板中的作品会保留。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清空")
        alert.window.level = NSWindow.Level(rawValue: toolbar.level.rawValue + 1)
        if alert.runModal() == .alertSecondButtonReturn { canvas.engine.clear(); canvas.changed(); save() }
        if wasWriting { resume() }
    }
    @objc func showHelp() {
        if help.isShown { help.close(); return }
        pause()
        help.show(relativeTo: modeButton.bounds, of: modeButton, preferredEdge: .minY)
    }

    private func refresh() {
        modeButton.title = canvas.isWriting ? "操作桌面 ↩" : "继续标记"
        undoButton.isEnabled = canvas.engine.canUndo; redoButton.isEnabled = canvas.engine.canRedo
        hint.stringValue = saveError ?? (canvas.isWriting
            ? "● 正在标记 · Enter 操作桌面 · 空格预览 · F / Esc 退出 · \(canvas.engine.document.strokes.count) 笔"
            : "○ 操作桌面 · 标记保留可见，点击和滚动穿过标记层 · 点「继续标记」恢复 · 工具条可拖动")
        onChange?()
    }

    private func scheduleSave() {
        guard !smokeMode else { return }
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in self?.save() }
    }
    func save() {
        guard !screenID.isEmpty else { return }
        documents[screenID] = canvas.engine.document
        guard !smokeMode else { return }
        saveTimer?.invalidate(); saveTimer = nil
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(documents).write(to: dataURL, options: .atomic)
            saveError = nil
        } catch { saveError = "桌面标记保存失败：\(error.localizedDescription)" }
    }
    private func restore() {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return }
        do {
            let value = try JSONDecoder().decode([String: InkDocument].self, from: Data(contentsOf: dataURL))
            guard value.values.allSatisfy({ $0.isValid }) else { throw CocoaError(.fileReadCorruptFile) }
            documents = value
        } catch {
            let backup = dataURL.deletingLastPathComponent().appendingPathComponent("desktop-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: dataURL, to: backup)
            saveError = "旧桌面标记无法读取，已保留备份"
        }
    }
    func windowDidResignKey(_ notification: Notification) { if isVisible { pause() } }
    @objc private func screenConfigurationChanged() { if isVisible { finish() } }

    // Exercise actual overlay windows with synthetic ink; never captures desktop pixels.
    func runSmokeChecks(output: String) -> [String: Any] {
        var checks: [String: Any] = [:]
        guard isVisible else { return ["desktopEntered": false] }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        checks["desktopCapturesWriting"] = canvas.isWriting && canvas.cursorDetached && canvas.cursorHidden
        checks["desktopTransparentWindow"] = !overlay.isOpaque && overlay.backgroundColor.alphaComponent < 0.02 && !overlay.hasShadow
        checks["desktopCoversWholeScreen"] = NSScreen.screens.contains { $0.frame == overlay.frame } && canvas.paperRect == canvas.bounds
        checks["desktopAboveNormalWindows"] = overlay.level.rawValue > NSWindow.Level.normal.rawValue
        checks["desktopAllSpacesConfigured"] = overlay.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications])
        checks["desktopTouchTargetAtScreenCenter"] = NSWindow.windowNumber(at: NSPoint(x: overlay.frame.midX, y: overlay.frame.midY), belowWindowWithWindowNumber: 0) == overlay.windowNumber
        checks["desktopCenterWindowNumber"] = NSWindow.windowNumber(at: NSPoint(x: overlay.frame.midX, y: overlay.frame.midY), belowWindowWithWindowNumber: 0)
        checks["desktopWindowNumber"] = overlay.windowNumber
        let documentAspect = canvas.engine.document.aspect
        func finger(_ id: Int, _ x: Double, _ y: Double, _ timestamp: Double) -> FingerSample {
            FingerSample(id: id, point: InkPoint(x, y), pressure: 0.02, timestamp: timestamp, inputPoint: InkPoint(x, y))
        }
        canvas.processTouchFrame([finger(90, 0.2, 0.2, 30)], timestamp: 30)
        canvas.processTouchFrame([finger(90, 0.2, 0.2, 30.03), finger(91, 0.6, 0.4, 30.03)], timestamp: 30.03)
        canvas.processTouchFrame([finger(90, 0.1, 0.4, 30.1), finger(91, 0.9, 0.7, 30.1)], timestamp: 30.1)
        checks["desktopTwoFingersDoNotMoveMarks"] = canvas.viewport.zoom == 1 && canvas.viewport.center == InkPoint(0.5, 0.5) && canvas.engine.document.strokes.isEmpty
        canvas.processTouchFrame([finger(90, 0.1, 0.4, 30.2)], timestamp: 30.2)
        checks["desktopRemainingFingerDoesNotDraw"] = canvas.engine.document.strokes.isEmpty
        canvas.processTouchFrame([], timestamp: 30.3)
        for i in 0...120 {
            let t = Double(i) / 120, a = t * 2 * Double.pi
            canvas.processTouchFrame([finger(92, 0.34 + cos(a) * 0.19, 0.48 + sin(a) * 0.12, 31 + t)], timestamp: 31 + t)
        }
        canvas.processTouchFrame([], timestamp: 32.1)
        func key(_ code: UInt16, _ text: String, type: NSEvent.EventType = .keyDown) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: overlay.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        _ = handleKeyboard(key(6, "z")); checks["desktopSingleZUndo"] = canvas.engine.document.strokes.isEmpty
        _ = handleKeyboard(key(16, "y")); checks["desktopSingleYRedo"] = canvas.engine.document.strokes.count == 1
        _ = handleKeyboard(key(49, " "))
        canvas.processTouchFrame([finger(93, 0.8, 0.3, 33)], timestamp: 33)
        canvas.processTouchFrame([], timestamp: 33.1)
        checks["desktopSpacePreviewsWithoutInk"] = canvas.engine.preview && canvas.engine.document.strokes.count == 1
        _ = handleKeyboard(key(49, " ", type: .keyUp))
        canvas.engine.color = .blue
        let arrow = [InkPoint(0.58, 0.70), InkPoint(0.80, 0.48), InkPoint(0.73, 0.49), InkPoint(0.80, 0.48), InkPoint(0.79, 0.59)]
        for (i, p) in arrow.enumerated() {
            let time = 34 + Double(i) * 0.2
            canvas.processTouchFrame([finger(94, p.x, p.y, time)], timestamp: time)
        }
        canvas.processTouchFrame([], timestamp: 35)
        checks["desktopMarksUseScreenAspect"] = canvas.engine.document.aspect == documentAspect
        let count = canvas.engine.document.strokes.count
        _ = handleKeyboard(key(36, "\r"))
        // Let the WindowServer apply the mouse-event routing change before querying it.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        checks["desktopEnterAllowsInteraction"] = !canvas.isWriting && overlay.ignoresMouseEvents && !canvas.cursorDetached && !canvas.cursorHidden
        checks["desktopPausedInkDoesNotInterceptClicks"] = NSWindow.windowNumber(at: NSPoint(x: overlay.frame.minX + overlay.frame.width * 0.15, y: overlay.frame.minY + overlay.frame.height * 0.52), belowWindowWithWindowNumber: 0) != overlay.windowNumber
        checks["desktopInteractionKeepsMarksVisible"] = overlay.isVisible && toolbar.isVisible && canvas.engine.document.strokes.count == count
        resume()
        checks["desktopResumeCapturesAgain"] = canvas.isWriting && !overlay.ignoresMouseEvents
        pause()
        overlay.contentView?.layoutSubtreeIfNeeded(); toolbar.contentView?.layoutSubtreeIfNeeded()
        if let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            checks["desktopEmptyPixelsAreTransparent"] = (bitmap.colorAt(x: 10, y: 10)?.alphaComponent ?? 1) < 0.01
            let ink = canvas.engine.document.strokes[0].points[60]
            let px = Int(ink.x * Double(bitmap.pixelsWide)), py = Int(ink.y * Double(bitmap.pixelsHigh))
            checks["desktopInkPixelsVisible"] = (bitmap.colorAt(x: px, y: py)?.alphaComponent ?? 0) > 0.5
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("desktop-overlay.png"))
            writeDemonstration(ink: bitmap, output: output)
        }
        if let root = toolbar.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            checks["desktopToolbarFits"] = root.subviews.flatMap { $0.subviews }.allSatisfy { root.bounds.insetBy(dx: -1, dy: -1).contains($0.convert($0.bounds, to: root)) }
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("desktop-toolbar.png"))
        }
        showHelp()
        if let root = help.contentViewController?.view {
            root.layoutSubtreeIfNeeded()
            checks["desktopHelpFits"] = root.bounds.width <= 321 && root.subviews.allSatisfy { root.bounds.contains($0.frame) }
            if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("desktop-help.png"))
            }
        }
        _ = handleKeyboard(key(4, "h")); checks["desktopHClosesHelp"] = !help.isShown
        save()
        checks["desktopDocumentsSerialize"] = (try? JSONDecoder().decode([String: InkDocument].self, from: JSONEncoder().encode(documents)))?.values.allSatisfy { $0.isValid } == true
        resume(); _ = handleKeyboard(key(53, "\u{1b}"))
        checks["desktopEscHidesAndRestoresCursor"] = !isVisible && !overlay.isVisible && !toolbar.isVisible && !canvas.cursorHidden && !canvas.cursorDetached
        if let screen = NSScreen.screens.first {
            begin(on: screen, settings: canvas.engine, previous: nil)
            checks["desktopReentryRetainsMarks"] = canvas.engine.document.strokes.count == count
            _ = handleKeyboard(key(3, "f"))
            checks["desktopFExits"] = !isVisible
        }
        return checks
    }

    private func writeDemonstration(ink: NSBitmapImageRep, output: String) {
        // A generated example background, not a screenshot of the user's applications.
        let size = canvas.bounds.size
        let picture = NSImage(size: size, flipped: true) { rect in
            NSColor(srgbRed: 0.91, green: 0.94, blue: 0.97, alpha: 1).setFill(); rect.fill()
            func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ font: CGFloat, _ color: NSColor = .darkGray) {
                (value as NSString).draw(at: NSPoint(x: rect.width * x, y: rect.height * y), withAttributes: [.font: NSFont.systemFont(ofSize: font * rect.width / 1180), .foregroundColor: color])
            }
            text("项目讲解 · 透明桌面标记演示", 0.10, 0.18, 28)
            text("示例背景由应用生成，未截取桌面内容", 0.10, 0.24, 14, .gray)
            for (x, width) in [(0.13, 0.43), (0.62, 0.26)] {
                NSColor.white.setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.width * x, y: rect.height * 0.34, width: rect.width * width, height: rect.height * 0.36), xRadius: 16, yRadius: 16).fill()
            }
            text("需要说明的重点", 0.22, 0.44, 23)
            text("直接圈出屏幕中的内容", 0.22, 0.52, 15, .gray)
            text("下一步", 0.71, 0.40, 22)
            text("指向关键位置", 0.67, 0.56, 15, .gray)
            let inkImage = NSImage(size: size); inkImage.addRepresentation(ink)
            inkImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        if let tiff = picture.tiffRepresentation, let result = NSBitmapImageRep(data: tiff) {
            try? result.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("desktop-demo.png"))
        }
    }
}
