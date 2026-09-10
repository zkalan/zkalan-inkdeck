import Foundation
import CoreGraphics

@main struct InkEngineTests {
    static func main() {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1; print("PASS: \(name)")
        }
        func finger(_ id: Int, _ x: Double, _ y: Double) -> FingerSample { FingerSample(id: id, point: InkPoint(x, y)) }

        let ink = InkEngine()
        ink.frame([finger(1, 0.1, 0.2)])
        ink.frame([finger(1, 0.4, 0.2)])
        ink.frame([])
        ink.frame([finger(2, 0.65, 0.75)])
        ink.frame([finger(2, 0.85, 0.75)])
        ink.frame([])
        check(ink.document.strokes.count == 2, "抬手换行生成两笔，不产生连接线")
        check(ink.document.strokes[1].points.first == InkPoint(0.65, 0.75), "第二笔从新落点开始，与旧笔末点无关")
        check(ink.document.strokes.allSatisfy { $0.points.count == 2 }, "笔画只包含各自的轨迹")
        ink.frame([finger(3, 0.5, 0.5)])
        ink.frame([], ended: [finger(3, 0.6, 0.6)])
        check(ink.document.strokes.last?.points.last == InkPoint(0.6, 0.6), "保留抬手事件的最后坐标")
        ink.frame([], ended: [finger(3, 0.6, 0.6)])
        check(ink.document.strokes.count == 3, "重复结束事件不会创建额外笔画")

        ink.setPreview(true)
        ink.frame([finger(4, 0.2, 0.8)])
        ink.frame([finger(4, 0.7, 0.3)])
        check(ink.document.strokes.count == 3 && ink.pointer == InkPoint(0.7, 0.3), "空格预览只更新笔尖，不写入笔迹")
        ink.setPreview(false)
        ink.frame([finger(4, 0.71, 0.31)])
        check(ink.document.strokes.last?.points.first == InkPoint(0.71, 0.31), "松开预览从当前位置落笔，不连接预览轨迹")
        ink.setPreview(true)
        ink.frame([finger(4, 0.9, 0.9)])
        check(ink.document.strokes.last?.points.count == 1, "书写中切换预览立即断笔")
        ink.frame([]); ink.setPreview(false)

        let multi = InkEngine()
        multi.frame([finger(1, 0.1, 0.1)])
        multi.frame([finger(1, 0.2, 0.2), finger(2, 0.3, 0.3)])
        multi.frame([finger(1, 0.4, 0.4)])
        check(multi.blockedUntilLift && multi.document.strokes.count == 1 && multi.document.strokes[0].points.count == 1, "多指打断书写，剩余一指不会意外续笔")
        multi.frame([])
        multi.frame([finger(3, 0.6, 0.6)])
        check(!multi.blockedUntilLift && multi.document.strokes.count == 2, "全部抬手后恢复书写")
        multi.cancelContacts()
        multi.frame([finger(3, 0.8, 0.8)])
        check(multi.document.strokes.count == 3, "取消输入后，即使身份复用也开始新笔画")

        let identity = InkEngine()
        identity.frame([finger(1, 0.1, 0.1)])
        identity.frame([finger(2, 0.9, 0.9)])
        check(identity.document.strokes.count == 2, "接触身份变化时强制断笔")
        identity.frame([])
        check(identity.document.strokes.last?.points.count == 1, "轻点可保存为一个点")
        identity.undo()
        check(identity.document.strokes.count == 1 && identity.canRedo, "撤销移除最后一笔")
        identity.redo()
        check(identity.document.strokes.count == 2 && !identity.canRedo, "重做恢复笔画")
        identity.undo()
        identity.frame([finger(3, 0.2, 0.3)])
        check(!identity.canRedo, "撤销后重新书写会清除重做历史")
        identity.clear()
        check(identity.document.strokes.isEmpty && identity.pointer == nil && !identity.canUndo && !identity.canRedo, "清空重置笔迹和输入状态")

        let data = try! JSONEncoder().encode(ink.document)
        let restored = try! JSONDecoder().decode(InkDocument.self, from: data)
        check(restored.strokes.count == ink.document.strokes.count && restored.strokes[1].points == ink.document.strokes[1].points, "草稿序列化保留独立笔画和绝对坐标")
        check(InkPoint(-0.1, 1.3).clampedToUnit == InkPoint(0, 1), "触控设备坐标限制在有效范围")
        check(InkPoint(-2, 3.5).x == -2 && InkPoint(-2, 3.5).y == 3.5, "世界坐标允许向初始纸张四周扩展")

        func near(_ a: InkPoint, _ b: InkPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 1e-8 }
        var view = InkViewport()
        let anchor = InkPoint(0.23, 0.71)
        let anchorWorld = view.worldPoint(at: anchor)
        view.zoom(by: 3.7, around: anchor)
        check(near(view.worldPoint(at: anchor), anchorWorld), "缩放时锚点下的世界坐标保持不动")
        let testPoint = InkPoint(-0.8, 2.4)
        check(near(view.worldPoint(at: view.viewPoint(at: testPoint)), testPoint), "缩放前后坐标双向转换精确")
        let before = view.viewPoint(at: testPoint)
        view.pan(dx: 0.2, dy: -0.15)
        let after = view.viewPoint(at: testPoint)
        check(abs(after.x - before.x - 0.2) < 1e-8 && abs(after.y - before.y + 0.15) < 1e-8, "拖动距离准确且不随缩放倍率加速")
        view.zoom(by: 1e8, around: anchor)
        check(view.zoom == 16, "最大缩放限制为 1600%")
        view.zoom(by: 1e-12)
        check(view.zoom == 0.1, "最小缩放限制为 10%")
        let stable = view.zoom
        view.zoom(by: .nan)
        check(view.zoom == stable, "忽略无效缩放值")

        let initial = InkViewport(zoom: 2.4, center: InkPoint(1.2, -0.8))
        let firstPair = [finger(1, 0.3, 0.4), finger(2, 0.7, 0.4)]
        let gesture = NavigationGesture(viewport: initial, fingers: firstPair, aspect: 1.6)
        let secondPair = [finger(2, 0.9, 0.6), finger(1, 0.4, 0.6)]
        let moved = gesture.updated(secondPair)!
        check(abs(moved.zoom - 3) < 1e-8, "双指间距变化控制缩放且不受集合顺序影响")
        check(near(moved.worldPoint(at: InkPoint(0.65, 0.6)), initial.worldPoint(at: InkPoint(0.5, 0.4))), "双指平移与缩放可同时进行，锚点无漂移")
        check(gesture.updated([finger(1, 0.4, 0.6)]) == nil, "双指变为单指时结束导航计算")
        check(gesture.updated([finger(1, 0.4, 0.6), finger(3, 0.9, 0.6)]) == nil, "双指身份更换时重新建立手势基准")

        let force = InkEngine()
        force.lightTouchAssistance = false
        for i in 0...20 {
            force.frame([FingerSample(id: 1, point: InkPoint(Double(i) / 30, 0.5), pressure: Double(i) / 20, timestamp: Double(i) / 120)])
        }
        force.frame([])
        let factors = force.document.strokes[0].widthFactors!
        check(factors.last! > factors.first! * 3, "压力数值由轻到重，笔画显著增粗")
        check(zip(factors, factors.dropFirst()).allSatisfy { $0 <= $1 }, "逐渐加力时粗细平滑且单调增加")
        let unpressured = InkEngine(); unpressured.pressureEnabled = false
        for i in 0...10 { unpressured.frame([FingerSample(id: 1, point: InkPoint(Double(i) / 10, 0.4), pressure: Double(i) / 10)]) }
        check(unpressured.document.strokes[0].widthFactors!.allSatisfy { $0 == 1 }, "关闭压感后普通笔保持固定粗细")
        let stationary = InkEngine()
        stationary.frame([finger(1, 0.5, 0.5)])
        let initialFactor = stationary.document.strokes[0].widthFactors![0]
        stationary.updatePressure(1, timestamp: 0.1)
        check(stationary.document.strokes[0].points.count == 1 && stationary.document.strokes[0].widthFactors![0] > initialFactor, "手指不动时压力变化仍可增粗，不增加伪轨迹")

        func brushAtSpeed(_ elapsed: Double) -> Double {
            let ink = InkEngine(); ink.brush = .brush
            ink.frame([FingerSample(id: 1, point: InkPoint(0.1, 0.1), pressure: 0.6, timestamp: 1)])
            ink.frame([FingerSample(id: 1, point: InkPoint(0.3, 0.1), pressure: 0.6, timestamp: 1 + elapsed)])
            return ink.document.strokes[0].widthFactors!.last!
        }
        check(brushAtSpeed(0.01) < brushAtSpeed(1), "毛笔快速挥动比慢速运行更细")
        let prelude = InkEngine()
        prelude.frame([finger(1, 0.4, 0.4)])
        prelude.discardGesturePrelude(maxLength: 0.01)
        check(prelude.document.strokes.isEmpty, "双指先后落下时清除起始误触点")
        prelude.frame([finger(1, 0.1, 0.1)]); prelude.frame([finger(1, 0.7, 0.1)])
        prelude.discardGesturePrelude(maxLength: 0.01)
        check(prelude.document.strokes.count == 1, "进入双指手势时保留已经画好的长笔画")

        let legacy = #"{"aspect":1.6,"strokes":[{"points":[{"x":0.1,"y":0.2},{"x":0.4,"y":0.5}],"color":"graphite","width":0.004}]}"#.data(using: .utf8)!
        let legacyDoc = try! JSONDecoder().decode(InkDocument.self, from: legacy)
        check(legacyDoc.isValid && legacyDoc.strokes[0].brush == nil && legacyDoc.strokes[0].factor(at: 0) == 1, "旧版草稿可读取，原有等宽笔迹保持不变")
        var extendedDoc = force.document
        extendedDoc.viewport = moved
        extendedDoc.strokes.append(InkStroke(points: [InkPoint(-2, 3), InkPoint(4, -1)], color: .blue, width: 0.008))
        let roundtrip = try! JSONDecoder().decode(InkDocument.self, from: JSONEncoder().encode(extendedDoc))
        check(roundtrip.isValid && roundtrip.viewport!.zoom == moved.zoom && roundtrip.strokes[0].widthFactors == factors, "新版草稿保留压感细节、无限坐标与视窗状态")
        check(roundtrip.contentBounds.minX < -2 && roundtrip.contentBounds.maxX > 4 && roundtrip.contentBounds.maxY > 3, "作品边界包含屏幕外内容与笔画宽度")
        check(PressureResponse.normalized(0.02, sensitivity: 2) > 0.19, "轻微的 2% 原始压力已产生明显响应")
        check(PressureResponse.normalized(0.1, sensitivity: 2) > 0.57, "10% 原始压力可达到一半以上的响应范围")
        let pressureCurve = (0...1000).map { PressureResponse.normalized(Double($0) / 1000, sensitivity: 2) }
        check(pressureCurve.first == 0 && pressureCurve.last == 1 && zip(pressureCurve, pressureCurve.dropFirst()).allSatisfy { $0 < $1 }, "敏感曲线连续递增，保留完整压力范围")
        check(PressureResponse.normalized(0.05, sensitivity: 5) > PressureResponse.normalized(0.05, sensitivity: 0.5), "灵敏度滑块确实增强小压力响应")
        func lightStroke(elapsed: Double, zoom: Double = 1, enhanced: Bool = true) -> Double {
            let ink = InkEngine(); ink.lightTouchAssistance = enhanced
            ink.frame([FingerSample(id: 1, point: InkPoint(0.1 / zoom, 0.2 / zoom), timestamp: 1, inputPoint: InkPoint(0.1, 0.2))])
            for i in 1...30 {
                let x = 0.1 + Double(i) / 30 * 0.3
                ink.frame([FingerSample(id: 1, point: InkPoint(x / zoom, 0.2 / zoom), timestamp: 1 + Double(i) / 30 * elapsed, inputPoint: InkPoint(x, 0.2))])
            }
            return ink.document.strokes[0].widthFactors!.last!
        }
        check(lightStroke(elapsed: 1.2) > lightStroke(elapsed: 0.15) * 1.3, "不按下触控板，轻触增强也能随速度产生粗细变化")
        check(abs(lightStroke(elapsed: 0.5) - lightStroke(elapsed: 0.5, zoom: 8)) < 1e-10, "轻触粗细取决于真实手指速度，不受缩放倍率影响")
        check(lightStroke(elapsed: 1.2, enhanced: false) == lightStroke(elapsed: 0.15, enhanced: false), "纯压感下普通笔不混入速度辅助")
        func pressureAfter(_ hz: Int) -> Double {
            let ink = InkEngine(); ink.lightTouchAssistance = false
            ink.frame([FingerSample(id: 1, point: InkPoint(0.5, 0.5), timestamp: 1)])
            for i in 1...(hz / 5) { ink.updatePressure(0.05, timestamp: 1 + Double(i) / Double(hz)) }
            return ink.document.strokes[0].widthFactors![0]
        }
        check(abs(pressureAfter(60) - pressureAfter(120)) < 1e-10, "压力平滑按时间计算，60Hz 和 120Hz 的响应一致")
        let velocity = InkEngine()
        velocity.frame([FingerSample(id: 1, point: InkPoint(0.1, 0.1), timestamp: 1)])
        velocity.frame([FingerSample(id: 1, point: InkPoint(0.2, 0.1), timestamp: 1.01)])
        let fastFactor = velocity.document.strokes[0].widthFactors!.last!
        velocity.updatePressure(0, timestamp: 1.03)
        check(velocity.document.strokes[0].widthFactors!.last! <= fastFactor, "独立压力事件不会把移动速度错误重置为零")
        print("\(passed) checks passed.")
    }
}
