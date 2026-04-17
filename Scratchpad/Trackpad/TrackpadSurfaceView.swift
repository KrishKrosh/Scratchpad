//
//  TrackpadSurfaceView.swift
//  Scratchpad
//
//  The rectangular "lens" on the canvas that represents the trackpad. It is
//  fully transparent (just an outline). The outline only shows when a drawing
//  tool is active. Finger indicators only appear when drawing mode is engaged.
//

import SwiftUI

struct TrackpadSurfaceView: View {
    @ObservedObject var doc: DocumentModel
    @ObservedObject var input: TrackpadInputManager

    /// Rect of the surface in screen space (fixed — does not follow pan/zoom).
    let screenRect: CGRect
    /// Suppress finger indicators (e.g. while pan/zoom is active).
    var hideIndicator: Bool = false
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        let drawing = doc.isDrawingModeActive
        let indicatorSize = max(3, currentIndicatorSize())
        let indicatorColor: Color = doc.tool == .eraser ? .gray : doc.color

        ZStack {
            // Outline only — no fill, no glass.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    drawing
                        ? AnyShapeStyle(LinearGradient(
                            colors: [
                                Color(red: 0.32, green: 0.24, blue: 0.94),
                                Color(red: 0.60, green: 0.35, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.primary.opacity(0.35)),
                    style: StrokeStyle(
                        lineWidth: drawing ? 2 : 1,
                        dash: drawing ? [] : [5, 4]
                    )
                )

            // Mode hint pill at the top of the outline.
            HintPill(isDrawing: drawing)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, -12)

            // Finger indicators — only while drawing mode is on, and not
            // suppressed by pan/zoom activity.
            if drawing && !hideIndicator {
                ForEach(input.touches.filter(\.isContact)) { t in
                    IndicatorDot(
                        touch: t,
                        surfaceSize: screenRect.size,
                        diameter: indicatorSize,
                        color: indicatorColor
                    )
                }
            }
        }
        .frame(width: screenRect.width, height: screenRect.height)
        // An invisible fill-sized hit target so the whole rect is draggable
        // when not in drawing mode. But we keep it hit-testable only when we
        // actually want to drag; otherwise scroll (pan/zoom) passes through.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture(drawing: drawing))
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: drawing)
    }

    private func dragGesture(drawing: Bool) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { v in
                // When drawing, we do NOT want a cursor drag to move the card —
                // but hovering/drawing happens via the trackpad, not mouse.
                if drawing { return }
                onDragChanged(v.translation)
            }
            .onEnded { _ in
                if drawing { return }
                onDragEnded()
            }
    }

    /// Diameter of the indicator — matches the current tool's stroke width.
    private func currentIndicatorSize() -> CGFloat {
        switch doc.tool {
        case .highlighter: return doc.highlighterWidth
        case .eraser:      return doc.eraserWidth
        default:           return doc.lineWidth
        }
    }
}

// MARK: - Hint pill

private struct HintPill: View {
    let isDrawing: Bool
    var body: some View {
        HStack(spacing: 6) {
            if isDrawing {
                Circle().fill(Color.white).frame(width: 6, height: 6)
                Text("DRAWING").fontWeight(.bold)
                Text("•").opacity(0.6)
                Text("⌘D OR ESC TO EXIT").fontWeight(.semibold)
            } else {
                Image(systemName: "hand.point.up.left")
                Text("PRESS ⌘D TO DRAW").fontWeight(.semibold)
            }
        }
        .font(.system(size: 10.5, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                isDrawing
                    ? AnyShapeStyle(LinearGradient(
                        colors: [
                            Color(red: 0.32, green: 0.24, blue: 0.94),
                            Color(red: 0.60, green: 0.35, blue: 0.95)
                        ],
                        startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.black.opacity(0.55))
            )
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Tiny finger dot

private struct IndicatorDot: View {
    let touch: NormalizedTouch
    let surfaceSize: CGSize
    let diameter: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .fill(color.opacity(0.85))
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 0.8))
            .frame(width: diameter, height: diameter)
            .offset(
                x: -surfaceSize.width / 2 + touch.x * surfaceSize.width,
                y: -surfaceSize.height / 2 + touch.y * surfaceSize.height
            )
            .allowsHitTesting(false)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.85), value: touch.x)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.85), value: touch.y)
    }
}
