//
//  DotGridBackground.swift
//  Scratchpad
//

import SwiftUI

/// Infinite paper background OR a single-page rectangle. Renders dots / grid
/// / lines in document space, panned & zoomed by the current canvas transform.
struct DotGridBackground: View {
    let paperStyle: PaperStyle
    let canvasStyle: CanvasStyle
    let panOffset: CGSize
    let zoom: CGFloat
    /// How many stacked pages to render in `.page` mode. Ignored for infinite.
    var pageCount: Int = 1

    /// Document-space spacing between grid units.
    private let baseSpacing: CGFloat = 24
    /// US Letter portrait at 72 dpi — doc-space dimensions for .page mode.
    static let pageSize: CGSize = CGSize(width: 612, height: 792)
    /// Doc-space vertical gap between pages in multi-page layout.
    static let pageGap: CGFloat = 20

    /// Doc-space origin (top-left) of page `i`. Pages stack vertically centred
    /// horizontally around 0; page 0 sits with its center at doc origin.
    static func pageDocOrigin(_ i: Int) -> CGPoint {
        let firstTopY = -pageSize.height / 2
        let y = firstTopY + CGFloat(i) * (pageSize.height + pageGap)
        return CGPoint(x: -pageSize.width / 2, y: y)
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(canvasStyle == .page
                             ? Color(nsColor: .windowBackgroundColor)
                             : Color(nsColor: .textBackgroundColor))
            )

            if canvasStyle == .page {
                let count = max(1, pageCount)
                for i in 0..<count {
                    let rect = pageScreenRect(index: i, in: size)
                    let pagePath = Path(roundedRect: rect, cornerRadius: 6)
                    ctx.fill(pagePath, with: .color(Color(nsColor: .textBackgroundColor)))
                    ctx.stroke(pagePath, with: .color(Color.primary.opacity(0.15)), lineWidth: 0.8)
                    ctx.drawLayer { inner in
                        inner.clip(to: pagePath)
                        drawPaper(ctx: inner, size: size)
                    }
                }
                return
            }

            drawPaper(ctx: ctx, size: size)
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    private func pageScreenRect(index i: Int, in size: CGSize) -> CGRect {
        let origin = Self.pageDocOrigin(i)
        let w = Self.pageSize.width * zoom
        let h = Self.pageSize.height * zoom
        let cx = size.width / 2 + panOffset.width
        let cy = size.height / 2 + panOffset.height
        return CGRect(
            x: cx + origin.x * zoom,
            y: cy + origin.y * zoom,
            width: w,
            height: h
        )
    }

    private func drawPaper(ctx: GraphicsContext, size: CGSize) {
        let spacing = baseSpacing * zoom
        guard spacing > 6 else { return }

        let dotColor = Color.primary.opacity(0.18)
        let lineColor = Color.primary.opacity(0.12)

        let originX = size.width / 2 + panOffset.width
        let originY = size.height / 2 + panOffset.height

        let startX = originX.truncatingRemainder(dividingBy: spacing)
        let startY = originY.truncatingRemainder(dividingBy: spacing)

        switch paperStyle {
        case .blank:
            return

        case .dots:
            let r = max(1.1, 1.4 * min(1.2, zoom))
            var y = startY - spacing
            while y < size.height + spacing {
                var x = startX - spacing
                while x < size.width + spacing {
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    x += spacing
                }
                y += spacing
            }

        case .grid:
            var x = startX
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 0.6)
                x += spacing
            }
            var y = startY
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 0.6)
                y += spacing
            }

        case .lined:
            let lineSpacing = spacing * 1.25
            var y = originY.truncatingRemainder(dividingBy: lineSpacing)
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 0.6)
                y += lineSpacing
            }
        }
    }
}
