import Foundation
import CoreGraphics

struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
    var clampedToUnit: InkPoint { InkPoint(min(1, max(0, x)), min(1, max(0, y))) }
}

struct InkColor: RawRepresentable, Codable, Equatable, Hashable, CaseIterable {
    let rawValue: String
    static let graphite = InkColor(rawValue: "graphite")!
    static let blue = InkColor(rawValue: "blue")!
    static let coral = InkColor(rawValue: "coral")!
    static let green = InkColor(rawValue: "green")!
    static let allCases: [InkColor] = [.graphite, .blue, .coral, .green]
    init?(rawValue: String) {
        let named = ["graphite", "blue", "coral", "green"]
        if named.contains(rawValue) { self.rawValue = rawValue; return }
        let hex = rawValue.uppercased()
        guard hex.count == 7, hex.first == "#", UInt32(hex.dropFirst(), radix: 16) != nil else { return nil }
        self.rawValue = hex
    }
    var rgb: UInt32 {
        switch rawValue {
        case "graphite": return 0x24333D
        case "blue": return 0x3363D9
        case "coral": return 0xD65240
        case "green": return 0x217A61
        default: return UInt32(rawValue.dropFirst(), radix: 16)!
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard let value = InkColor(rawValue: try c.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ink color")
        }
        self = value
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

enum DrawingMode: String, Codable, CaseIterable {
    case holdToDraw, touchToDraw, pressToDraw
    var next: DrawingMode {
        let values = Self.allCases
        return values[(values.firstIndex(of: self)! + 1) % values.count]
    }
}
enum InkTool { case pen, eraser }

struct RecentInkColors: Codable {
    private(set) var colors: [InkColor] = []
    mutating func use(_ color: InkColor) {
        colors.removeAll { $0.rgb == color.rgb }
        colors.insert(color, at: 0)
        colors = Array(colors.prefix(6))
    }
}

enum InkBrush: String, Codable { case pen, brush }

struct InkViewport: Codable {
    static let zoomRange = 0.1...16.0
    var zoom: Double = 1
    var center = InkPoint(0.5, 0.5)

    func worldPoint(at point: InkPoint) -> InkPoint {
        InkPoint(center.x + (point.x - 0.5) / zoom, center.y + (point.y - 0.5) / zoom)
    }
    func viewPoint(at point: InkPoint) -> InkPoint {
        InkPoint(0.5 + (point.x - center.x) * zoom, 0.5 + (point.y - center.y) * zoom)
    }
    mutating func zoom(by factor: Double, around anchor: InkPoint = InkPoint(0.5, 0.5)) {
        guard factor.isFinite && factor > 0 else { return }
        let world = worldPoint(at: anchor)
        zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom * factor))
        center = InkPoint(world.x - (anchor.x - 0.5) / zoom, world.y - (anchor.y - 0.5) / zoom)
    }
    mutating func pan(dx: Double, dy: Double) {
        guard dx.isFinite && dy.isFinite else { return }
        center = InkPoint(center.x - dx / zoom, center.y - dy / zoom)
    }
}

// Anchor both pan and pinch to the same initial world point, including at zoom limits.
struct NavigationGesture {
    let initial: InkViewport
    let anchor: InkPoint
    let distance: Double
    let ids: Set<AnyHashable>
    let aspect: Double
    init(viewport: InkViewport, fingers: [FingerSample], aspect: Double) {
        initial = viewport; self.aspect = aspect
        ids = Set(fingers.map(\.id))
        let centroid = Self.centroid(fingers)
        anchor = viewport.worldPoint(at: centroid)
        distance = max(0.025, Self.distance(fingers, aspect: aspect))
    }
    func updated(_ fingers: [FingerSample]) -> InkViewport? {
        guard fingers.count == 2, Set(fingers.map(\.id)) == ids else { return nil }
        let center = Self.centroid(fingers)
        var result = initial
        result.zoom = min(InkViewport.zoomRange.upperBound, max(InkViewport.zoomRange.lowerBound,
            initial.zoom * max(0.025, Self.distance(fingers, aspect: aspect)) / distance))
        result.center = InkPoint(anchor.x - (center.x - 0.5) / result.zoom, anchor.y - (center.y - 0.5) / result.zoom)
        return result
    }
    static func centroid(_ fingers: [FingerSample]) -> InkPoint {
        InkPoint((fingers[0].point.x + fingers[1].point.x) / 2, (fingers[0].point.y + fingers[1].point.y) / 2)
    }
    static func distance(_ fingers: [FingerSample], aspect: Double) -> Double {
        hypot(fingers[0].point.x - fingers[1].point.x, (fingers[0].point.y - fingers[1].point.y) / aspect)
    }
}

struct InkStroke: Codable {
    var points: [InkPoint]
    var color: InkColor
    // Width is relative to the canvas width, so resize/export preserve proportions.
    var width: Double
    // Optional fields allow version 0.1's constant-width strokes to load unchanged.
    var brush: InkBrush? = nil
    var widthFactors: [Double]? = nil
    var id: UUID? = UUID()
    // Eraser strokes remove only earlier ink; nil keeps legacy documents compatible.
    var eraser: Bool? = nil

    func factor(at index: Int) -> Double {
        guard let widthFactors, widthFactors.indices.contains(index) else { return 1 }
        return widthFactors[index]
    }
}

struct InkDocument: Codable {
    var strokes: [InkStroke] = []
    var aspect: Double = 1.6
    var viewport: InkViewport? = nil
    var formatVersion: Int? = 3

    var isValid: Bool {
        guard aspect.isFinite, (0.5...3).contains(aspect) else { return false }
        if let v = viewport {
            guard v.zoom.isFinite, InkViewport.zoomRange.contains(v.zoom), Self.valid(v.center) else { return false }
        }
        return strokes.allSatisfy { stroke in
            stroke.width.isFinite && (0.00001...(stroke.eraser == true ? 10.0 : 0.1)).contains(stroke.width) && stroke.points.allSatisfy(Self.valid)
            && (stroke.widthFactors == nil || (stroke.widthFactors!.count == stroke.points.count
                && stroke.widthFactors!.allSatisfy { $0.isFinite && (0.02...10).contains($0) }))
        }
    }
    private static func valid(_ point: InkPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && abs(point.x) < 1e8 && abs(point.y) < 1e8
    }
    var contentBounds: CGRect {
        var bounds: CGRect?
        for stroke in strokes where stroke.eraser != true {
            let radius = stroke.width * (stroke.widthFactors?.max() ?? 1) / 2
            for point in stroke.points {
                let rect = CGRect(x: point.x - radius, y: point.y - radius * aspect, width: radius * 2, height: radius * 2 * aspect)
                bounds = bounds.map { $0.union(rect) } ?? rect
            }
        }
        guard var result = bounds else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let padding = max(0.025, max(result.width, result.height) * 0.04)
        result = result.insetBy(dx: -padding, dy: -padding)
        return result
    }
}

struct FingerSample {
    var id: AnyHashable
    var point: InkPoint
    var pressure: Double = 0
    var timestamp: Double = 0
    // Physical normalized touch position keeps speed response independent of zoom.
    var inputPoint: InkPoint? = nil
}

enum PressureResponse {
    static func normalized(_ pressure: Double, sensitivity: Double) -> Double {
        guard pressure.isFinite else { return 0 }
        let p = min(1, max(0, pressure))
        let knee = 0.18 / min(5, max(0.5, sensitivity))
        // A soft knee expands low pressures without a threshold or abrupt saturation.
        return p * (1 + knee) / (p + knee)
    }
}

final class InkEngine {
    var document = InkDocument()
    var color: InkColor = .graphite
    var width: Double = 0.004
    var brush: InkBrush = .pen
    var pressureEnabled = true
    var pressureSensitivity: Double = 2
    var lightTouchAssistance = true
    var tool: InkTool = .pen
    var eraserWidth: Double = 0.025
    var onColorUsed: ((InkColor) -> Void)?
    private(set) var pointer: InkPoint?
    private(set) var preview = false
    private(set) var blockedUntilLift = false
    private(set) var activeID: AnyHashable?
    private(set) var activeStroke: Int?
    private(set) var revision = 0
    private var lastSample: FingerSample?
    private var lastMotionSample: FingerSample?
    private var filteredSpeed: Double = 0.6
    private var lastWidthTimestamp: Double = 0
    private var smoothedFactor: Double = 1
    private var redoStack: [InkStroke] = []
    var canUndo: Bool { !document.strokes.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func frame(_ fingers: [FingerSample], ended: [FingerSample] = []) {
        if let id = activeID, let last = ended.first(where: { $0.id == id }) {
            append(last)
            finish()
        }
        if fingers.isEmpty {
            finish()
            blockedUntilLift = false
            pointer = nil
            return
        }
        // Reject ambiguous input and require all fingers to lift before resuming.
        if fingers.count > 1 {
            finish()
            blockedUntilLift = true
            pointer = nil
            return
        }
        guard !blockedUntilLift, let finger = fingers.first else { return }
        pointer = finger.point
        if preview { finish(); return }
        if activeID != finger.id {
            finish()
            redoStack.removeAll()
            smoothedFactor = widthFactor(for: finger)
            document.strokes.append(InkStroke(points: [finger.point], color: color,
                width: tool == .eraser ? eraserWidth : width * (brush == .brush ? 1.8 : 1),
                brush: tool == .eraser ? nil : brush, widthFactors: [smoothedFactor], eraser: tool == .eraser ? true : nil))
            document.formatVersion = 3
            if tool == .pen { onColorUsed?(color) }
            activeStroke = document.strokes.count - 1
            activeID = finger.id
            lastSample = finger
            lastMotionSample = finger
            lastWidthTimestamp = finger.timestamp
            revision += 1
        } else {
            append(finger)
        }
    }

    private func widthFactor(for sample: FingerSample) -> Double {
        if tool == .eraser { return 1 }
        let response = PressureResponse.normalized(sample.pressure, sensitivity: pressureSensitivity)
        if pressureEnabled && lightTouchAssistance {
            let base = brush == .brush ? 0.65 + 1.2 / (1 + filteredSpeed / 0.65) : 0.70 + 0.9 / (1 + filteredSpeed / 0.65)
            let maximum = brush == .brush ? 3.3 : 2.5
            return base + (maximum - base) * response
        }
        let force = pressureEnabled ? (brush == .brush ? 0.8 + 2.5 * response : 0.65 + 1.85 * response) : 1
        return brush == .brush ? force * (0.55 + 0.45 / (1 + filteredSpeed * 0.3)) : force
    }
    private func updateSpeed(_ sample: FingerSample) {
        defer { lastMotionSample = sample }
        guard let previous = lastMotionSample, sample.timestamp > previous.timestamp else { return }
        let from = previous.inputPoint ?? previous.point, to = sample.inputPoint ?? sample.point
        let dt = sample.timestamp - previous.timestamp
        let speed = hypot(to.x - from.x, (to.y - from.y) / document.aspect) / max(1.0 / 240, dt)
        filteredSpeed += (min(20, speed) - filteredSpeed) * (1 - exp(-dt / 0.04))
    }
    private func append(_ sample: FingerSample, pressureOnly: Bool = false) {
        guard let index = activeStroke, document.strokes.indices.contains(index) else { return }
        if !pressureOnly { updateSpeed(sample) }
        let target = widthFactor(for: sample)
        let dt = sample.timestamp > lastWidthTimestamp ? sample.timestamp - lastWidthTimestamp : (sample.timestamp == 0 ? 1.0 / 120 : 0)
        // Time-based smoothing: quick response to added pressure, gentle release.
        let responseTime = target > smoothedFactor ? 0.014 : 0.035
        smoothedFactor += (target - smoothedFactor) * (1 - exp(-dt / responseTime))
        lastWidthTimestamp = max(lastWidthTimestamp, sample.timestamp)
        if document.strokes[index].points.last != sample.point {
            document.strokes[index].points.append(sample.point)
            document.strokes[index].widthFactors?.append(smoothedFactor)
        } else if document.strokes[index].widthFactors != nil {
            // Pressure can change while the finger remains stationary.
            document.strokes[index].widthFactors![document.strokes[index].points.count - 1] = smoothedFactor
        }
        lastSample = sample
        revision += 1
    }

    func updatePressure(_ pressure: Double, timestamp: Double) {
        guard tool == .pen, var sample = lastSample, activeID != nil, !preview else { return }
        sample.pressure = pressure; sample.timestamp = timestamp
        append(sample, pressureOnly: true)
    }
    func discardGesturePrelude(maxLength: Double) {
        guard let index = activeStroke, index == document.strokes.count - 1 else { return }
        let points = document.strokes[index].points
        let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, ($1.1.y - $1.0.y) / document.aspect) }
        if length < maxLength { document.strokes.removeLast(); revision += 1 }
        finish()
    }
    func finish() {
        if activeStroke != nil { revision += 1 }
        activeID = nil; activeStroke = nil; lastSample = nil; lastMotionSample = nil
        filteredSpeed = 0.6; lastWidthTimestamp = 0
    }
    func cancelContacts() {
        finish(); pointer = nil; blockedUntilLift = false; preview = false
    }
    func setPreview(_ enabled: Bool) {
        if preview != enabled { finish(); preview = enabled }
    }
    func undo() {
        finish()
        if let stroke = document.strokes.popLast() { redoStack.append(stroke); revision += 1 }
    }
    func redo() {
        finish()
        if let stroke = redoStack.popLast() { document.strokes.append(stroke); revision += 1 }
    }
    func clear() {
        cancelContacts(); document.strokes.removeAll(); redoStack.removeAll(); revision += 1
    }
}
