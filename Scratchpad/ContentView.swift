//
//  ContentView.swift
//  Scratchpad
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    let fileURL: URL?

    @StateObject private var doc = DocumentModel()
    @StateObject private var input = TrackpadInputManager()
    @Environment(\.undoManager) private var envUndoManager
    @Environment(\.openWindow) private var openWindow

    @State private var viewportSize: CGSize = .zero
    @State private var activeTouchIDs: Set<Int32> = []
    @State private var dragSessionAccum: CGSize = .zero
    @State private var scrollMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var mouseDownMonitor: Any?
    @State private var editingTextID: UUID?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedTick: Int = 0
    @State private var panZoomActiveUntil: Date = .distantPast
    @State private var cursorHidden: Bool = false
    @State private var cmdHeld: Bool = false
    @State private var hostWindow: NSWindow?

    var body: some View {
        ZStack(alignment: .top) {
            canvasBody

            InteractionLayer(
                doc: doc,
                isTextEditing: editingTextID != nil,
                onBeginTextEdit: { editingTextID = $0 },
                onInteractionBegin: resignFirstResponder
            )
            .zIndex(5)

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
        let shouldDraw = doc.isDrawingModeActive
            && doc.tool.canDraw
            && contactTouches.count == 1

        if !shouldDraw {
            for id in activeTouchIDs {
                doc.endStroke(id: id)
            }
            activeTouchIDs.removeAll()
            return
        }

        let t = contactTouches[0]
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

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            guard isEventInHostWindow(event) else { return event }
            let nextCmd = event.modifierFlags.contains(.command)
            if nextCmd != cmdHeld { cmdHeld = nextCmd }
            return event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            guard isEventInHostWindow(event), let window = event.window else { return event }
            let contentView = window.contentView
            let locWindow = event.locationInWindow
            if let contentView, contentView.bounds.contains(contentView.convert(locWindow, from: nil)) {
                let locContent = contentView.convert(locWindow, from: nil)
                let anchor = CGPoint(x: locContent.x, y: contentView.bounds.height - locContent.y)
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
            let point = CGPoint(x: locContent.x, y: contentView.bounds.height - locContent.y)
            let docPoint = screenToDocument(point, in: viewportSize)

            // While editing text in Text tool, clicking outside the text content
            // should blur immediately (including selection edge/handle region).
            if doc.tool == .text, let editingID = editingTextID {
                if !isPointInsideTextContent(docPoint, itemID: editingID) {
                    editingTextID = nil
                    resignFirstResponder()
                }
                return event
            }

            guard event.clickCount == 2 else { return event }
            guard doc.tool == .select, editingTextID == nil else { return event }
            guard let textID = textItemID(at: docPoint) else { return event }
            doc.selection = [textID]
            doc.tool = .text
            DispatchQueue.main.async {
                editingTextID = textID
            }
            return nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53, editingTextID != nil {
            editingTextID = nil
            resignFirstResponder()
            return nil
        }

        // Typing into a text field — let everything through.
        if editingTextID != nil { return event }

        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let chars = event.charactersIgnoringModifiers ?? ""

        // ⌘1..6 — select corresponding tool
        if cmd, let digit = Int(chars), digit >= 1, digit <= ToolKind.allCases.count {
            doc.tool = ToolKind.allCases[digit - 1]
            return nil
        }

        if cmd, chars == "d" {
            doc.isDrawingModeActive.toggle()
            return nil
        }
        if event.keyCode == 53 {
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

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
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

    private func textItemID(at p: CGPoint) -> UUID? {
        for item in doc.items.reversed() {
            if case .text = item.kind, item.frame.insetBy(dx: -4, dy: -4).contains(p) {
                return item.id
            }
        }
        return nil
    }

    private func isPointInsideTextContent(_ p: CGPoint, itemID: UUID) -> Bool {
        guard let item = doc.items.first(where: { $0.id == itemID }) else { return false }
        guard case .text = item.kind else { return false }
        let insetX = min(6, max(1, item.frame.width * 0.45))
        let insetY = min(6, max(1, item.frame.height * 0.45))
        let contentRect = item.frame.insetBy(dx: insetX, dy: insetY)
        return contentRect.contains(p)
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
