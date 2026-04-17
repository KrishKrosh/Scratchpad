//
//  SelectionLayer.swift
//  Scratchpad
//
//  Selection outline with corner handles, lasso/marquee rectangle,
//  free-form lasso path, and a shape-being-dragged preview.
//

import SwiftUI

struct SelectionLayer: View {
    /// Selection bounding rect in document space.
    let selectionRect: CGRect?
    /// Screen-space marquee rectangle during a drag.
    let marqueeRect: CGRect?
    /// Screen-space lasso path during a free-form drag.
    let lassoPath: [CGPoint]?
    let shapePreview: ShapePreview?
    let panOffset: CGSize
    let zoom: CGFloat
    let showHandles: Bool

    struct ShapePreview {
        let kind: ShapeKind
        let color: Color
        let width: CGFloat
        let rect: CGRect
    }

    /// Screen-space diameter of a handle grabber.
    static let handleDiameter: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear

                if let rect = selectionRect {
                    let sr = screenRect(for: rect, in: proxy.size).insetBy(dx: -4, dy: -4)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                        .frame(width: sr.width, height: sr.height)
                        .position(x: sr.midX, y: sr.midY)

                    if showHandles {
                        ForEach(handlePoints(of: sr), id: \.self) { pt in
                            Circle()
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                                .frame(width: Self.handleDiameter, height: Self.handleDiameter)
                                .position(pt)
                                .shadow(color: .black.opacity(0.1), radius: 1)
                        }
                    }
                }

                if let rect = marqueeRect {
                    Rectangle()
                        .strokeBorder(
                            Color.accentColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .background(Color.accentColor.opacity(0.08))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if let pts = lassoPath, pts.count > 1 {
                    LassoShape(points: pts)
                        .stroke(
                            Color.accentColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                    LassoShape(points: pts, closed: true)
                        .fill(Color.accentColor.opacity(0.08))
                }

                if let prev = shapePreview {
                    let sr = screenRect(for: prev.rect, in: proxy.size)
                    shapePreviewView(prev)
                        .frame(width: max(sr.width, 1), height: max(sr.height, 1))
                        .position(x: sr.midX, y: sr.midY)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Eight resize handles: corners + side midpoints.
    private func handlePoints(of r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.minX, y: r.midY),
            CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.maxX, y: r.maxY)
        ]
    }

    private func screenRect(for docRect: CGRect, in size: CGSize) -> CGRect {
        let cx = size.width / 2 + panOffset.width
        let cy = size.height / 2 + panOffset.height
        return CGRect(
            x: cx + docRect.origin.x * zoom,
            y: cy + docRect.origin.y * zoom,
            width: docRect.width * zoom,
            height: docRect.height * zoom
        )
    }

    @ViewBuilder
    private func shapePreviewView(_ p: ShapePreview) -> some View {
        let w = max(p.width * zoom, 0.5)
        switch p.kind {
        case .rectangle:
            Rectangle().stroke(p.color, lineWidth: w)
        case .ellipse:
            Ellipse().stroke(p.color, lineWidth: w)
        case .line:
            LineDiag().stroke(p.color, lineWidth: w)
        case .arrow:
            ArrowDiag().stroke(p.color, lineWidth: w)
        }
    }
}

private struct LineDiag: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

private struct ArrowDiag: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        let head = min(rect.width, rect.height) * 0.25
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - head, y: rect.maxY - head * 0.3))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - head * 0.3, y: rect.maxY - head))
        return p
    }
}

private struct LassoShape: Shape {
    let points: [CGPoint]
    var closed: Bool = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        if closed { p.closeSubpath() }
        return p
    }
}
