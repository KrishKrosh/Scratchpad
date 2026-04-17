//
//  StrokesLayer.swift
//  Scratchpad
//

import SwiftUI

/// Renders all committed + live strokes through the current pan/zoom transform.
/// Strokes are stored in document-space; this layer applies the transform so
/// panning/zooming stays crisp and inexpensive.
struct StrokesLayer: View {
    let strokes: [Stroke]
    let liveStrokes: [Int32: Stroke]
    let panOffset: CGSize
    let zoom: CGFloat

    var body: some View {
        Canvas { ctx, size in
            // Map document space -> screen space.
            let tx = size.width / 2 + panOffset.width
            let ty = size.height / 2 + panOffset.height
            ctx.translateBy(x: tx, y: ty)
            ctx.scaleBy(x: zoom, y: zoom)

            for stroke in strokes {
                drawStroke(stroke, in: &ctx)
            }
            for stroke in liveStrokes.values {
                drawStroke(stroke, in: &ctx)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawStroke(_ stroke: Stroke, in ctx: inout GraphicsContext) {
        guard stroke.points.count > 1 else {
            if let p = stroke.points.first {
                let r = stroke.width * 0.5
                let rect = CGRect(x: p.location.x - r, y: p.location.y - r,
                                  width: stroke.width, height: stroke.width)
                ctx.fill(Path(ellipseIn: rect),
                         with: .color(stroke.swiftUIColor.opacity(stroke.opacity)))
            }
            return
        }

        // Smooth with a midpoint-quadratic pass for a handwritten feel.
        var path = Path()
        let pts = stroke.points.map(\.location)
        path.move(to: pts[0])
        if pts.count == 2 {
            path.addLine(to: pts[1])
        } else {
            for i in 1 ..< pts.count - 1 {
                let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                                  y: (pts[i].y + pts[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i])
            }
            path.addLine(to: pts[pts.count - 1])
        }

        // Average pressure over the stroke modulates the line width slightly.
        let avgP = stroke.points.reduce(0) { $0 + $1.pressure } / CGFloat(stroke.points.count)
        let widthMultiplier: CGFloat = stroke.tool == .highlighter
            ? 1.0
            : 0.6 + min(1.8, avgP * 1.2)
        let effectiveWidth = stroke.width * widthMultiplier

        let style = StrokeStyle(
            lineWidth: effectiveWidth,
            lineCap: stroke.tool == .highlighter ? .butt : .round,
            lineJoin: .round
        )
        ctx.stroke(path,
                   with: .color(stroke.swiftUIColor.opacity(stroke.opacity)),
                   style: style)
    }
}
