import AppKit

// Paths use isotropic document units (y / aspect), independent of zoom or export size.
final class InkRenderer {
    private struct CacheEntry {
        var count: Int
        var last: InkPoint?
        var factor: Double
        var active: Bool
        var aspect: Double
        var path: CGPath
    }
    private var cache: [String: CacheEntry] = [:]

    func draw(_ document: InkDocument, activeStroke: Int?, in context: CGContext) {
        var liveKeys = Set<String>()
        for (index, stroke) in document.strokes.enumerated() {
            let key = stroke.id?.uuidString ?? "legacy-\(index)"
            liveKeys.insert(key)
            let active = activeStroke == index
            let factor = stroke.points.isEmpty ? 1 : stroke.factor(at: stroke.points.count - 1)
            let entry: CacheEntry
            if let old = cache[key], old.count == stroke.points.count, old.last == stroke.points.last,
               old.factor == factor, old.active == active, old.aspect == document.aspect {
                entry = old
            } else {
                entry = CacheEntry(count: stroke.points.count, last: stroke.points.last, factor: factor,
                    active: active, aspect: document.aspect, path: Self.path(for: stroke, aspect: document.aspect, active: active))
                cache[key] = entry
            }
            guard !entry.path.isEmpty, context.boundingBoxOfClipPath.intersects(entry.path.boundingBoxOfPath) else { continue }
            context.setFillColor(stroke.color.nsColor.cgColor)
            context.addPath(entry.path)
            context.fillPath()
        }
        cache = cache.filter { liveKeys.contains($0.key) }
    }

    static func path(for stroke: InkStroke, aspect: Double, active: Bool) -> CGPath {
        let path = CGMutablePath()
        guard !stroke.points.isEmpty else { return path }
        let points = stroke.points.map { CGPoint(x: $0.x, y: $0.y / aspect) }
        var lengths = [Double](repeating: 0, count: points.count)
        for i in points.indices.dropFirst() {
            lengths[i] = lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        let total = lengths.last ?? 0
        var radii = points.indices.map { stroke.width * stroke.factor(at: $0) / 2 }
        if stroke.brush == .brush && total > stroke.width * 1.5 {
            let maxWidth = (radii.max() ?? stroke.width / 2) * 2
            let startLength = min(total * 0.3, maxWidth * 1.8)
            let endLength = min(total * 0.38, maxWidth * 3)
            for i in points.indices {
                let start = 0.18 + 0.82 * min(1, lengths[i] / max(0.000001, startLength))
                let end = active ? 1 : 0.08 + 0.92 * min(1, (total - lengths[i]) / max(0.000001, endLength))
                radii[i] *= min(start, end)
            }
        }
        if points.count == 1 {
            path.addEllipse(in: CGRect(x: points[0].x - radii[0], y: points[0].y - radii[0], width: radii[0] * 2, height: radii[0] * 2))
            return path
        }
        var samples: [(CGPoint, Double)] = [(points[0], radii[0])]
        for i in 0..<(points.count - 1) {
            let a = points[max(0, i - 1)], b = points[i], c = points[i + 1], d = points[min(points.count - 1, i + 2)]
            let distance = hypot(c.x - b.x, c.y - b.y)
            let steps = min(24, max(2, Int(ceil(distance / max(0.0005, stroke.width * 0.25)))))
            for step in 1...steps {
                let t = Double(step) / Double(steps), t2 = t * t, t3 = t2 * t
                func interpolate(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> Double {
                    0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
                }
                // Preserve version 0.1's exact polyline geometry when loading old strokes.
                let point = stroke.brush == nil
                    ? CGPoint(x: b.x + (c.x - b.x) * t, y: b.y + (c.y - b.y) * t)
                    : CGPoint(x: interpolate(a.x, b.x, c.x, d.x), y: interpolate(a.y, b.y, c.y, d.y))
                samples.append((point, radii[i] + (radii[i + 1] - radii[i]) * t))
            }
        }
        for (point, radius) in samples {
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        for i in 1..<samples.count {
            let (a, ra) = samples[i - 1], (b, rb) = samples[i]
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 1e-10 else { continue }
            let nx = -(b.y - a.y) / length, ny = (b.x - a.x) / length
            // Match CGPath ellipse winding; opposite winding would punch circular holes.
            path.move(to: CGPoint(x: a.x + nx * ra, y: a.y + ny * ra))
            path.addLine(to: CGPoint(x: a.x - nx * ra, y: a.y - ny * ra))
            path.addLine(to: CGPoint(x: b.x - nx * rb, y: b.y - ny * rb))
            path.addLine(to: CGPoint(x: b.x + nx * rb, y: b.y + ny * rb))
            path.closeSubpath()
        }
        return path
    }
}
