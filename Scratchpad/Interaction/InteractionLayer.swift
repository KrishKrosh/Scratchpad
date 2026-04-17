//
//  InteractionLayer.swift
//  Scratchpad
//
//  Full-canvas transparent layer that handles mouse input for:
//  - select tool (click, marquee OR lasso, drag-move, corner-resize)
//  - shape tool (click-drag to create)
//  - text tool (click to place)
//  - drawing tools WHEN drawing mode is OFF (mouse-drag to draw a stroke)
//

import SwiftUI
import AppKit

struct InteractionLayer: View {
    @ObservedObject var doc: DocumentModel
    let isTextEditing: Bool
    let onBeginTextEdit: (UUID) -> Void
    /// Called whenever the layer receives a user interaction — the host uses
    /// this to resign first responder so the title TextField commits / blurs.
    var onInteractionBegin: () -> Void = {}

    @State private var dragStart: CGPoint? = nil
    @State private var dragStartDoc: CGPoint? = nil
    @State private var dragMovedSignificantly: Bool = false
    @State private var moveStartDoc: CGPoint? = nil
    @State private var moveTotal: CGSize = .zero
    @State private var moveIDs: Set<UUID> = []
    @State private var shapePreview: CGRect? = nil
    @State private var marquee: CGRect? = nil
    @State private var lassoPoints: [CGPoint] = []
    @State private var mode: Mode = .idle
    @State private var resizeAnchor: CGPoint = .zero
    @State private var resizeInitialSel: CGRect = .zero
    @State private var resizeHandle: ResizeHandle = .bottomRight
    @State private var resizeCumulativeSX: CGFloat = 1
    @State private var resizeCumulativeSY: CGFloat = 1
    @State private var drawTouchID: Int32 = -1

    private enum Mode {
        case idle, moving, marquee, lasso, shape, resizing, drawing, textPending
    }

    private enum ResizeHandle: Int {
        case topLeft = 0, top, topRight, bottomLeft, bottom, left, right, bottomRight

        func anchor(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.maxX, y: rect.maxY)
            case .top: return CGPoint(x: rect.midX, y: rect.maxY)
            case .topRight: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomLeft: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
            case .left: return CGPoint(x: rect.maxX, y: rect.midY)
            case .right: return CGPoint(x: rect.minX, y: rect.midY)
            case .bottomRight: return CGPoint(x: rect.minX, y: rect.minY)
            }
        }

        var affectsX: Bool {
            switch self {
            case .top, .bottom: return false
            default: return true
            }
        }

        var affectsY: Bool {
            switch self {
            case .left, .right: return false
            default: return true
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear.contentShape(Rectangle())
                SelectionLayer(
                    selectionRect: doc.selection.isEmpty ? nil : doc.selectionBounds,
                    marqueeRect: mode == .marquee ? marquee : nil,
                    lassoPath: mode == .lasso ? lassoPoints : nil,
                    shapePreview: shapePreview.flatMap { r in
                        SelectionLayer.ShapePreview(
                            kind: doc.shapeKind,
                            color: doc.color,
                            width: doc.shapeStrokeWidth,
                            rect: r
                        )
                    },
                    panOffset: doc.panOffset,
                    zoom: doc.zoom,
                    showHandles: (doc.tool == .select || doc.tool == .text) && !doc.selection.isEmpty
                )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in handleDragChanged(g, in: proxy.size) }
                    .onEnded { g in handleDragEnded(g, in: proxy.size) }
            )
        }
        .allowsHitTesting(shouldHandle)
    }

    /// Whether this layer intercepts events. Skips when editing text so the
    /// NSTextView can receive events.
    private var shouldHandle: Bool {
        if isTextEditing { return false }
        switch doc.tool {
        case .pen, .highlighter, .eraser:
            return !doc.isDrawingModeActive
        case .select, .shape, .text:
            return true
        }
    }

    // MARK: - Coordinate math

    private func screenToDoc(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let cx = size.width / 2 + doc.panOffset.width
        let cy = size.height / 2 + doc.panOffset.height
        return CGPoint(x: (p.x - cx) / doc.zoom, y: (p.y - cy) / doc.zoom)
    }

    private func docToScreen(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let cx = size.width / 2 + doc.panOffset.width
        let cy = size.height / 2 + doc.panOffset.height
        return CGPoint(x: cx + p.x * doc.zoom, y: cy + p.y * doc.zoom)
    }

    /// Screen-space corner handle hit test — returns the corner index (0..3)
    /// for TL, TR, BL, BR, or nil.
    private func resizeHandleHit(_ p: CGPoint, in size: CGSize) -> ResizeHandle? {
        guard (doc.tool == .select || doc.tool == .text), !doc.selection.isEmpty else { return nil }
        let b = doc.selectionBounds
        let tl = docToScreen(CGPoint(x: b.minX, y: b.minY), in: size)
        let tm = docToScreen(CGPoint(x: b.midX, y: b.minY), in: size)
        let tr = docToScreen(CGPoint(x: b.maxX, y: b.minY), in: size)
        let bl = docToScreen(CGPoint(x: b.minX, y: b.maxY), in: size)
        let bm = docToScreen(CGPoint(x: b.midX, y: b.maxY), in: size)
        let lm = docToScreen(CGPoint(x: b.minX, y: b.midY), in: size)
        let rm = docToScreen(CGPoint(x: b.maxX, y: b.midY), in: size)
        let br = docToScreen(CGPoint(x: b.maxX, y: b.maxY), in: size)
        let inset: CGFloat = 5
        let handleR: CGFloat = SelectionLayer.handleDiameter + 2
        let corners = [tl, tm, tr, bl, bm, lm, rm, br]
        let inflated = [
            CGPoint(x: tl.x - inset, y: tl.y - inset),
            CGPoint(x: tm.x, y: tm.y - inset),
            CGPoint(x: tr.x + inset, y: tr.y - inset),
            CGPoint(x: bl.x - inset, y: bl.y + inset),
            CGPoint(x: bm.x, y: bm.y + inset),
            CGPoint(x: lm.x - inset, y: lm.y),
            CGPoint(x: rm.x + inset, y: rm.y),
            CGPoint(x: br.x + inset, y: br.y + inset)
        ]
        for (i, c) in corners.enumerated() {
            let dx = p.x - inflated[i].x
            let dy = p.y - inflated[i].y
            if dx * dx + dy * dy <= handleR * handleR {
                // Return the doc-space opposite corner as the stationary anchor.
                _ = c
                return ResizeHandle(rawValue: i)
            }
        }
        return nil
    }

    // MARK: - Gesture handling

    private func handleDragChanged(_ g: DragGesture.Value, in size: CGSize) {
        let start = g.startLocation
        let current = g.location

        if dragStart == nil {
            dragStart = start
            dragStartDoc = screenToDoc(start, in: size)
            dragMovedSignificantly = false
            onInteractionBegin()
            determineMode(at: start, in: size)
        }

        let ddx = current.x - start.x
        let ddy = current.y - start.y
        if ddx * ddx + ddy * ddy > 9 { dragMovedSignificantly = true }

        switch mode {
        case .moving:
            guard let prev = moveStartDoc else { return }
            let docP = screenToDoc(current, in: size)
            let dx = docP.x - prev.x
            let dy = docP.y - prev.y
            doc.translateSelection(dx: dx, dy: dy)
            moveTotal.width += dx
            moveTotal.height += dy
            moveStartDoc = docP

        case .resizing:
            let docP = screenToDoc(current, in: size)
            let rect = resizeInitialSel
            // Compute target scale relative to the ORIGINAL bounds (pre-drag).
            let tsx: CGFloat
            let tsy: CGFloat
            if resizeHandle.affectsX {
                if resizeAnchor.x <= rect.midX {
                    tsx = max(0.1, (docP.x - resizeAnchor.x) / max(rect.maxX - resizeAnchor.x, 0.001))
                } else {
                    tsx = max(0.1, (resizeAnchor.x - docP.x) / max(resizeAnchor.x - rect.minX, 0.001))
                }
            } else {
                tsx = 1
            }
            if resizeHandle.affectsY {
                if resizeAnchor.y <= rect.midY {
                    tsy = max(0.1, (docP.y - resizeAnchor.y) / max(rect.maxY - resizeAnchor.y, 0.001))
                } else {
                    tsy = max(0.1, (resizeAnchor.y - docP.y) / max(resizeAnchor.y - rect.minY, 0.001))
                }
            } else {
                tsy = 1
            }
            // Apply incremental scale so we end up at (tsx, tsy) vs the original.
            let incX = tsx / resizeCumulativeSX
            let incY = tsy / resizeCumulativeSY
            doc.scaleSelection(sx: incX, sy: incY, anchor: resizeAnchor)
            resizeCumulativeSX = tsx
            resizeCumulativeSY = tsy

        case .marquee:
            let r = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            marquee = r

        case .lasso:
            lassoPoints.append(current)

        case .shape:
            let a = screenToDoc(start, in: size)
            let b = screenToDoc(current, in: size)
            shapePreview = CGRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(b.x - a.x), height: abs(b.y - a.y)
            )

        case .drawing:
            let docP = screenToDoc(current, in: size)
            doc.extendStroke(id: drawTouchID, to: docP, pressure: 0.6, timestamp: g.time.timeIntervalSince1970)

        case .textPending, .idle:
            break
        }
    }

    private func determineMode(at start: CGPoint, in size: CGSize) {
        switch doc.tool {
        case .select:
            if let handle = resizeHandleHit(start, in: size) {
                mode = .resizing
                resizeInitialSel = doc.selectionBounds
                resizeHandle = handle
                resizeAnchor = handle.anchor(in: resizeInitialSel)
                resizeCumulativeSX = 1
                resizeCumulativeSY = 1
                return
            }
            let docP = screenToDoc(start, in: size)
            if let hitID = doc.hitTest(docP) {
                if !doc.selection.contains(hitID) { doc.selection = [hitID] }
                mode = .moving
                moveStartDoc = docP
                moveTotal = .zero
                moveIDs = doc.selection
            } else {
                doc.selection.removeAll()
                if doc.selectMode == .lasso {
                    mode = .lasso
                    lassoPoints = [start]
                } else {
                    mode = .marquee
                }
            }

        case .shape:
            mode = .shape

        case .text:
            if let handle = resizeHandleHit(start, in: size) {
                mode = .resizing
                resizeInitialSel = doc.selectionBounds
                resizeHandle = handle
                resizeAnchor = handle.anchor(in: resizeInitialSel)
                resizeCumulativeSX = 1
                resizeCumulativeSY = 1
                return
            }

            let p = screenToDoc(start, in: size)
            if let textID = textItemHitTest(p) {
                doc.selection = [textID]
                onBeginTextEdit(textID)
                mode = .textPending
            } else {
                // Click-to-place. The DragGesture intercepts simple taps too, so
                // we place the text item right here. A subsequent drag (unlikely)
                // is ignored.
                let rect = CGRect(x: p.x, y: p.y,
                                  width: 220,
                                  height: max(32, doc.textFontSize * 1.6))
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
                onBeginTextEdit(item.id)
                mode = .textPending
            }

        case .pen, .highlighter, .eraser:
            guard !doc.isDrawingModeActive else { mode = .idle; return }
            // Mouse drawing path.
            drawTouchID = Int32.random(in: 1_000...9_999)
            let docP = screenToDoc(start, in: size)
            doc.beginStroke(id: drawTouchID, at: docP, pressure: 0.6, timestamp: Date().timeIntervalSince1970)
            mode = .drawing
        }
    }

    private func textItemHitTest(_ p: CGPoint) -> UUID? {
        for item in doc.items.reversed() {
            if case .text = item.kind, item.frame.insetBy(dx: -4, dy: -4).contains(p) {
                return item.id
            }
        }
        return nil
    }

    private func handleDragEnded(_ g: DragGesture.Value, in size: CGSize) {
        let endLocation = g.location
        defer {
            dragStart = nil
            dragStartDoc = nil
            dragMovedSignificantly = false
            moveStartDoc = nil
            marquee = nil
            lassoPoints = []
            shapePreview = nil
            let finishedMode = mode
            mode = .idle
            if finishedMode == .moving, moveTotal != .zero {
                doc.registerMoveUndo(totalDx: moveTotal.width,
                                     totalDy: moveTotal.height,
                                     ids: moveIDs)
            }
            if finishedMode == .resizing,
               resizeCumulativeSX != 1 || resizeCumulativeSY != 1 {
                doc.registerResizeUndo(sx: resizeCumulativeSX,
                                       sy: resizeCumulativeSY,
                                       anchor: resizeAnchor,
                                       ids: doc.selection)
            }
            moveTotal = .zero
            moveIDs = []
            resizeCumulativeSX = 1
            resizeCumulativeSY = 1
            drawTouchID = -1
        }

        switch mode {
        case .marquee:
            if dragMovedSignificantly, let r = marquee, r.width > 4 || r.height > 4 {
                let p0 = screenToDoc(CGPoint(x: r.minX, y: r.minY), in: size)
                let p1 = screenToDoc(CGPoint(x: r.maxX, y: r.maxY), in: size)
                let docRect = CGRect(
                    x: min(p0.x, p1.x), y: min(p0.y, p1.y),
                    width: abs(p1.x - p0.x), height: abs(p1.y - p0.y)
                )
                doc.selection = doc.idsContained(in: docRect)
            } else {
                // Treat as a click — select under cursor, or clear.
                let docP = screenToDoc(endLocation, in: size)
                if let id = doc.hitTest(docP) {
                    doc.selection = [id]
                } else {
                    doc.selection.removeAll()
                }
            }

        case .lasso:
            if dragMovedSignificantly, lassoPoints.count > 3 {
                let docPts = lassoPoints.map { screenToDoc($0, in: size) }
                doc.selection = idsInsidePolygon(docPts)
            } else {
                let docP = screenToDoc(endLocation, in: size)
                if let id = doc.hitTest(docP) {
                    doc.selection = [id]
                } else {
                    doc.selection.removeAll()
                }
            }

        case .shape:
            if let r = shapePreview, r.width > 3 || r.height > 3 {
                let item = CanvasItem(
                    frame: r,
                    kind: .shape(doc.shapeKind, CodableColor(doc.color), doc.shapeStrokeWidth)
                )
                doc.addItem(item)
                doc.selection = [item.id]
                doc.tool = .select
            }

        case .drawing:
            doc.endStroke(id: drawTouchID)

        case .textPending, .moving, .resizing, .idle:
            break
        }
    }

    /// Ray-cast point-in-polygon test for lasso selection.
    private func idsInsidePolygon(_ polygon: [CGPoint]) -> Set<UUID> {
        var out: Set<UUID> = []
        for it in doc.items where pointInPolygon(CGPoint(x: it.frame.midX, y: it.frame.midY), polygon) {
            out.insert(it.id)
        }
        for s in doc.strokes {
            let b = s.bounds
            if pointInPolygon(CGPoint(x: b.midX, y: b.midY), polygon) {
                out.insert(s.id)
            }
        }
        return out
    }

    private func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count > 2 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let pi = poly[i], pj = poly[j]
            if ((pi.y > p.y) != (pj.y > p.y)) &&
                (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y + 0.00001) + pi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
