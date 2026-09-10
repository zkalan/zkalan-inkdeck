import AppKit
import CoreGraphics

extension InkColor {
    var nsColor: NSColor {
        switch self {
        case .graphite: return NSColor(srgbRed: 0.14, green: 0.20, blue: 0.24, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.20, green: 0.39, blue: 0.85, alpha: 1)
        case .coral: return NSColor(srgbRed: 0.84, green: 0.32, blue: 0.25, alpha: 1)
        case .green: return NSColor(srgbRed: 0.13, green: 0.48, blue: 0.38, alpha: 1)
        }
    }
    var title: String {
        switch self { case .graphite: return "墨黑"; case .blue: return "靛蓝"; case .coral: return "朱红"; case .green: return "松绿" }
    }
}

final class CanvasView: NSView {
    let engine = InkEngine()
    var onChange: (() -> Void)?
    var onDocumentChange: (() -> Void)?
    private(set) var isWriting = false
    private(set) var receivedFrames = 0
    private(set) var contactCount = 0
    private(set) var deviceLabel = "等待触控板输入"
    private(set) var sessionMessage = "点击「开始书写」，让触控板变成一张纸"
    var showGrid = true { didSet { needsDisplay = true } }
    var desktopSurface = false { didSet { needsDisplay = true } }
    var handTool = false { didSet { changed() } }
    private(set) var rawPointer: InkPoint?
    private(set) var currentPressure: Double = 0
    private(set) var pressureEventCount = 0
    private(set) var isNavigating = false
    private let renderer = InkRenderer()
    private var navigation: NavigationGesture?
    private var navigationUntilLift = false
    private var extraTouchesBlocked = false
    private var singleBeganAt: Double = 0
    private var lastTouchTimestamp: Double?
    private var mouseDragLast: NSPoint?
    var viewport: InkViewport {
        get { engine.document.viewport ?? InkViewport() }
        set { engine.document.viewport = newValue }
    }
    private(set) var cursorDetached = false
    private(set) var cursorHidden = false
    private(set) var lastCursorRestoreSucceeded = true
    private var savedCursor: CGPoint?
    private var hasDeviceAspect = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("触控板手写画布")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var paperRect: NSRect {
        if desktopSurface { return bounds }
        let space = bounds.insetBy(dx: 3, dy: 3)
        let aspect = max(0.5, min(3, engine.document.aspect))
        let width = max(1, min(space.width, space.height * aspect))
        let height = width / aspect
        return NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    @discardableResult func startWriting() -> Bool {
        guard !isWriting, let window, window.isKeyWindow, NSApp.isActive,
              let screenTop = NSScreen.screens.first?.frame.maxY else { return false }
        window.makeFirstResponder(self)
        engine.cancelContacts()
        resetNavigation()
        handTool = false
        let appPoint = window.convertPoint(toScreen: convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil))
        savedCursor = CGEvent(source: nil)?.location
        // Keep the OS cursor over this NSView so each new touch sequence reaches it.
        let warp = CGWarpMouseCursorPosition(CGPoint(x: appPoint.x, y: screenTop - appPoint.y))
        guard warp == .success else {
            sessionMessage = "无法定位光标，请重新点击画布后开始"
            changed(); return false
        }
        let result = CGAssociateMouseAndMouseCursorPosition(0)
        guard result == .success else {
            if let savedCursor { CGWarpMouseCursorPosition(savedCursor) }
            sessionMessage = "无法进入书写模式，请退出应用后重试"
            changed(); return false
        }
        cursorDetached = true
        cursorHidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
        isWriting = true
        sessionMessage = "先抬起手指，再轻触书写 · 按 Esc 退出"
        changed()
        return true
    }

    func stopWriting(message: String = "已退出书写，可以正常使用光标") {
        let wasWriting = isWriting
        isWriting = false
        engine.cancelContacts()
        resetNavigation()
        contactCount = 0
        if cursorDetached {
            lastCursorRestoreSucceeded = CGAssociateMouseAndMouseCursorPosition(1) == .success
            cursorDetached = false
        }
        // Only warp back while foreground; never move another application's cursor.
        if wasWriting, NSApp.isActive, let savedCursor { CGWarpMouseCursorPosition(savedCursor) }
        savedCursor = nil
        if cursorHidden {
            let shown = CGDisplayShowCursor(CGMainDisplayID()) == .success
            lastCursorRestoreSucceeded = shown && lastCursorRestoreSucceeded
            cursorHidden = false
        }
        if wasWriting { sessionMessage = message; changed(); onDocumentChange?() }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopWriting() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func mouseDown(with event: NSEvent) {
        if !isWriting && (handTool || event.modifierFlags.contains(.option)) {
            mouseDragLast = convert(event.locationInWindow, from: nil)
        } else if !isWriting { startWriting() }
    }
    // Mouse drags can move the view in hand mode, but never create ink.
    override func mouseDragged(with event: NSEvent) {
        guard !isWriting, let last = mouseDragLast else { return }
        let point = convert(event.locationInWindow, from: nil)
        pan(dx: (point.x - last.x) / paperRect.width, dy: (point.y - last.y) / paperRect.height)
        mouseDragLast = point
    }
    override func mouseUp(with event: NSEvent) { mouseDragLast = nil }
    override func scrollWheel(with event: NSEvent) {
        // While captured, raw touches handle both pinch and pan. Do not apply OS gestures twice.
        guard !isWriting, !desktopSurface else { return }
        let gain = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
        pan(dx: event.scrollingDeltaX * gain / paperRect.width, dy: event.scrollingDeltaY * gain / paperRect.height)
    }
    override func magnify(with event: NSEvent) {
        guard !isWriting, !desktopSurface else { return }
        let p = convert(event.locationInWindow, from: nil)
        zoom(by: max(0.05, 1 + event.magnification), around: InkPoint((p.x - paperRect.minX) / paperRect.width, (p.y - paperRect.minY) / paperRect.height))
    }
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}

    private func sample(_ touch: NSTouch, timestamp: Double) -> FingerSample {
        FingerSample(id: AnyHashable(touch.identity as! NSObject),
                     point: InkPoint(touch.normalizedPosition.x, 1 - touch.normalizedPosition.y).clampedToUnit,
                     pressure: currentPressure, timestamp: timestamp,
                     inputPoint: InkPoint(touch.normalizedPosition.x, 1 - touch.normalizedPosition.y).clampedToUnit)
    }
    private func receive(_ event: NSEvent) {
        guard isWriting, lastTouchTimestamp != event.timestamp else { return }
        lastTouchTimestamp = event.timestamp
        let touches = event.touches(matching: .touching, in: self).filter { $0.type == .indirect }
        let ended = event.touches(matching: .ended, in: self).filter { $0.type == .indirect }
        receivedFrames += 1
        if !hasDeviceAspect, let touch = touches.first, touch.deviceSize.height > 0 {
            let aspect = touch.deviceSize.width / touch.deviceSize.height
            if aspect >= 0.5 && aspect <= 3 {
                if engine.document.strokes.isEmpty && !desktopSurface { engine.document.aspect = aspect }
                hasDeviceAspect = true
                deviceLabel = String(format: "触控板已连接 · 比例 %.2f : 1", aspect)
            }
        }
        let fingers = touches.map { sample($0, timestamp: event.timestamp) }
        processTouchFrame(fingers, ended: ended.map { sample($0, timestamp: event.timestamp) }, timestamp: event.timestamp)
    }
    // The real NSTouch adapter and the integration checks share this routing path.
    // Synthetic samples deliberately do not increment the hardware-input counter.
    func processTouchFrame(_ fingers: [FingerSample], ended: [FingerSample] = [], timestamp: Double) {
        if desktopSurface {
            contactCount = fingers.count
            let oldRevision = engine.revision
            if fingers.count >= 2 { engine.discardGesturePrelude(maxLength: 0.012); currentPressure = 0 }
            engine.frame(fingers, ended: ended)
            rawPointer = fingers.count == 1 && !engine.blockedUntilLift ? fingers.first?.point : nil
            if fingers.isEmpty { currentPressure = 0 }
            changed()
            if engine.revision != oldRevision { onDocumentChange?() }
            return
        }
        if contactCount == 0 && fingers.count == 1 { singleBeganAt = timestamp }
        contactCount = fingers.count
        let oldRevision = engine.revision
        if fingers.count >= 2 {
            if !navigationUntilLift {
                if timestamp - singleBeganAt < 0.20 { engine.discardGesturePrelude(maxLength: 0.012 / viewport.zoom) }
                engine.frame([])
            }
            navigationUntilLift = true
            rawPointer = nil; currentPressure = 0
            if fingers.count > 2 { extraTouchesBlocked = true; navigation = nil }
            if fingers.count == 2 && !extraTouchesBlocked {
                if navigation?.ids != Set(fingers.map(\.id)) {
                    navigation = NavigationGesture(viewport: viewport, fingers: fingers, aspect: engine.document.aspect)
                }
                if let updated = navigation?.updated(fingers) {
                    viewport = updated; isNavigating = true; onDocumentChange?()
                }
                sessionMessage = "双指移动画布 · 张合缩放 · 全部抬手后继续写"
            } else { sessionMessage = "接触点过多，请全部抬手后重试" }
        } else if navigationUntilLift {
            if fingers.isEmpty { resetNavigation(); engine.frame([]) }
            sessionMessage = fingers.isEmpty ? "轻触书写 · 双指移动和缩放" : "请先全部抬手，再用单指继续写"
        } else {
            rawPointer = fingers.first?.point
            func world(_ sample: FingerSample) -> FingerSample {
                var result = sample; result.point = viewport.worldPoint(at: sample.point); return result
            }
            engine.frame(fingers.map(world), ended: ended.map(world))
            if fingers.isEmpty { currentPressure = 0 }
            sessionMessage = engine.preview ? "正在预览落点 · 松开空格后书写" : "轻触书写 · 加力增粗 · 双指移动和缩放"
        }
        changed()
        if engine.revision != oldRevision { onDocumentChange?() }
    }
    override func touchesBegan(with event: NSEvent) { receive(event) }
    override func touchesMoved(with event: NSEvent) { receive(event) }
    override func touchesEnded(with event: NSEvent) { receive(event) }
    override func touchesCancelled(with event: NSEvent) {
        engine.cancelContacts(); contactCount = 0; resetNavigation(); changed(); onDocumentChange?()
    }
    override func pressureChange(with event: NSEvent) {
        guard isWriting else { return }
        pressureEventCount += 1
        guard contactCount == 1, !navigationUntilLift else { currentPressure = 0; changed(); return }
        currentPressure = event.stage == 0 ? 0 : min(1, max(0, Double(event.pressure)))
        engine.updatePressure(currentPressure, timestamp: event.timestamp)
        changed(); onDocumentChange?()
    }
    private func resetNavigation() {
        navigation = nil; navigationUntilLift = false; extraTouchesBlocked = false
        isNavigating = false; rawPointer = nil; currentPressure = 0; mouseDragLast = nil; lastTouchTimestamp = nil
    }
    func zoom(by factor: Double, around point: InkPoint = InkPoint(0.5, 0.5)) {
        engine.finish(); viewport.zoom(by: factor, around: point)
        navigation = nil; changed(); onDocumentChange?()
    }
    func pan(dx: Double, dy: Double) {
        engine.finish(); viewport.pan(dx: dx, dy: dy)
        changed(); onDocumentChange?()
    }
    func resetViewport() {
        engine.finish(); viewport = InkViewport(); navigation = nil
        changed(); onDocumentChange?()
    }
    func fitContent() {
        engine.finish()
        let rect = engine.document.contentBounds
        let zoom = min(16, max(0.1, 0.90 / max(rect.width, rect.height)))
        viewport = InkViewport(zoom: zoom, center: InkPoint(rect.midX, rect.midY))
        navigation = nil; changed(); onDocumentChange?()
    }
    func setPreview(_ enabled: Bool) {
        guard isWriting else { return }
        engine.setPreview(enabled)
        sessionMessage = enabled ? "正在预览落点 · 松开空格后书写" : "轻触落笔，抬手断笔 · 按 Esc 退出"
        changed()
    }
    func changed() { needsDisplay = true; onChange?() }

    func drawInk(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext.current?.cgContext {
            context.clip(to: rect)
            let origin = viewport.viewPoint(at: InkPoint(0, 0))
            context.translateBy(x: rect.minX + origin.x * rect.width, y: rect.minY + origin.y * rect.height)
            context.scaleBy(x: rect.width * viewport.zoom, y: rect.height * engine.document.aspect * viewport.zoom)
            renderer.draw(engine.document, activeStroke: engine.activeStroke, in: context)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func draw(_ dirtyRect: NSRect) {
        if desktopSurface {
            NSGraphicsContext.current?.cgContext.clear(bounds)
            // WindowServer ignores fully transparent pixels when routing a new touch sequence.
            // Keep a 1% backing while drawing; interaction mode clears it completely.
            if isWriting { NSColor.black.withAlphaComponent(0.01).setFill(); bounds.fill() }
            drawInk(in: bounds)
            drawPointer(in: bounds)
            return
        }
        let paper = paperRect
        NSColor(srgbRed: 0.96, green: 0.96, blue: 0.95, alpha: 1).setFill()
        bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.04)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor(srgbRed: 0.998, green: 0.995, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: paper, xRadius: 3, yRadius: 3).fill()
        NSGraphicsContext.restoreGraphicsState()
        if showGrid {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: paper.insetBy(dx: 1, dy: 1)).addClip()
            let grid = NSBezierPath()
            var step = 1.0 / 16
            while step * paper.width * viewport.zoom < 18 { step *= 2 }
            while step * paper.width * viewport.zoom > 90 { step /= 2 }
            let origin = viewport.viewPoint(at: InkPoint(0, 0))
            let spacing = step * paper.width * viewport.zoom
            let offsetX = (origin.x * paper.width).truncatingRemainder(dividingBy: spacing)
            let offsetY = (origin.y * paper.height).truncatingRemainder(dividingBy: spacing)
            for x in stride(from: paper.minX + offsetX - spacing, to: paper.maxX, by: spacing) {
                grid.move(to: NSPoint(x: x, y: paper.minY)); grid.line(to: NSPoint(x: x, y: paper.maxY))
            }
            for y in stride(from: paper.minY + offsetY - spacing, to: paper.maxY, by: spacing) {
                grid.move(to: NSPoint(x: paper.minX, y: y)); grid.line(to: NSPoint(x: paper.maxX, y: y))
            }
            NSColor(srgbRed: 0.85, green: 0.87, blue: 0.82, alpha: 0.48).setStroke()
            grid.lineWidth = 0.6; grid.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        drawInk(in: paper)
        let border = NSBezierPath(roundedRect: paper, xRadius: 3, yRadius: 3)
        (isWriting ? InkColor.green.nsColor.withAlphaComponent(0.75) : NSColor.black.withAlphaComponent(0.10)).setStroke()
        border.lineWidth = isWriting ? 2 : 1
        border.stroke()
        drawPointer(in: paper)
        if engine.document.strokes.isEmpty && !isWriting {
            drawCentered("按 Enter 开始书写", at: paper.midY - 10, size: 16, color: .tertiaryLabelColor)
        }
    }

    private func drawPointer(in paper: NSRect) {
        if let point = rawPointer, isWriting {
            let p = NSPoint(x: paper.minX + point.x * paper.width, y: paper.minY + point.y * paper.height)
            let radius: CGFloat = engine.preview ? 11 : 6
            let ring = NSBezierPath(ovalIn: NSRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
            InkColor.green.nsColor.setStroke(); ring.lineWidth = 1.5; ring.stroke()
            if engine.preview {
                let cross = NSBezierPath()
                cross.move(to: NSPoint(x: p.x - 17, y: p.y)); cross.line(to: NSPoint(x: p.x + 17, y: p.y))
                cross.move(to: NSPoint(x: p.x, y: p.y - 17)); cross.line(to: NSPoint(x: p.x, y: p.y + 17))
                cross.lineWidth = 0.7; cross.stroke()
            }
        }
    }

    private func drawCentered(_ text: String, at y: CGFloat, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: size > 20 ? .medium : .regular), .foregroundColor: color]
        let line = text as NSString
        let width = line.size(withAttributes: attrs).width
        line.draw(at: NSPoint(x: bounds.midX - width / 2, y: y), withAttributes: attrs)
    }

    func pngData() -> Data? {
        // Export every stroke, including content outside the current viewport.
        var content: CGRect?
        for stroke in engine.document.strokes {
            let path = InkRenderer.path(for: stroke, aspect: engine.document.aspect, active: false)
            if !path.isEmpty { content = content.map { $0.union(path.boundingBoxOfPath) } ?? path.boundingBoxOfPath }
        }
        var area = content ?? CGRect(x: 0, y: 0, width: 1, height: 1 / engine.document.aspect)
        let padding = max(0.015, max(area.width, area.height) * 0.04)
        area = area.insetBy(dx: -padding, dy: -padding)
        let scale = 4096 / max(area.width, area.height)
        let width = max(1, Int(ceil(area.width * scale)))
        let height = max(1, Int(ceil(area.height * scale)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.translateBy(x: 0, y: CGFloat(height))
        context.cgContext.scaleBy(x: 1, y: -1)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.white.setFill(); rect.fill()
        context.cgContext.scaleBy(x: scale, y: scale)
        context.cgContext.translateBy(x: -area.minX, y: -area.minY)
        renderer.draw(engine.document, activeStroke: nil, in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
