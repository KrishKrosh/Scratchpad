//
//  DocumentModel.swift
//  Scratchpad
//

import Foundation
import SwiftUI
import Combine
import AppKit

/// Serializable document payload. Everything on disk lives here.
struct ScratchpadFile: Codable {
    var title: String
    var paperStyle: PaperStyle
    var canvasStyle: CanvasStyle = .infinite
    var selectMode: SelectMode = .rectangle
    /// Number of stacked pages in `.page` mode. Infinite canvas ignores this.
    var pageCount: Int = 1
    var strokes: [Stroke]
    var items: [CanvasItem]
    /// Document-space origin for the view to restore.
    var panOffset: CGSize = .zero
    var zoom: CGFloat = 1.0
    var createdAt: Date = .init()
    var modifiedAt: Date = .init()
}

/// The app/document state. Mutations that need to be undoable go through
/// `perform(_:undo:)`, which wires to NSUndoManager.
@MainActor
final class DocumentModel: ObservableObject {

    // MARK: Identity / file URL
    @Published var fileURL: URL?

    // MARK: Metadata
    @Published var title: String = NameGenerator.next()
    @Published var paperStyle: PaperStyle = .dots
    @Published var canvasStyle: CanvasStyle = .infinite
    @Published var selectMode: SelectMode = .rectangle
    /// Number of stacked pages when `canvasStyle == .page`. Clamped to >= 1.
    @Published var pageCount: Int = 1

    // MARK: Content
    @Published private(set) var strokes: [Stroke] = []
    @Published var liveStrokes: [Int32: Stroke] = [:]
    @Published private(set) var items: [CanvasItem] = []

    // MARK: Selection (across items and strokes — UUIDs are unique)
    @Published var selection: Set<UUID> = []

    // MARK: Tool state
    @Published var tool: ToolKind = .pen {
        didSet {
            // Leaving/entering a non-draw tool exits drawing mode.
            if !tool.canDraw { isDrawingModeActive = false }
            if tool != .shape { shapeKind = shapeKind } // no-op, keeps menu
        }
    }
    @Published var color: Color = Color(red: 0.32, green: 0.24, blue: 0.94)
    @Published var lineWidth: CGFloat = 2.5
    @Published var highlighterWidth: CGFloat = 18
    @Published var eraserWidth: CGFloat = 22
    @Published var textFontSize: CGFloat = 18
    @Published var shapeKind: ShapeKind = .rectangle
    @Published var shapeStrokeWidth: CGFloat = 2.0

    // MARK: Canvas transform
    @Published var panOffset: CGSize = .zero
    @Published var zoom: CGFloat = 1.0

    // MARK: Surface (screen-fixed)
    @Published var surfaceSize: CGSize = CGSize(width: 560, height: 360)
    @Published var surfaceScreenOffset: CGSize = .zero

    // MARK: Drawing mode
    @Published var isDrawingModeActive: Bool = false

    let palette: [Color] = [
        .black,
        Color(red: 0.32, green: 0.24, blue: 0.94),
        Color(red: 0.90, green: 0.23, blue: 0.36),
        Color(red: 0.97, green: 0.64, blue: 0.20),
        Color(red: 0.22, green: 0.74, blue: 0.44),
        Color(red: 0.14, green: 0.52, blue: 0.95),
        Color(red: 0.60, green: 0.35, blue: 0.95)
    ]

    /// Receives undo registrations. Set by the hosting view.
    weak var undoManager: UndoManager?

    // MARK: - Stroke building (not undoable per-point; only the finished stroke)

    func beginStroke(id: Int32, at point: CGPoint, pressure: CGFloat, timestamp: TimeInterval) {
        let stroke = Stroke(
            points: [StrokePoint(location: point, pressure: pressure, timestamp: timestamp)],
            color: tool == .eraser ? .white : color,
            width: toolWidth(),
            tool: tool,
            opacity: tool == .highlighter ? 0.35 : 1.0
        )
        liveStrokes[id] = stroke
    }

    func extendStroke(id: Int32, to point: CGPoint, pressure: CGFloat, timestamp: TimeInterval) {
        guard var stroke = liveStrokes[id] else { return }
        stroke.points.append(StrokePoint(location: point, pressure: pressure, timestamp: timestamp))
        liveStrokes[id] = stroke
    }

    func endStroke(id: Int32) {
        guard let stroke = liveStrokes.removeValue(forKey: id) else { return }
        guard stroke.points.count > 1 else { return }
        if stroke.tool == .eraser {
            applyEraser(stroke)
        } else {
            addStroke(stroke, registerUndo: true)
        }
    }

    func cancelStroke(id: Int32) {
        liveStrokes.removeValue(forKey: id)
    }

    private func toolWidth() -> CGFloat {
        switch tool {
        case .highlighter: highlighterWidth
        case .eraser:      eraserWidth
        default:           lineWidth
        }
    }

    // MARK: - Undoable mutations

    private func addStroke(_ stroke: Stroke, registerUndo: Bool) {
        strokes.append(stroke)
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                target.removeStroke(id: stroke.id, registerUndo: true)
            }
            undoManager?.setActionName("Draw")
        }
        bumpModified()
    }

    private func removeStroke(id: UUID, registerUndo: Bool) {
        guard let idx = strokes.firstIndex(where: { $0.id == id }) else { return }
        let removed = strokes.remove(at: idx)
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                target.addStroke(removed, registerUndo: true)
            }
        }
        selection.remove(id)
        bumpModified()
    }

    func addItem(_ item: CanvasItem, registerUndo: Bool = true) {
        items.append(item)
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                target.removeItem(id: item.id, registerUndo: true)
            }
            undoManager?.setActionName("Add \(itemActionName(item))")
        }
        bumpModified()
    }

    func removeItem(id: UUID, registerUndo: Bool = true) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                target.addItem(removed, registerUndo: true)
            }
        }
        selection.remove(id)
        bumpModified()
    }

    func updateItem(_ new: CanvasItem, registerUndo: Bool = true) {
        guard let idx = items.firstIndex(where: { $0.id == new.id }) else { return }
        let old = items[idx]
        items[idx] = new
        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                target.updateItem(old, registerUndo: true)
            }
        }
        bumpModified()
    }

    /// Translate the currently-selected items and strokes by dx,dy in document space.
    /// Groups a whole drag into a single undoable action by supplying the same
    /// `transactionID` across calls; only the first/last registration are kept.
    func translateSelection(dx: CGFloat, dy: CGFloat) {
        if dx == 0 && dy == 0 { return }
        for id in selection {
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].frame = items[i].frame.offsetBy(dx: dx, dy: dy)
            }
            if let i = strokes.firstIndex(where: { $0.id == id }) {
                strokes[i].points = strokes[i].points.map {
                    StrokePoint(location: CGPoint(x: $0.location.x + dx,
                                                  y: $0.location.y + dy),
                                pressure: $0.pressure,
                                timestamp: $0.timestamp)
                }
            }
        }
        bumpModified()
    }

    // MARK: - Property edits on selection (undoable)

    /// Change the color of every selected stroke AND the color field of every
    /// selected text item / shape item. Registered as a single undo.
    func applyColorToSelection(_ new: Color) {
        guard !selection.isEmpty else { return }
        let cc = CodableColor(new)
        var strokeOlds: [(UUID, CodableColor)] = []
        var itemOlds: [(UUID, CanvasItem)] = []
        for id in selection {
            if let i = strokes.firstIndex(where: { $0.id == id }) {
                strokeOlds.append((id, strokes[i].color))
                strokes[i].color = cc
            }
            if let i = items.firstIndex(where: { $0.id == id }) {
                itemOlds.append((id, items[i]))
                switch items[i].kind {
                case .text(var content):
                    content.color = cc
                    items[i].kind = .text(content)
                case .shape(let kind, _, let w):
                    items[i].kind = .shape(kind, cc, w)
                case .image: break
                }
            }
        }
        guard !strokeOlds.isEmpty || !itemOlds.isEmpty else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            for (id, old) in strokeOlds {
                if let i = target.strokes.firstIndex(where: { $0.id == id }) {
                    target.strokes[i].color = old
                }
            }
            for (id, old) in itemOlds {
                if let i = target.items.firstIndex(where: { $0.id == id }) {
                    target.items[i] = old
                }
            }
            target.bumpModified()
        }
        undoManager?.setActionName("Change Color")
        bumpModified()
    }

    /// Change the width of every selected stroke or shape-item line width.
    func applyWidthToSelection(_ new: CGFloat) {
        guard !selection.isEmpty else { return }
        var strokeOlds: [(UUID, CGFloat)] = []
        var itemOlds: [(UUID, CanvasItem)] = []
        for id in selection {
            if let i = strokes.firstIndex(where: { $0.id == id }) {
                strokeOlds.append((id, strokes[i].width))
                strokes[i].width = new
            }
            if let i = items.firstIndex(where: { $0.id == id }) {
                if case .shape(let kind, let color, _) = items[i].kind {
                    itemOlds.append((id, items[i]))
                    items[i].kind = .shape(kind, color, new)
                }
            }
        }
        guard !strokeOlds.isEmpty || !itemOlds.isEmpty else { return }
        undoManager?.registerUndo(withTarget: self) { target in
            for (id, old) in strokeOlds {
                if let i = target.strokes.firstIndex(where: { $0.id == id }) {
                    target.strokes[i].width = old
                }
            }
            for (id, old) in itemOlds {
                if let i = target.items.firstIndex(where: { $0.id == id }) {
                    target.items[i] = old
                }
            }
            target.bumpModified()
        }
        undoManager?.setActionName("Change Width")
        bumpModified()
    }

    /// Scale the whole selection around the stationary `anchor` in doc space.
    /// Used by corner-resize handles. Not undo-registered directly —
    /// `registerResizeUndo` wraps the whole drag as one action.
    func scaleSelection(sx: CGFloat, sy: CGFloat, anchor: CGPoint) {
        guard !selection.isEmpty, sx.isFinite, sy.isFinite else { return }
        for id in selection {
            if let i = items.firstIndex(where: { $0.id == id }) {
                let f = items[i].frame
                var nextFrame = CGRect(
                    x: anchor.x + (f.origin.x - anchor.x) * sx,
                    y: anchor.y + (f.origin.y - anchor.y) * sy,
                    width: max(2, f.width * sx),
                    height: max(2, f.height * sy)
                )
                // Text resizing should preserve font size and keep the box
                // tall enough to fit wrapped content.
                if case .text(let content) = items[i].kind {
                    let fitHeight = Self.fittedTextHeight(
                        text: content.text,
                        fontSize: content.fontSize,
                        width: max(nextFrame.width - 8, 1)
                    )
                    let minHeight = max(32, content.fontSize * 1.6)
                    nextFrame.size.height = max(nextFrame.height, minHeight, fitHeight + 8)
                }
                items[i].frame = nextFrame
            }
            if let i = strokes.firstIndex(where: { $0.id == id }) {
                strokes[i].points = strokes[i].points.map {
                    StrokePoint(
                        location: CGPoint(
                            x: anchor.x + ($0.location.x - anchor.x) * sx,
                            y: anchor.y + ($0.location.y - anchor.y) * sy
                        ),
                        pressure: $0.pressure,
                        timestamp: $0.timestamp
                    )
                }
                strokes[i].width = max(0.5, strokes[i].width * ((abs(sx) + abs(sy)) / 2))
            }
        }
        bumpModified()
    }

    /// Register a single undo for a resize that has already been applied.
    func registerResizeUndo(sx: CGFloat, sy: CGFloat, anchor: CGPoint, ids: Set<UUID>) {
        guard sx != 1 || sy != 1 else { return }
        let invX = sx == 0 ? 1 : 1 / sx
        let invY = sy == 0 ? 1 : 1 / sy
        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            guard let self else { return }
            let prev = self.selection
            self.selection = ids
            target.scaleSelection(sx: invX, sy: invY, anchor: anchor)
            target.registerResizeUndo(sx: invX, sy: invY, anchor: anchor, ids: ids)
            self.selection = prev
        }
        undoManager?.setActionName("Resize")
    }

    /// Register a single undo for a move that has already been applied in place.
    func registerMoveUndo(totalDx: CGFloat, totalDy: CGFloat, ids: Set<UUID>) {
        guard totalDx != 0 || totalDy != 0 else { return }
        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            guard let self else { return }
            let prevSelection = self.selection
            self.selection = ids
            target.translateSelection(dx: -totalDx, dy: -totalDy)
            target.registerMoveUndo(totalDx: -totalDx, totalDy: -totalDy, ids: ids)
            self.selection = prevSelection
        }
        undoManager?.setActionName("Move")
    }

    // MARK: - Selection-level actions

    /// Delete everything in the current selection (strokes + items).
    func deleteSelection() {
        guard !selection.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for id in selection {
            if items.contains(where: { $0.id == id }) { removeItem(id: id) }
            if strokes.contains(where: { $0.id == id }) { removeStroke(id: id, registerUndo: true) }
        }
        undoManager?.setActionName("Delete")
        undoManager?.endUndoGrouping()
        selection.removeAll()
    }

    /// Append one more page in `.page` mode (undoable).
    func addPage() {
        let before = pageCount
        pageCount = before + 1
        undoManager?.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            self.removePage(restoringCount: before)
        }
        undoManager?.setActionName("Add Page")
        bumpModified()
    }

    private func removePage(restoringCount: Int) {
        let before = pageCount
        pageCount = max(1, restoringCount)
        undoManager?.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            self.pageCount = before
            self.bumpModified()
        }
        bumpModified()
    }

    func clearAll() {
        undoManager?.beginUndoGrouping()
        for s in strokes { removeStroke(id: s.id, registerUndo: true) }
        for i in items { removeItem(id: i.id, registerUndo: true) }
        undoManager?.setActionName("Clear")
        undoManager?.endUndoGrouping()
    }

    // MARK: - Cut / Copy / Paste
    //
    // We use a custom pasteboard type so multiple selected objects can round-trip.

    static let pasteboardType = NSPasteboard.PasteboardType("com.krishkrosh.scratchpad.selection")

    struct ClipboardPayload: Codable {
        var strokes: [Stroke]
        var items: [CanvasItem]
    }

    func copySelection() {
        let pb = NSPasteboard.general
        let payload = buildClipboardPayload()
        guard !payload.strokes.isEmpty || !payload.items.isEmpty else { return }
        pb.clearContents()
        if let data = try? JSONEncoder().encode(payload) {
            pb.setData(data, forType: Self.pasteboardType)
        }
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    /// Paste strokes/items from our own pasteboard type, OR an image from NSPasteboard.
    func pasteFromClipboard(at docPoint: CGPoint? = nil) {
        let pb = NSPasteboard.general

        // 1) Our own payload.
        if let data = pb.data(forType: Self.pasteboardType),
           let payload = try? JSONDecoder().decode(ClipboardPayload.self, from: data) {
            applyPaste(payload, at: docPoint)
            return
        }

        // 2) An image on the pasteboard.
        if let imageData = imageDataFromPasteboard(pb) {
            pasteImage(data: imageData, at: docPoint)
            return
        }

        NSSound.beep()
    }

    private func imageDataFromPasteboard(_ pb: NSPasteboard) -> Data? {
        if let data = pb.data(forType: .png) { return data }
        if let data = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: data) {
            return rep.representation(using: .png, properties: [:])
        }
        if let objs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = objs.first,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    /// Drop in a clipboard payload, offset so the centroid lands at `docPoint`
    /// (or just nudge it a bit from the originals).
    private func applyPaste(_ payload: ClipboardPayload, at docPoint: CGPoint?) {
        let srcBounds = combinedBounds(strokes: payload.strokes, items: payload.items)
        let target = docPoint ?? CGPoint(x: srcBounds.midX + 20, y: srcBounds.midY + 20)
        let dx = target.x - srcBounds.midX
        let dy = target.y - srcBounds.midY

        undoManager?.beginUndoGrouping()
        var newSelection: Set<UUID> = []
        for var s in payload.strokes {
            let newID = UUID()
            s.id = newID
            s.points = s.points.map {
                StrokePoint(location: CGPoint(x: $0.location.x + dx, y: $0.location.y + dy),
                            pressure: $0.pressure, timestamp: $0.timestamp)
            }
            addStroke(s, registerUndo: true)
            newSelection.insert(newID)
        }
        for var i in payload.items {
            i.id = UUID()
            i.frame = i.frame.offsetBy(dx: dx, dy: dy)
            addItem(i, registerUndo: true)
            newSelection.insert(i.id)
        }
        selection = newSelection
        undoManager?.setActionName("Paste")
        undoManager?.endUndoGrouping()
    }

    private func pasteImage(data: Data, at docPoint: CGPoint?) {
        guard let img = NSImage(data: data) else { return }
        let s = img.size
        let maxSide: CGFloat = 400
        let scale = min(maxSide / max(s.width, 1), maxSide / max(s.height, 1), 1)
        let w = s.width * scale
        let h = s.height * scale
        let center = docPoint ?? .zero
        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        let item = CanvasItem(frame: rect, kind: .image(data))
        addItem(item)
        undoManager?.setActionName("Paste Image")
        selection = [item.id]
    }

    private func buildClipboardPayload() -> ClipboardPayload {
        let s = strokes.filter { selection.contains($0.id) }
        let i = items.filter { selection.contains($0.id) }
        return ClipboardPayload(strokes: s, items: i)
    }

    // MARK: - Helpers

    private func itemActionName(_ item: CanvasItem) -> String {
        switch item.kind {
        case .text: return "Text"
        case .shape: return "Shape"
        case .image: return "Image"
        }
    }

    private func applyEraser(_ eraser: Stroke) {
        let eraserBounds = eraser.bounds
        undoManager?.beginUndoGrouping()
        let toRemove = strokes.filter { stroke in
            guard stroke.bounds.intersects(eraserBounds) else { return false }
            let r2 = (eraser.width * 0.5) * (eraser.width * 0.5)
            for ep in eraser.points {
                for sp in stroke.points {
                    let dx = ep.location.x - sp.location.x
                    let dy = ep.location.y - sp.location.y
                    if dx * dx + dy * dy <= r2 { return true }
                }
            }
            return false
        }
        for s in toRemove { removeStroke(id: s.id, registerUndo: true) }
        undoManager?.setActionName("Erase")
        undoManager?.endUndoGrouping()
    }

    /// Combined bounds for arbitrary strokes + items.
    func combinedBounds(strokes s: [Stroke], items i: [CanvasItem]) -> CGRect {
        var rect: CGRect?
        for st in s { rect = rect?.union(st.bounds) ?? st.bounds }
        for it in i { rect = rect?.union(it.frame) ?? it.frame }
        return rect ?? .zero
    }

    /// Bounds of the currently selected content.
    var selectionBounds: CGRect {
        combinedBounds(
            strokes: strokes.filter { selection.contains($0.id) },
            items: items.filter { selection.contains($0.id) }
        )
    }

    // MARK: - Hit testing (in document space)

    /// Return the topmost selectable id under point `p`, or nil.
    func hitTest(_ p: CGPoint) -> UUID? {
        for it in items.reversed() where it.frame.insetBy(dx: -4, dy: -4).contains(p) {
            return it.id
        }
        for s in strokes.reversed() where s.bounds.contains(p) {
            if strokeContainsPoint(s, p) { return s.id }
        }
        return nil
    }

    private func strokeContainsPoint(_ stroke: Stroke, _ p: CGPoint) -> Bool {
        let r = max(4, stroke.width * 0.6)
        let r2 = r * r
        for sp in stroke.points {
            let dx = sp.location.x - p.x
            let dy = sp.location.y - p.y
            if dx * dx + dy * dy <= r2 { return true }
        }
        return false
    }

    /// Everything fully contained in `rect` (for marquee / lasso selection).
    func idsContained(in rect: CGRect) -> Set<UUID> {
        var out: Set<UUID> = []
        for it in items where rect.contains(it.frame.origin) && rect.contains(CGPoint(x: it.frame.maxX, y: it.frame.maxY)) {
            out.insert(it.id)
        }
        for s in strokes where rect.contains(s.bounds) {
            out.insert(s.id)
        }
        return out
    }

    // MARK: - Document lifecycle

    func load(from file: ScratchpadFile, url: URL?) {
        title = file.title
        paperStyle = file.paperStyle
        canvasStyle = file.canvasStyle
        selectMode = file.selectMode
        pageCount = max(1, file.pageCount)
        strokes = file.strokes
        items = file.items
        panOffset = file.panOffset
        zoom = file.zoom
        fileURL = url
        selection.removeAll()
        liveStrokes.removeAll()
        undoManager?.removeAllActions()
        bumpModified()
    }

    func snapshot() -> ScratchpadFile {
        ScratchpadFile(
            title: title,
            paperStyle: paperStyle,
            canvasStyle: canvasStyle,
            selectMode: selectMode,
            pageCount: pageCount,
            strokes: strokes,
            items: items,
            panOffset: panOffset,
            zoom: zoom,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    func clear() {
        strokes.removeAll()
        items.removeAll()
        liveStrokes.removeAll()
        selection.removeAll()
        undoManager?.removeAllActions()
        bumpModified()
    }

    // MARK: - Modified tracking (used by autosave)

    /// Monotonically increases on any content change; autosave watches this.
    @Published private(set) var modificationTick: Int = 0
    private func bumpModified() { modificationTick &+= 1 }

    private static func fittedTextHeight(text: String, fontSize: CGFloat, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let sample = text.isEmpty ? " " : text
        let rect = NSAttributedString(string: sample, attributes: attrs).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }
}
