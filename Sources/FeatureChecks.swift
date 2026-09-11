import AppKit

extension AppDelegate {
    func runFeatureChecks(output: String) -> [String: Any] {
        var checks: [String: Any] = [:]
        let outputURL = URL(fileURLWithPath: output)
        func snapshot(_ view: NSView, _ name: String) {
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                var exported = bitmap
                if name == "palette.png", let source = bitmap.cgImage,
                   let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                   let context = NSGraphicsContext(bitmapImageRep: opaque)?.cgContext {
                    let rect = CGRect(x: 0, y: 0, width: opaque.pixelsWide, height: opaque.pixelsHigh)
                    context.setFillColor(NSColor.white.cgColor); context.fill(rect); context.draw(source, in: rect)
                    context.flush(); exported = opaque
                }
                try? exported.representation(using: .png, properties: [:])?.write(to: outputURL.appendingPathComponent(name))
            }
        }
        func exercise(_ surface: CanvasView, window: NSWindow, prefix: String, route: (NSEvent) -> NSEvent?) {
            surface.engine.clear(); surface.viewport = InkViewport(); surface.engine.tool = .pen
            surface.drawingMode = .holdToDraw; surface.engine.color = InkColor(rawValue: "#983DE0")!
            surface.engine.brush = .pen; surface.engine.width = 0.012
            func key(_ code: UInt16, _ type: NSEvent.EventType = .keyDown, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
                NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code)!
            }
            var time = 100.0
            func touch(_ id: Int?, _ x: Double = 0, _ y: Double = 0) {
                time += 0.02
                surface.processTouchFrame(id.map { [FingerSample(id: $0, point: InkPoint(x, y), timestamp: time)] } ?? [], timestamp: time)
            }
            checks[prefix + "DefaultHoldMode"] = surface.isWriting && surface.engine.preview && !surface.spacePressed
            checks[prefix + "PointerVisibleBeforeContact"] = surface.visiblePointer != nil && !surface.pointerIsLive
            touch(500, 0.25, 0.45); touch(nil)
            checks[prefix + "LiftKeepsReferenceWithoutLiveContact"] = surface.visiblePointer == InkPoint(0.25, 0.45) && surface.rawPointer == nil && !surface.pointerIsLive
            _ = route(key(49))
            checks[prefix + "SpaceInAirCannotDrawAtReference"] = surface.engine.document.strokes.isEmpty && surface.visiblePointer == InkPoint(0.25, 0.45)
            _ = route(key(49, .keyUp))
            touch(501, 0.2, 0.5); touch(501, 0.3, 0.5)
            checks[prefix + "HoverPreviewNoInk"] = surface.engine.document.strokes.isEmpty && surface.rawPointer == InkPoint(0.3, 0.5)
            checks[prefix + "NewContactUpdatesVisiblePointer"] = surface.visiblePointer == InkPoint(0.3, 0.5) && surface.pointerIsLive
            _ = route(key(49))
            checks[prefix + "SpaceStartsAtStationaryPreview"] = surface.engine.document.strokes.first?.points.first == InkPoint(0.3, 0.5)
            touch(501, 0.7, 0.5)
            _ = route(key(49, .keyUp)); touch(501, 0.8, 0.7)
            checks[prefix + "ReleaseStopsInkImmediately"] = surface.engine.preview && surface.engine.document.strokes.count == 1 && surface.engine.document.strokes[0].points.last == InkPoint(0.7, 0.5)
            _ = route(key(49)); touch(501, 0.75, 0.75); touch(nil)
            touch(502, 0.2, 0.2); touch(502, 0.45, 0.2); touch(nil)
            checks[prefix + "HeldSpaceAllowsSeparateStrokes"] = surface.engine.document.strokes.count == 3
            _ = route(key(49, .keyUp, flags: .control))
            checks[prefix + "ModifierKeyUpReleasesClutch"] = surface.engine.preview && !surface.spacePressed
            _ = route(key(49, repeatKey: true))
            checks[prefix + "RepeatDoesNotRearmClutch"] = surface.engine.preview
            _ = route(key(14))
            checks[prefix + "EHoldEntersEraser"] = surface.engine.tool == .eraser && !surface.engine.preview
            touch(503, 0.5, 0.35); touch(503, 0.5, 0.65); touch(nil)
            checks[prefix + "EraserMovesWithoutSpace"] = surface.engine.document.strokes.last?.eraser == true
            _ = route(key(6)); checks[prefix + "UndoEraser"] = surface.engine.document.strokes.count == 3
            _ = route(key(16)); checks[prefix + "RedoEraser"] = surface.engine.document.strokes.last?.eraser == true
            _ = route(key(14, .keyUp)); touch(504, 0.1, 0.1); touch(nil)
            checks[prefix + "EReleaseReturnsToPreview"] = surface.engine.preview && surface.engine.tool == .pen && surface.engine.document.strokes.count == 4
            _ = route(key(46)); touch(505, 0.15, 0.8); touch(nil)
            checks[prefix + "OptionalTouchModeDraws"] = surface.drawingMode == .touchToDraw && surface.engine.document.strokes.count == 5
            _ = route(key(49)); touch(506, 0.2, 0.8); touch(nil)
            checks[prefix + "OptionalModeSpacePreviews"] = surface.engine.preview && surface.engine.document.strokes.count == 5
            _ = route(key(49, .keyUp)); _ = route(key(46))
            touch(509, 0.65, 0.9)
            let beforePressure = surface.engine.document.strokes.count
            checks[prefix + "PressureModeInitiallyPreviews"] = surface.drawingMode == .pressToDraw && surface.engine.preview
            surface.processPressure(0.01, stage: 1, timestamp: time + 0.001)
            checks[prefix + "BelowPressureThresholdNoInk"] = surface.engine.document.strokes.count == beforePressure
            surface.processPressure(0.20, stage: 1, timestamp: time + 0.002)
            checks[prefix + "PressureStartsAtPreviewPoint"] = surface.engine.document.strokes.last?.points.first == surface.viewport.worldPoint(at: InkPoint(0.65, 0.9))
            touch(509, 0.75, 0.9)
            surface.processPressure(0, stage: 0, timestamp: time + 0.003)
            touch(509, 0.85, 0.9)
            checks[prefix + "PressureReleaseStopsInk"] = surface.engine.preview && surface.engine.document.strokes.count == beforePressure + 1 && surface.engine.document.strokes.last?.points.last == surface.viewport.worldPoint(at: InkPoint(0.75, 0.9))
            _ = route(key(49)); surface.processPressure(0.5, stage: 1, timestamp: time + 0.004)
            checks[prefix + "PressureSpacePausesInk"] = surface.engine.preview && surface.engine.document.strokes.count == beforePressure + 1
            surface.processPressure(0, stage: 0, timestamp: time + 0.005)
            touch(nil); _ = route(key(49, .keyUp)); _ = route(key(46))
            checks[prefix + "ModeCycleReturnsToDefault"] = surface.drawingMode == .holdToDraw && surface.engine.preview
            let beforePalette = surface.engine.document.strokes.count
            _ = route(key(40))
            checks[prefix + "KOpensPaletteReleasesCursor"] = NSColorPanel.shared.isVisible && !surface.isWriting && !surface.cursorHidden && !surface.cursorDetached
            NSColorPanel.shared.color = prefix == "board" ? NSColor(srgbRed: 0.95, green: 0.45, blue: 0.12, alpha: 1) : NSColor(srgbRed: 0.12, green: 0.75, blue: 0.62, alpha: 1)
            palettePanel.colorChanged(NSColorPanel.shared)
            let picked = surface.engine.color
            checks[prefix + "PaletteDoesNotDrawOrRecordUnusedColor"] = surface.engine.document.strokes.count == beforePalette && !preferences.recent.colors.contains(where: { $0.rgb == picked.rgb })
            let undoItem = NSApp.mainMenu!.items.flatMap { $0.submenu?.items ?? [] }.first { $0.action == #selector(undoStroke) }!
            checks[prefix + "PaletteDisablesCanvasMenuShortcuts"] = !validateMenuItem(undoItem)
            if prefix == "board" { snapshot(NSColorPanel.shared.contentView!, "palette.png") }
            palettePanel.finishPicking()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            checks[prefix + "PaletteDoneResumesPreview"] = surface.isWriting && surface.engine.preview && !surface.spacePressed
            touch(507, 0.65, 0.3); _ = route(key(49)); touch(507, 0.85, 0.4); touch(nil); _ = route(key(49, .keyUp))
            checks[prefix + "DrawRecordsCustomColor"] = preferences.recent.colors.first?.rgb == picked.rgb && surface.engine.document.strokes.last?.color == picked
            if !surface.desktopSurface {
                surface.viewport.zoom(by: 4)
                _ = route(key(14)); touch(508, 0.5, 0.5)
                let visibleWidth = surface.engine.eraserWidth * surface.paperRect.width * surface.viewport.zoom
                checks[prefix + "EraserKeepsScreenSizeWhenZoomed"] = abs(visibleWidth - surface.eraserDiameter) < 0.01
                touch(nil); _ = route(key(14, .keyUp)); surface.resetViewport()
            }
            let displayDocument = surface.engine.document
            let displayColor = surface.engine.color
            for mode in DrawingMode.allCases {
                surface.drawingMode = mode
                let before = surface.engine.document.strokes.count
                _ = route(key(14)); touch(601, 0.4, 0.6); touch(601, 0.45, 0.6)
                _ = route(key(14, repeatKey: true))
                checks[prefix + mode.rawValue + "ERepeatStaysMomentary"] = surface.eraserHeld && surface.engine.tool == .eraser && surface.engine.document.strokes.count == before + 1
                _ = route(key(14, .keyUp, flags: .control))
                let eraserPoints = surface.engine.document.strokes.last?.points
                touch(601, 0.55, 0.6)
                checks[prefix + mode.rawValue + "EReleaseStopsWithoutExtraInk"] = !surface.eraserHeld && surface.engine.tool == .pen && surface.engine.preview && surface.engine.document.strokes.count == before + 1 && surface.engine.document.strokes.last?.points == eraserPoints
                touch(nil)
                checks[prefix + mode.rawValue + "EReleasePreservesInputMode"] = surface.drawingMode == mode && surface.engine.preview == (mode != .touchToDraw)
            }
            surface.drawingMode = .holdToDraw
            let countBeforeTap = surface.engine.document.strokes.count
            _ = route(key(14)); _ = route(key(14, .keyUp)); touch(602, 0.7, 0.6); touch(nil)
            checks[prefix + "ETapDoesNotLatchOrErase"] = !surface.eraserHeld && surface.engine.preview && surface.engine.document.strokes.count == countBeforeTap
            _ = route(key(49)); _ = route(key(14)); touch(603, 0.6, 0.6)
            _ = route(key(14, .keyUp)); touch(603, 0.62, 0.6)
            checks[prefix + "EReleaseKeepsSpaceStateButWaitsForLift"] = surface.spacePressed && surface.engine.preview && !surface.eraserHeld
            touch(nil); touch(604, 0.64, 0.6)
            checks[prefix + "PenResumesAfterLiftWithSpaceHeld"] = !surface.engine.preview && surface.engine.document.strokes.last?.eraser != true
            touch(nil); _ = route(key(49, .keyUp))
            _ = route(key(14)); touch(605, 0.4, 0.4); _ = route(key(49)); _ = route(key(49, .keyUp))
            checks[prefix + "SpaceReleaseDoesNotCancelHeldE"] = surface.eraserHeld && surface.engine.tool == .eraser
            _ = route(key(14, .keyUp)); touch(nil)
            _ = route(key(14)); _ = route(key(40))
            checks[prefix + "FocusLossCancelsHeldE"] = !surface.isWriting && !surface.eraserHeld && surface.engine.tool == .pen
            palettePanel.finishPicking()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            _ = route(key(14, repeatKey: true))
            checks[prefix + "ERepeatAfterFocusLossCannotRearm"] = surface.isWriting && !surface.eraserHeld && surface.engine.preview
            _ = route(key(14, .keyUp))
            func holdButton(in view: NSView) -> HoldEraserButton? {
                if let button = view as? HoldEraserButton { return button }
                return view.subviews.compactMap { holdButton(in: $0) }.first
            }
            let controlsRoot = surface.desktopSurface ? desktop.toolbar.contentView! : window.contentView!
            if let button = holdButton(in: controlsRoot), let buttonWindow = button.window {
                let original = button.onHold
                var transitions: [Bool] = []
                button.onHold = { held in transitions.append(held); original?(held) }
                let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time, windowNumber: buttonWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                // App-local event queue only: release outside the button's bounds.
                let up = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: time + 0.01, windowNumber: buttonWindow.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
                NSApp.postEvent(up, atStart: true)
                button.mouseDown(with: down)
                button.onHold = original
                checks[prefix + "ToolbarReleaseOutsideDoesNotLatch"] = transitions == [true, false] && !surface.eraserHeld && surface.engine.tool == .pen
            } else { checks[prefix + "ToolbarReleaseOutsideDoesNotLatch"] = false }
            surface.engine.clear(); surface.drawingMode = .holdToDraw; surface.engine.color = .graphite
            let black = InkStroke(points: [InkPoint(0.44, 0.5), InkPoint(0.56, 0.5)], color: InkColor(rawValue: "#000000")!, width: 0.1)
            surface.engine.document.strokes = [black]
            touch(606, 0.5, 0.5)
            func cursorColors() -> (light: Int, dark: Int) {
                guard let rep = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) else { return (0, 0) }
                surface.cacheDisplay(in: surface.bounds, to: rep)
                let sx = Double(rep.pixelsWide) / surface.bounds.width, sy = Double(rep.pixelsHigh) / surface.bounds.height
                let centerX = surface.paperRect.midX * sx, centerY = surface.paperRect.midY * sy
                var light = 0, dark = 0
                for y in Int(centerY - 19 * sy)...Int(centerY + 19 * sy) {
                    for x in Int(centerX - 19 * sx)...Int(centerX + 19 * sx) {
                        if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                            if c.alphaComponent > 0.8 && min(c.redComponent, c.greenComponent, c.blueComponent) > 0.8 { light += 1 }
                            if c.alphaComponent > 0.8 && max(c.redComponent, c.greenComponent, c.blueComponent) < 0.2 { dark += 1 }
                        }
                    }
                }
                return (light, dark)
            }
            checks[prefix + "CursorVisibleOverSolidBlackInk"] = cursorColors().light > 20
            snapshot(surface, prefix + "-cursor-dark.png")
            surface.engine.document.strokes = []
            checks[prefix + "CursorVisibleOverLightOrTransparentBackground"] = cursorColors().dark > 20
            touch(nil)
            checks[prefix + "IdlePointerVisibleOverLightOrTransparentBackground"] = cursorColors().dark > 20 && !surface.pointerIsLive
            snapshot(surface, prefix + "-cursor-lifted.png")
            surface.engine.document.strokes = [black]
            checks[prefix + "IdlePointerVisibleOverSolidBlackInk"] = cursorColors().light > 20
            snapshot(surface, prefix + "-cursor-lifted-dark.png")
            surface.engine.document.strokes = []
            touch(607, 0.48, 0.5)
            surface.processTouchFrame([], ended: [FingerSample(id: 607, point: InkPoint(0.5, 0.5), timestamp: time + 0.01)], timestamp: time + 0.01)
            checks[prefix + "LiftUsesFinalPreviewEndpointWithoutInk"] = surface.visiblePointer == InkPoint(0.5, 0.5) && !surface.pointerIsLive && surface.engine.document.strokes.isEmpty
            let reference = surface.visiblePointer
            let pair = [FingerSample(id: 608, point: InkPoint(0.2, 0.3)), FingerSample(id: 609, point: InkPoint(0.7, 0.6))]
            surface.processTouchFrame(pair, timestamp: time + 0.02)
            surface.processTouchFrame([pair[0]], timestamp: time + 0.03)
            checks[prefix + "NavigationKeepsReferenceWithoutLivePen"] = surface.visiblePointer == reference && !surface.pointerIsLive && surface.engine.document.strokes.isEmpty
            touch(nil)
            surface.zoom(by: 2)
            checks[prefix + "ZoomKeepsPointerAtSameScreenPosition"] = surface.visiblePointer == reference
            surface.resetViewport()
            _ = route(key(14))
            checks[prefix + "EraserInAirKeepsReferenceWithoutErasing"] = surface.visiblePointer == reference && surface.engine.document.strokes.isEmpty
            _ = route(key(14, .keyUp))
            surface.engine.clear(); surface.engine.document = displayDocument; surface.engine.color = displayColor
            surface.stopWriting()
            checks[prefix + "PauseHidesReferenceAndRestoresSystemCursor"] = surface.visiblePointer == nil && !surface.cursorHidden && !surface.cursorDetached
            surface.startWriting()
            checks[prefix + "ResumeKeepsReferenceBeforeContact"] = surface.visiblePointer == reference && !surface.pointerIsLive
            surface.stopWriting()
        }

        preferences.mode = .holdToDraw
        canvas.drawingMode = preferences.mode
        window.setContentSize(NSSize(width: 1180, height: 830)); window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded(); canvas.startWriting()
        exercise(canvas, window: window, prefix: "board", route: handleKeyboard)
        snapshot(window.contentView!, "tools-demo.png")
        window.setContentSize(NSSize(width: 1000, height: 612)); window.contentView?.layoutSubtreeIfNeeded()
        snapshot(window.contentView!, "tools-minimum.png")
        let controls = window.contentView!.subviews.filter { $0 is NSStackView }.flatMap { ($0 as! NSStackView).arrangedSubviews }
        checks["toolControlsFitMinimumWindow"] = controls.allSatisfy { view in
            view.isHidden || window.contentView!.bounds.insetBy(dx: -1, dy: -1).contains(view.convert(view.bounds, to: window.contentView!))
        }
        // Persistent preference roundtrip in an isolated suite, never personal settings.
        let suite = "io.github.zkalan.inkdeck.test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let saved = InkPreferences(persistent: true, defaults: defaults)
        saved.mode = .touchToDraw; saved.record(InkColor(rawValue: "#123ABC")!)
        let loaded = InkPreferences(persistent: true, defaults: defaults)
        checks["preferencesSurviveReload"] = loaded.mode == .touchToDraw && loaded.recent.colors.first?.rawValue == "#123ABC"
        defaults.removePersistentDomain(forName: suite)

        toggleDesktop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let boardColor = canvas.engine.color
        desktop.pause()
        checks["menuBarOneClickResumesPausedDesktop"] = quickResumeDesktop() && desktop.canvas.isWriting && !desktop.overlay.ignoresMouseEvents
        checks["menuBarResumeDoesNotToggleActiveDrawing"] = !quickResumeDesktop() && desktop.canvas.isWriting
        exercise(desktop.canvas, window: desktop.overlay, prefix: "desktopTool", route: desktop.handleKeyboard)
        checks["recentColorsSharedAcrossSurfaces"] = preferences.recent.colors.contains { $0.rgb == boardColor.rgb } && preferences.recent.colors.first?.rgb == desktop.canvas.engine.color.rgb
        snapshot(desktop.toolbar.contentView!, "desktop-tools.png")
        desktop.finish()
        checks["menuBarResumeDoesNothingOutsideDesktop"] = !quickResumeDesktop()
        checks["toolsExitRestoresCursor"] = !desktop.canvas.cursorDetached && !desktop.canvas.cursorHidden && !canvas.cursorDetached && !canvas.cursorHidden

        // Pixel-level rendering: local erasure, transparent overlay, later ink, undo and reload.
        func bitmap(_ doc: InkDocument, background: NSColor?) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            if let background { context.setFillColor(background.cgColor); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600)) }
            context.scaleBy(x: 600, y: 600)
            InkRenderer().draw(doc, activeStroke: nil, in: context)
            context.flush(); return rep
        }
        var doc = InkDocument(strokes: [InkStroke(points: [InkPoint(0.1, 0.5), InkPoint(0.9, 0.5)], color: .blue, width: 0.04)], aspect: 1)
        let erase = InkStroke(points: [InkPoint(0.5, 0.3), InkPoint(0.5, 0.7)], color: .graphite, width: 0.10, eraser: true)
        doc.strokes.append(erase)
        let transparent = bitmap(doc, background: nil)
        checks["eraserClearsOnlyLocalInk"] = transparent.colorAt(x: 300, y: 300)!.alphaComponent < 0.01 && transparent.colorAt(x: 120, y: 300)!.alphaComponent > 0.99
        let background = bitmap(doc, background: .systemYellow)
        let center = background.colorAt(x: 300, y: 300)!.usingColorSpace(.sRGB)!
        let yellow = NSColor.systemYellow.usingColorSpace(.sRGB)!
        checks["eraserPreservesUnderlyingBackground"] = abs(center.redComponent - yellow.redComponent) < 0.02 && abs(center.blueComponent - yellow.blueComponent) < 0.02
        doc.strokes.removeLast()
        checks["undoErasureRestoresVisibleInk"] = bitmap(doc, background: nil).colorAt(x: 300, y: 300)!.alphaComponent > 0.99
        doc.strokes.append(erase)
        doc.strokes.append(InkStroke(points: [InkPoint(0.3, 0.5), InkPoint(0.7, 0.5)], color: InkColor(rawValue: "#FF0000")!, width: 0.015))
        let restored = try! JSONDecoder().decode(InkDocument.self, from: JSONEncoder().encode(doc))
        let final = bitmap(restored, background: nil)
        let red = final.colorAt(x: 300, y: 300)!.usingColorSpace(.sRGB)!
        checks["newInkCanCrossErasedAreaAfterReload"] = red.redComponent > 0.99 && red.greenComponent < 0.01 && red.alphaComponent > 0.99
        try? final.representation(using: .png, properties: [:])?.write(to: outputURL.appendingPathComponent("eraser-pixels.png"))
        return checks
    }
}
