import AppKit

final class InkPreferences {
    private let defaults: UserDefaults?
    private(set) var recent = RecentInkColors()
    var mode: DrawingMode = .holdToDraw {
        didSet { defaults?.set(mode.rawValue, forKey: "drawingMode") }
    }
    init(persistent: Bool, defaults: UserDefaults? = nil) {
        self.defaults = persistent ? (defaults ?? .standard) : nil
        if let raw = self.defaults?.string(forKey: "drawingMode"), let saved = DrawingMode(rawValue: raw) { mode = saved }
        if let data = self.defaults?.data(forKey: "recentInkColors"), let saved = try? JSONDecoder().decode(RecentInkColors.self, from: data) {
            for color in saved.colors.reversed() { recent.use(color) }
        }
    }
    func record(_ color: InkColor) {
        recent.use(color)
        if let data = try? JSONEncoder().encode(recent) { defaults?.set(data, forKey: "recentInkColors") }
        NotificationCenter.default.post(name: .inkRecentColorsChanged, object: self)
    }
}
extension Notification.Name { static let inkRecentColorsChanged = Notification.Name("InkDeckRecentColorsChanged") }

final class ColorControls: NSStackView {
    let picker = NSButton(title: "调色 K", target: nil, action: nil)
    private let preferences: InkPreferences
    private var buttons: [NSButton] = []
    private var observer: NSObjectProtocol?
    var onPick: (() -> Void)?
    var onSelect: ((InkColor) -> Void)?
    var selected: InkColor = .graphite { didSet { refresh() } }
    init(preferences: InkPreferences) {
        self.preferences = preferences
        super.init(frame: .zero)
        orientation = .horizontal; spacing = 3; alignment = .centerY
        picker.target = self; picker.action = #selector(openPicker)
        picker.bezelStyle = .rounded; picker.controlSize = .small; picker.font = .systemFont(ofSize: 11)
        picker.toolTip = "调色盘 · K · 画过的颜色自动加入最近使用"
        addArrangedSubview(picker)
        for i in 0..<6 {
            let b = NSButton(title: "", target: self, action: #selector(selectRecent(_:)))
            b.tag = i; b.bezelStyle = .regularSquare; b.isBordered = false
            b.widthAnchor.constraint(equalToConstant: 19).isActive = true
            b.heightAnchor.constraint(equalToConstant: 23).isActive = true
            buttons.append(b); addArrangedSubview(b)
        }
        observer = NotificationCenter.default.addObserver(forName: .inkRecentColorsChanged, object: preferences, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private var displayedColors: [InkColor] {
        var values = preferences.recent.colors
        for color in InkColor.allCases where !values.contains(where: { $0.rgb == color.rgb }) { values.append(color) }
        return Array(values.prefix(6))
    }
    func refresh() {
        picker.bezelColor = selected.nsColor.withAlphaComponent(0.22)
        let colors = displayedColors
        for (i, b) in buttons.enumerated() {
            b.isHidden = i >= colors.count
            guard i < colors.count else { continue }
            let color = colors[i], active = selected.rgb == color.rgb
            b.image = NSImage(size: NSSize(width: 19, height: 23), flipped: false) { rect in
                let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 5))
                color.nsColor.setFill(); oval.fill()
                if active { NSColor.labelColor.setStroke(); oval.lineWidth = 1.5; oval.stroke() }
                return true
            }
            b.toolTip = (i < preferences.recent.colors.count ? "最近使用 · " : "预设 · ") + color.title
            b.setAccessibilityLabel(b.toolTip!)
        }
    }
    @objc private func openPicker() { onPick?() }
    @objc private func selectRecent(_ sender: NSButton) {
        let colors = displayedColors
        if colors.indices.contains(sender.tag) { onSelect?(colors[sender.tag]) }
    }
}

// Native macOS wheel/sliders; only the explicit Done button recaptures the trackpad.
final class InkPalette: NSObject {
    private var onSelect: ((InkColor) -> Void)?
    private var onDone: (() -> Void)?
    private var preferences: InkPreferences?
    private(set) var isOpen = false
    func show(color: InkColor, preferences: InkPreferences, onSelect: @escaping (InkColor) -> Void, onDone: @escaping () -> Void) {
        self.onSelect = onSelect; self.onDone = onDone; self.preferences = preferences
        let panel = NSColorPanel.shared
        panel.title = "笔迹调色盘"; panel.showsAlpha = false; panel.isContinuous = true
        panel.setTarget(self); panel.setAction(#selector(colorChanged(_:)))
        panel.color = color.nsColor
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        let recent = ColorControls(preferences: preferences)
        recent.picker.isHidden = true; recent.selected = color
        recent.onSelect = { [weak self, weak recent] color in panel.color = color.nsColor; self?.onSelect?(color); recent?.selected = color }
        let done = NSButton(title: "使用颜色并返回画图", target: self, action: #selector(finishPicking))
        done.bezelStyle = .rounded
        let text = NSTextField(labelWithString: "画出笔迹后自动记录最近颜色")
        text.font = .systemFont(ofSize: 11); text.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [recent, text, done])
        stack.orientation = .vertical; stack.spacing = 8; stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 100)
        panel.accessoryView = stack
        isOpen = true; panel.makeKeyAndOrderFront(nil)
    }
    @objc func colorChanged(_ sender: NSColorPanel) { onSelect?(InkColor(sender.color)) }
    @objc func finishPicking() {
        let callback = onDone
        close(); callback?()
    }
    func close() {
        guard isOpen else { return }
        isOpen = false; NSColorPanel.shared.orderOut(nil); NSColorPanel.shared.accessoryView = nil
        onSelect = nil; onDone = nil; preferences = nil
    }
}
