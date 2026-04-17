//
//  ContentView.swift
//  Scratchpad
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine
import QuartzCore

struct ContentView: View {
    let fileURL: URL?

    @StateObject private var doc = DocumentModel()
    @StateObject private var input = TrackpadInputManager()
    @Environment(\.undoManager) private var envUndoManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppSettings.drawingPressureThresholdKey)
    private var drawingPressureThreshold = AppSettings.defaultDrawingPressureThreshold
    @AppStorage(AppSettings.keyboardPanSensitivityKey)
    private var keyboardPanSensitivity = AppSettings.defaultKeyboardPanSensitivity
    @AppStorage(AppSettings.twoFingerDoubleTapUndoEnabledKey)
    private var twoFingerDoubleTapUndoEnabled = AppSettings.defaultTwoFingerDoubleTapUndoEnabled

    @State private var viewportSize: CGSize = .zero
    @State private var activeTouchIDs: Set<Int32> = []
    @State private var palmRejectedTouchIDs: Set<Int32> = []
    @State private var previousContactTouchIDs: Set<Int32> = []
    @State private var twoFingerTapCandidate: TwoFingerTapCandidate?
    @State private var lastTwoFingerTapAt: TimeInterval?
    @State private var dragSessionAccum: CGSize = .zero
    @State private var scrollMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var keyUpMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var mouseDownMonitor: Any?
    @State private var editingTextID: UUID?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedTick: Int = 0
    @State private var panZoomActiveUntil: Date = .distantPast
    @State private var cursorHidden: Bool = false
    @State private var cmdHeld: Bool = false
    @State private var hostWindow: NSWindow?
    @State private var isConvertingLatex: Bool = false
    @State private var latexErrorMessage: String?
    /// Screen-space rect we play the diffusion overlay over. Captured at the
    /// moment a conversion begins so the overlay stays anchored even after
    /// `replaceStrokes` swaps selection to the new LaTeX item.
    @State private var latexAnimationRect: CGRect?
    @State private var latexAnimationClearTask: Task<Void, Never>?
    @State private var activePanDirections: Set<PanDirection> = []
    @State private var keyboardPanVelocity: CGSize = .zero
    @State private var keyboardPanTask: Task<Void, Never>?

    private struct TwoFingerTapCandidate {
        let startedAt: TimeInterval
        let startLocations: [Int32: CGPoint]
        var maxTravel: CGFloat
    }

    private enum PanDirection: Hashable {
        case left, right, up, down
    }

    var body: some View {
        ZStack(alignment: .top) {
            canvasBody

            InteractionLayer(
                doc: doc,
                isTextEditing: editingTextID != nil,
                onInteractionBegin: resignFirstResponder
            )
            .zIndex(5)

            DiffusionOverlay(rect: latexAnimationRect)
                .zIndex(6)

            if let actionRect = selectionActionRect {
                SelectionContextMenu(
                    rect: actionRect,
                    isBusy: isConvertingLatex,
                    mode: selectionActionMode,
                    selectionKey: AnyHashable(doc.selection),
                    onConvert: convertSelectionToLatex,
                    onCopyLatex: copySelectedLatex,
                    onRevertToHandwriting: revertSelectedLatex
                )
                .zIndex(8)
            }

            ToolbarView(
                doc: doc,
                onHome: openHome,
                onExport: { exportDocument(format: $0) },
                onNewDocument: newDocument,
                onClear: confirmClear,
                cmdHeld: cmdHeld
            )
            .frame(maxWidth: 900)
            .padding(.top, 10)
            .padding(.horizontal, 14)
            .zIndex(10)
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert("LaTeX Conversion Failed", isPresented: Binding(
            get: { latexErrorMessage != nil },
            set: { if !$0 { latexErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { latexErrorMessage = nil }
        } message: {
            Text(latexErrorMessage ?? "")
        }
        .background(
            WindowAccessor { window in
                hostWindow = window
            }
        )
        .onAppear {
            input.start()
            installMonitors()
            loadIfNeeded()
        }
        .onDisappear {
            input.stop()
            stopKeyboardPan()
            removeMonitors()
            saveNow()
            showCursor()
        }
        .onChange(of: input.touches) { _, newTouches in
            handleTouches(newTouches)
        }
        .onChange(of: doc.modificationTick) { _, newTick in
            scheduleAutosave(tick: newTick)
        }
        .onChange(of: envUndoManager) { _, m in
            doc.undoManager = m
        }
        .onChange(of: doc.isDrawingModeActive) { _, active in
            if active { hideCursor() } else { showCursor() }
        }
        .onChange(of: doc.tool) { _, _ in
            if editingTextID != nil {
                editingTextID = nil
                resignFirstResponder()
            }
        }
    }

    // MARK: - Canvas stack

    private var canvasBody: some View {
        GeometryReader { proxy in
            ZStack {
                DotGridBackground(
                    paperStyle: doc.paperStyle,
                    canvasStyle: doc.canvasStyle,
                    panOffset: doc.panOffset,
                    zoom: doc.zoom,
                    pageCount: doc.pageCount
                )

                if doc.canvasStyle == .page {
                    addPageButton(in: proxy.size)
                        .zIndex(3)
                }

                StrokesLayer(
                    strokes: doc.strokes,
                    liveStrokes: doc.liveStrokes,
                    panOffset: doc.panOffset,
                    zoom: doc.zoom
                )

                ItemsLayer(
                    items: doc.items,
                    panOffset: doc.panOffset,
                    zoom: doc.zoom,
                    selection: doc.selection,
                    editingTextID: editingTextID,
                    onEditText: updateTextItem,
                    onEndTextEditing: { editingTextID = nil }
                )

                if doc.tool.canDraw {
                    let rect = surfaceScreenRect(in: proxy.size)
                    TrackpadSurfaceView(
                        doc: doc,
                        input: input,
                        screenRect: rect,
                        activeTouchIDs: activeTouchIDs,
                        palmRejectedTouchIDs: palmRejectedTouchIDs,
                        hideIndicator: panZoomActive,
                        onDragChanged: { translation in
                            let dx = translation.width - dragSessionAccum.width
                            let dy = translation.height - dragSessionAccum.height
                            doc.surfaceScreenOffset.width += dx
                            doc.surfaceScreenOffset.height += dy
                            dragSessionAccum = translation
                        },
                        onDragEnded: {
                            dragSessionAccum = .zero
                        }
                    )
                    .position(x: rect.midX, y: rect.midY)
                }
            }
            .onAppear { viewportSize = proxy.size }
            .onChange(of: proxy.size) { _, s in viewportSize = s }
        }
    }

    private var panZoomActive: Bool {
        Date() < panZoomActiveUntil
    }

    // MARK: - Coordinate math

    private func surfaceScreenRect(in size: CGSize) -> CGRect {
        let w = doc.surfaceSize.width
        let h = doc.surfaceSize.height
        let cx = size.width / 2 + doc.surfaceScreenOffset.width
        let cy = size.height / 2 + doc.surfaceScreenOffset.height
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    private func screenToDocument(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let cx = size.width / 2 + doc.panOffset.width
        let cy = size.height / 2 + doc.panOffset.height
        return CGPoint(x: (p.x - cx) / doc.zoom, y: (p.y - cy) / doc.zoom)
    }

    private func touchToDocumentPoint(_ t: NormalizedTouch) -> CGPoint {
        let size = viewportSize
        let rect = surfaceScreenRect(in: size)
        let screenPoint = CGPoint(
            x: rect.minX + t.x * rect.width,
            y: rect.minY + t.y * rect.height
        )
        return screenToDocument(screenPoint, in: size)
    }

    private func documentToScreenRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        let cx = size.width / 2 + doc.panOffset.width
        let cy = size.height / 2 + doc.panOffset.height
        return CGRect(
            x: cx + rect.origin.x * doc.zoom,
            y: cy + rect.origin.y * doc.zoom,
            width: rect.width * doc.zoom,
            height: rect.height * doc.zoom
        )
    }

    private var selectionActionRect: CGRect? {
        guard !doc.selection.isEmpty, viewportSize != .zero else { return nil }
        if doc.hasConvertibleInkSelection || doc.selectedLatexItem != nil {
            return documentToScreenRect(doc.selectionBounds, in: viewportSize)
        }
        return nil
    }

    private var selectionActionMode: SelectionContextMenu.Mode {
        if doc.selectedLatexItem != nil {
            return .renderedLatex
        }
        return .inkSelection
    }

    private func applyZoom(factor: CGFloat, anchor: CGPoint, in size: CGSize) {
        let newZoom = max(0.25, min(6.0, doc.zoom * factor))
        if newZoom == doc.zoom { return }
        let cx = size.width / 2
        let cy = size.height / 2
        let dx = anchor.x - (cx + doc.panOffset.width)
        let dy = anchor.y - (cy + doc.panOffset.height)
        let scale = newZoom / doc.zoom
        doc.panOffset.width += dx - dx * scale
        doc.panOffset.height += dy - dy * scale
        doc.zoom = newZoom
    }

    // MARK: - Touch → stroke routing

    private func handleTouches(_ touches: [NormalizedTouch]) {
        let contactTouches = touches.filter(\.isContact)
        updatePalmRejectedTouches(using: contactTouches)
        let drawableTouches = contactTouches.filter { !palmRejectedTouchIDs.contains($0.id) }
        processTwoFingerDoubleTapUndo(drawableTouches)

        guard doc.isDrawingModeActive, doc.tool.canDraw else {
            endActiveTouches()
            return
        }

        guard drawableTouches.count == 1 else {
            endActiveTouches()
            return
        }

        let t = drawableTouches[0]
        let shouldDraw = shouldDraw(for: t)

        if !shouldDraw {
            endActiveTouches()
            return
        }

        let p = touchToDocumentPoint(t)

        if activeTouchIDs.contains(t.id) {
            doc.extendStroke(id: t.id, to: p, pressure: t.pressure, timestamp: t.timestamp)
        } else {
            for id in activeTouchIDs where id != t.id {
                doc.endStroke(id: id)
            }
            activeTouchIDs = [t.id]
            doc.beginStroke(id: t.id, at: p, pressure: t.pressure, timestamp: t.timestamp)
        }
    }

    private func shouldDraw(for touch: NormalizedTouch) -> Bool {
        if activeTouchIDs.contains(touch.id) {
            return touch.pressure >= AppSettings.releaseThreshold(from: drawingPressureThreshold)
        }
        return touch.pressure >= AppSettings.beginThreshold(from: drawingPressureThreshold)
    }

    private func endActiveTouches() {
        for id in activeTouchIDs {
            doc.endStroke(id: id)
        }
        activeTouchIDs.removeAll()
    }

    private func updatePalmRejectedTouches(using contactTouches: [NormalizedTouch]) {
        let activeIDs = Set(contactTouches.map(\.id))
        palmRejectedTouchIDs.formIntersection(activeIDs)

        for touch in contactTouches where isDefinitelyPalm(touch) {
            palmRejectedTouchIDs.insert(touch.id)
        }

        guard contactTouches.count > 1 else { return }

        let drawableTouches = contactTouches.filter { !palmRejectedTouchIDs.contains($0.id) }
        guard drawableTouches.count > 1 else { return }

        let anchorTouch: NormalizedTouch
        if let activeID = activeTouchIDs.first,
           let activeTouch = drawableTouches.first(where: { $0.id == activeID }) {
            anchorTouch = activeTouch
        } else {
            anchorTouch = drawableTouches.min { lhs, rhs in
                if lhs.contactArea == rhs.contactArea {
                    return lhs.total < rhs.total
                }
                return lhs.contactArea < rhs.contactArea
            } ?? drawableTouches[0]
        }

        for touch in drawableTouches where touch.id != anchorTouch.id {
            if isLikelyPalm(touch, comparedTo: anchorTouch) {
                palmRejectedTouchIDs.insert(touch.id)
            }
        }
    }

    private func isDefinitelyPalm(_ touch: NormalizedTouch) -> Bool {
        let edgeBias = palmEdgeBias(for: touch)

        if edgeBias >= 0.92 && touch.contactArea >= 0.12 {
            return true
        }
        if edgeBias >= 0.88 && touch.contactArea >= 0.08 {
            return true
        }
        if edgeBias >= 0.82 && touch.total >= 0.5 && touch.contactArea >= 0.045 {
            return true
        }

        return false
    }

    private func isLikelyPalm(_ touch: NormalizedTouch, comparedTo anchor: NormalizedTouch) -> Bool {
        let areaRatio = touch.contactArea / max(anchor.contactArea, 0.001)
        let totalRatio = touch.total / max(anchor.total, 0.001)
        let densityRatio = touch.density / max(anchor.density, 0.001)
        let edgeBias = palmEdgeBias(for: touch)

        if edgeBias >= 0.65 && (areaRatio >= 1.3 || totalRatio >= 1.45) {
            return true
        }
        if areaRatio >= 1.9 || totalRatio >= 2.1 {
            return true
        }
        if areaRatio >= 1.55 && densityRatio <= 0.9 {
            return true
        }
        if edgeBias >= 0.45 && areaRatio >= 1.2 && touch.axisRatio >= 2.4 {
            return true
        }

        return false
    }

    private func palmEdgeBias(for touch: NormalizedTouch) -> CGFloat {
        let bottomBias = max(0, (touch.y - 0.78) / 0.22)
        let leftBias = max(0, (0.08 - touch.x) / 0.08)
        let rightBias = max(0, (touch.x - 0.92) / 0.08)
        let topBias = max(0, (0.05 - touch.y) / 0.05)
        return max(bottomBias, leftBias, rightBias, topBias * 0.5)
    }

    private func processTwoFingerDoubleTapUndo(_ contactTouches: [NormalizedTouch]) {
        guard twoFingerDoubleTapUndoEnabled else {
            twoFingerTapCandidate = nil
            previousContactTouchIDs = Set(contactTouches.map(\.id))
            return
        }

        let contactIDs = Set(contactTouches.map(\.id))
        let now = contactTouches.map(\.timestamp).max() ?? CACurrentMediaTime()

        if contactTouches.count == 2 {
            if previousContactTouchIDs != contactIDs || twoFingerTapCandidate == nil {
                twoFingerTapCandidate = TwoFingerTapCandidate(
                    startedAt: now,
                    startLocations: Dictionary(uniqueKeysWithValues: contactTouches.map {
                        ($0.id, CGPoint(x: $0.x, y: $0.y))
                    }),
                    maxTravel: 0
                )
            } else if var candidate = twoFingerTapCandidate {
                let travel = contactTouches.compactMap { touch -> CGFloat? in
                    guard let start = candidate.startLocations[touch.id] else { return nil }
                    let dx = touch.x - start.x
                    let dy = touch.y - start.y
                    return sqrt(dx * dx + dy * dy)
                }.max() ?? 0
                candidate.maxTravel = max(candidate.maxTravel, travel)
                twoFingerTapCandidate = candidate
            }
        } else if previousContactTouchIDs.count == 2 {
            if let candidate = twoFingerTapCandidate,
               isTwoFingerTap(candidate, endedAt: now) {
                if let lastTapAt = lastTwoFingerTapAt, now - lastTapAt <= 0.35 {
                    envUndoManager?.undo()
                    lastTwoFingerTapAt = nil
                } else {
                    lastTwoFingerTapAt = now
                }
            }
            twoFingerTapCandidate = nil
        } else if contactTouches.count > 2 {
            twoFingerTapCandidate = nil
        }

        previousContactTouchIDs = contactIDs
    }

    private func isTwoFingerTap(_ candidate: TwoFingerTapCandidate, endedAt now: TimeInterval) -> Bool {
        now - candidate.startedAt <= 0.22 && candidate.maxTravel <= 0.035
    }

    private func updateTextItem(_ id: UUID, _ text: String) {
        guard let idx = doc.items.firstIndex(where: { $0.id == id }) else { return }
        var item = doc.items[idx]
        if case .text(var content) = item.kind {
            content.text = text
            item.kind = .text(content)
            let fitHeight = fittedTextHeight(
                text: text,
                fontSize: content.fontSize,
                width: max(item.frame.width - 8, 1)
            )
            let minHeight = max(32, content.fontSize * 1.6)
            item.frame.size.height = max(minHeight, fitHeight + 8)
            doc.updateItem(item, registerUndo: false)
        }
    }

    // MARK: - Cursor
    //
    // When drawing mode engages we warp the cursor to the middle of the app
    // window, then decouple the mouse from the cursor so any inadvertent
    // movement doesn't carry it off-screen (where an alt-tab or menu-bar
    // interaction would steal focus). Drawing uses trackpad touches, not the
    // mouse, so freezing the cursor is safe. When drawing mode exits we
    // re-couple the two.
    private func hideCursor() {
        if cursorHidden { return }
        warpCursorToWindowCenter()
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
        cursorHidden = true
    }

    private func showCursor() {
        if !cursorHidden { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        cursorHidden = false
    }

    private func warpCursorToWindowCenter() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let frame = window.frame
        // Global display coordinates are top-origin; AppKit window coords are
        // bottom-origin, so flip using the primary screen height.
        let screenHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let center = CGPoint(x: frame.midX, y: screenHeight - frame.midY)
        CGWarpMouseCursorPosition(center)
    }

    private func resignFirstResponder() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func convertSelectionToLatex() {
        let selectedStrokes = doc.selectedStrokes
        guard doc.hasConvertibleInkSelection, !selectedStrokes.isEmpty, !isConvertingLatex else { return }

        isConvertingLatex = true
        let strokeIDs = Set(selectedStrokes.map(\.id))
        let originalBounds = doc.combinedBounds(strokes: selectedStrokes, items: [])
        let renderColor = selectedStrokes.last?.color ?? CodableColor(.primary)

        // Capture the selection rect in screen space so the diffusion overlay
        // stays put even after `replaceStrokes` moves the selection to the
        // newly created LaTeX item.
        startLatexAnimation(screenRect: documentToScreenRect(originalBounds, in: viewportSize))

        Task {
            do {
                let latex = try await Task.detached(priority: .userInitiated) {
                    try await MLXTexoService.shared.recognize(strokes: selectedStrokes)
                }.value

                let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw TexoMLXError.emptyPrediction
                }

                let render = try await LatexRenderer.shared.renderPNG(latex: trimmed, color: renderColor)
                _ = doc.replaceStrokes(
                    ids: strokeIDs,
                    withLatex: trimmed,
                    renderedPNGData: render.data,
                    originalBounds: originalBounds
                )
            } catch {
                latexErrorMessage = error.localizedDescription
            }
            isConvertingLatex = false
            // Hold the diffusion overlay briefly after the swap so the new
            // LaTeX appears to resolve out of the flash instead of snapping in.
            scheduleLatexAnimationEnd(after: 0.35)
        }
    }

    private func copySelectedLatex() {
        guard let item = doc.selectedLatexItem,
              case .latex(let content) = item.kind,
              !content.latex.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content.latex, forType: .string)
    }

    private func revertSelectedLatex() {
        guard let item = doc.selectedLatexItem else { return }

        let screenRect = documentToScreenRect(item.frame, in: viewportSize)
        startLatexAnimation(screenRect: screenRect)

        // Delay the actual swap slightly so the diffusion flash is visible
        // before the strokes pop back. Revert is synchronous, unlike convert,
        // so without this the animation wouldn't register.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            _ = doc.revertLatexItemToStrokes(id: item.id)
            scheduleLatexAnimationEnd(after: 0.30)
        }
    }

    // MARK: - LaTeX diffusion animation

    private func startLatexAnimation(screenRect: CGRect) {
        latexAnimationClearTask?.cancel()
        latexAnimationClearTask = nil
        latexAnimationRect = screenRect
    }

    private func scheduleLatexAnimationEnd(after seconds: TimeInterval) {
        latexAnimationClearTask?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            latexAnimationRect = nil
        }
        latexAnimationClearTask = task
    }

    // MARK: - Page layout overlay

    @ViewBuilder
    private func addPageButton(in size: CGSize) -> some View {
        let lastIndex = max(0, doc.pageCount - 1)
        let origin = DotGridBackground.pageDocOrigin(lastIndex)
        let pageH = DotGridBackground.pageSize.height
        let pageW = DotGridBackground.pageSize.width
        let cx = size.width / 2 + doc.panOffset.width
        let cy = size.height / 2 + doc.panOffset.height
        // Bottom-center of the last page in screen space.
        let sx = cx + (origin.x + pageW / 2) * doc.zoom
        let sy = cy + (origin.y + pageH) * doc.zoom + 14

        Button {
            doc.addPage()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add Page")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .position(x: sx, y: sy)
        .help("Add a new page below")
    }

    // MARK: - Keyboard + scroll monitoring

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isEventInHostWindow(event) else { return event }
            return handleKeyDown(event)
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            guard isEventInHostWindow(event) else { return event }
            return handleKeyUp(event)
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            guard isEventInHostWindow(event) else { return event }
            let nextCmd = event.modifierFlags.contains(.command)
            if nextCmd != cmdHeld { cmdHeld = nextCmd }
            if nextCmd { stopKeyboardPan() }
            return event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            guard isEventInHostWindow(event), let window = event.window else { return event }
            let contentView = window.contentView
            let locWindow = event.locationInWindow
            if let contentView, contentView.bounds.contains(contentView.convert(locWindow, from: nil)) {
                let anchor = contentPoint(in: contentView, fromWindowPoint: locWindow)
                if event.type == .scrollWheel {
                    panZoomActiveUntil = Date().addingTimeInterval(0.4)
                    if event.modifierFlags.contains(.command) {
                        let factor = 1 + (event.scrollingDeltaY * 0.01)
                        applyZoom(factor: factor, anchor: anchor, in: viewportSize)
                    } else {
                        doc.panOffset.width += event.scrollingDeltaX
                        doc.panOffset.height += event.scrollingDeltaY
                    }
                    return nil
                }
                if event.type == .magnify {
                    panZoomActiveUntil = Date().addingTimeInterval(0.4)
                    applyZoom(factor: 1 + event.magnification, anchor: anchor, in: viewportSize)
                    return nil
                }
            }
            return event
        }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window, let contentView = window.contentView else { return event }
            guard isEventInHostWindow(event) else { return event }
            let locContent = contentView.convert(event.locationInWindow, from: nil)
            guard contentView.bounds.contains(locContent) else { return event }
            let point = contentPoint(in: contentView, fromWindowPoint: event.locationInWindow)
            let docPoint = screenToDocument(point, in: viewportSize)

            // While editing text in Text tool, clicking outside the text content
            // should blur immediately (including selection edge/handle region).
            if doc.tool == .text, let editingID = editingTextID {
                if !isPointInsideTextContent(docPoint, itemID: editingID) {
                    editingTextID = nil
                    resignFirstResponder()
                }
            }

            guard event.clickCount == 2 else { return event }
            guard doc.tool == .text, !doc.isDrawingModeActive else { return event }
            createTextBox(at: docPoint, switchTool: true)
            return nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53, editingTextID != nil {
            stopKeyboardPan()
            editingTextID = nil
            resignFirstResponder()
            return nil
        }

        // Typing into a text field — let everything through.
        if editingTextID != nil { return event }

        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()

        if !cmd, let direction = panDirection(for: event) {
            activePanDirections.insert(direction)
            startKeyboardPan(boosted: shift)
            return nil
        }

        // ⌘1..6 — select corresponding tool
        if cmd, let digit = Int(chars), digit >= 1, digit <= ToolKind.allCases.count {
            doc.tool = ToolKind.allCases[digit - 1]
            return nil
        }

        if cmd, chars == "d" {
            stopKeyboardPan()
            doc.isDrawingModeActive.toggle()
            return nil
        }
        if event.keyCode == 53 {
            stopKeyboardPan()
            if doc.isDrawingModeActive { doc.isDrawingModeActive = false; return nil }
            if !doc.selection.isEmpty { doc.selection.removeAll(); return nil }
            return event
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if !doc.selection.isEmpty { doc.deleteSelection(); return nil }
            return event
        }
        if cmd, chars == "z" {
            if shift { envUndoManager?.redo() } else { envUndoManager?.undo() }
            return nil
        }
        if cmd, chars == "y" { envUndoManager?.redo(); return nil }
        if cmd, chars == "c" { doc.copySelection(); return nil }
        if cmd, chars == "x" { doc.cutSelection(); return nil }
        if cmd, chars == "v" {
            doc.pasteFromClipboard()
            return nil
        }
        if cmd, chars == "a" {
            doc.selection = Set(doc.items.map(\.id)).union(doc.strokes.map(\.id))
            return nil
        }
        if cmd, chars == "s" {
            saveNow()
            return nil
        }
        return event
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        if let direction = panDirection(for: event) {
            activePanDirections.remove(direction)
            if activePanDirections.isEmpty {
                stopKeyboardPan()
            }
            return nil
        }
        return event
    }

    private func panDirection(for event: NSEvent) -> PanDirection? {
        switch event.keyCode {
        case 123:
            return .left
        case 124:
            return .right
        case 125:
            return .down
        case 126:
            return .up
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            return .left
        case "d":
            return .right
        case "w":
            return .up
        case "s":
            return .down
        default:
            return nil
        }
    }

    private func startKeyboardPan(boosted: Bool) {
        guard keyboardPanTask == nil else { return }

        let baseSpeed = CGFloat(keyboardPanSensitivity) * (boosted ? 14 : 8)
        let maxSpeed = baseSpeed * 4.2
        let acceleration = baseSpeed * 10
        let deceleration = baseSpeed * 14

        keyboardPanTask = Task { @MainActor in
            var lastTime = CACurrentMediaTime()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { break }

                let now = CACurrentMediaTime()
                let dt = CGFloat(now - lastTime)
                lastTime = now
                guard dt > 0 else { continue }

                let axis = panAxisVector()
                let hasInput = axis != .zero

                keyboardPanVelocity.width = approach(
                    current: keyboardPanVelocity.width,
                    target: axis.width * maxSpeed,
                    rate: hasInput ? acceleration : deceleration,
                    dt: dt
                )
                keyboardPanVelocity.height = approach(
                    current: keyboardPanVelocity.height,
                    target: axis.height * maxSpeed,
                    rate: hasInput ? acceleration : deceleration,
                    dt: dt
                )

                if hasInput ||
                    abs(keyboardPanVelocity.width) > 0.1 ||
                    abs(keyboardPanVelocity.height) > 0.1 {
                    doc.panOffset.width += keyboardPanVelocity.width * dt
                    doc.panOffset.height += keyboardPanVelocity.height * dt
                    panZoomActiveUntil = Date().addingTimeInterval(0.12)
                } else {
                    keyboardPanVelocity = .zero
                    keyboardPanTask = nil
                    break
                }
            }
        }
    }

    private func stopKeyboardPan() {
        activePanDirections.removeAll()
        keyboardPanTask?.cancel()
        keyboardPanTask = nil
        keyboardPanVelocity = .zero
    }

    private func panAxisVector() -> CGSize {
        var dx: CGFloat = 0
        var dy: CGFloat = 0

        if activePanDirections.contains(.left) { dx += 1 }
        if activePanDirections.contains(.right) { dx -= 1 }
        if activePanDirections.contains(.up) { dy += 1 }
        if activePanDirections.contains(.down) { dy -= 1 }

        if dx != 0, dy != 0 {
            let scale = CGFloat(1 / sqrt(2.0))
            dx *= scale
            dy *= scale
        }

        return CGSize(width: dx, height: dy)
    }

    private func approach(current: CGFloat, target: CGFloat, rate: CGFloat, dt: CGFloat) -> CGFloat {
        let delta = target - current
        let step = rate * dt
        if abs(delta) <= step {
            return target
        }
        return current + step * (delta > 0 ? 1 : -1)
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m); keyUpMonitor = nil }
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
    }

    private func isEventInHostWindow(_ event: NSEvent) -> Bool {
        guard let hostWindow else { return false }
        if let eventWindow = event.window {
            return eventWindow == hostWindow
        }
        return hostWindow.isKeyWindow
    }

    private func contentPoint(in view: NSView, fromWindowPoint point: CGPoint) -> CGPoint {
        let local = view.convert(point, from: nil)
        let y = view.isFlipped ? local.y : (view.bounds.height - local.y)
        return CGPoint(x: local.x, y: y)
    }

    private func isPointInsideTextContent(_ p: CGPoint, itemID: UUID) -> Bool {
        guard let item = doc.items.first(where: { $0.id == itemID }) else { return false }
        guard case .text = item.kind else { return false }
        let insetX = min(6, max(1, item.frame.width * 0.45))
        let insetY = min(6, max(1, item.frame.height * 0.45))
        let contentRect = item.frame.insetBy(dx: insetX, dy: insetY)
        return contentRect.contains(p)
    }

    private func createTextBox(at point: CGPoint, switchTool: Bool) {
        let rect = CGRect(
            x: point.x,
            y: point.y,
            width: 220,
            height: max(32, doc.textFontSize * 1.6)
        )
        let item = CanvasItem(
            frame: rect,
            kind: .text(.init(
                text: "",
                fontSize: doc.textFontSize,
                color: CodableColor(doc.color)
            ))
        )
        doc.addItem(item)
        doc.selection = [item.id]
        if switchTool {
            doc.tool = .text
        }
        DispatchQueue.main.async {
            editingTextID = item.id
        }
    }

    private func fittedTextHeight(text: String, fontSize: CGFloat, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let sample = text.isEmpty ? " " : text
        let rect = NSAttributedString(string: sample, attributes: attrs).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }

    // MARK: - File lifecycle

    private func loadIfNeeded() {
        doc.undoManager = envUndoManager
        if let url = fileURL {
            if let file = try? Persistence.load(from: url) {
                doc.load(from: file, url: url)
                lastSavedTick = doc.modificationTick
            } else {
                doc.fileURL = url
            }
        } else {
            doc.fileURL = Persistence.newAutosaveURL(title: doc.title)
        }
    }

    private func scheduleAutosave(tick: Int) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            saveNow()
        }
    }

    private func saveNow() {
        guard doc.modificationTick != lastSavedTick else { return }
        guard let url = doc.fileURL else { return }
        try? Persistence.save(doc.snapshot(), to: url)
        lastSavedTick = doc.modificationTick
    }

    // MARK: - Commands

    private func openHome() {
        openWindow(id: "home")
    }

    private func newDocument() {
        saveNow()
        let name = NameGenerator.next()
        let url = Persistence.newAutosaveURL(title: name)
        let empty = ScratchpadFile(
            title: name,
            paperStyle: doc.paperStyle,
            strokes: [],
            items: []
        )
        try? Persistence.save(empty, to: url)
        openWindow(value: url)
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear this scratchpad?"
        alert.informativeText = "All strokes, shapes, text, and images will be removed. You can undo this with ⌘Z."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            doc.clearAll()
        }
    }

    // MARK: - Export

    private func exportDocument(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = doc.title
        switch format {
        case .png:
            panel.title = "Export as PNG"
            panel.allowedContentTypes = [.png]
        case .pdf:
            panel.title = "Export as PDF"
            panel.allowedContentTypes = [.pdf]
        case .scratchpad:
            panel.title = "Export Scratchpad"
            let scratch = UTType(filenameExtension: ScratchpadDocType.ext) ?? .json
            panel.allowedContentTypes = [scratch]
        }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            switch format {
            case .png:
                if let data = renderPNG() { try? data.write(to: url) }
            case .pdf:
                if let data = renderPDF() { try? data.write(to: url) }
            case .scratchpad:
                try? Persistence.save(doc.snapshot(), to: url)
            }
        }
    }

    @MainActor
    private func renderPNG() -> Data? {
        let size = viewportSize == .zero ? CGSize(width: 1920, height: 1080) : viewportSize
        let renderer = ImageRenderer(content: exportContent(size: size))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    private func renderPDF() -> Data? {
        let size = viewportSize == .zero ? CGSize(width: 1920, height: 1080) : viewportSize
        let renderer = ImageRenderer(content: exportContent(size: size))
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: pdfData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        renderer.render { sz, draw in
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: 0, y: sz.height)
            ctx.scaleBy(x: 1, y: -1)
            draw(ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return pdfData as Data
    }

    @MainActor
    private func exportContent(size: CGSize) -> some View {
        ZStack {
            DotGridBackground(
                paperStyle: doc.paperStyle,
                canvasStyle: doc.canvasStyle,
                panOffset: doc.panOffset,
                zoom: doc.zoom,
                pageCount: doc.pageCount
            )
            StrokesLayer(
                strokes: doc.strokes,
                liveStrokes: [:],
                panOffset: doc.panOffset,
                zoom: doc.zoom
            )
            ItemsLayer(
                items: doc.items,
                panOffset: doc.panOffset,
                zoom: doc.zoom,
                selection: [],
                editingTextID: nil,
                onEditText: { _, _ in },
                onEndTextEditing: {}
            )
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window {
                onResolve(w)
                w.titleVisibility = .hidden
                w.titlebarAppearsTransparent = true
                w.styleMask.insert(.fullSizeContentView)
                w.isMovableByWindowBackground = false
                w.backgroundColor = .windowBackgroundColor
                let minContent = CGSize(width: 1200, height: 780)
                if w.frame.size.width < minContent.width || w.frame.size.height < minContent.height {
                    var f = w.frame
                    let screenFrame = w.screen?.visibleFrame ?? .zero
                    f.size.width = max(f.size.width, minContent.width)
                    f.size.height = max(f.size.height, minContent.height)
                    f.origin.x = screenFrame.midX - f.size.width / 2
                    f.origin.y = screenFrame.midY - f.size.height / 2
                    w.setFrame(f, display: true, animate: false)
                }
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView(fileURL: nil)
        .frame(width: 1200, height: 780)
}
