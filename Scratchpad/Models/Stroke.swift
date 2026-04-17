//
//  Stroke.swift
//  Scratchpad
//

import Foundation
import SwiftUI

/// A single captured sample along a stroke, in document-space coordinates.
struct StrokePoint: Hashable, Codable {
    var location: CGPoint
    var pressure: CGFloat
    var timestamp: TimeInterval
}

enum PaperStyle: String, CaseIterable, Identifiable, Codable {
    case dots, grid, lined, blank
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dots: "Dots"
        case .grid: "Grid"
        case .lined: "Lined"
        case .blank: "Blank"
        }
    }
    var symbol: String {
        switch self {
        case .dots: "circle.grid.3x3"
        case .grid: "square.grid.3x3"
        case .lined: "text.alignleft"
        case .blank: "square"
        }
    }
}

enum ToolKind: String, CaseIterable, Identifiable, Codable {
    case select, pen, highlighter, eraser, text, shape
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select:      "cursorarrow"
        case .pen:         "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser:      "eraser"
        case .text:        "textformat"
        case .shape:       "square.on.circle"
        }
    }
    var label: String {
        switch self {
        case .select:      "Select"
        case .pen:         "Pen"
        case .highlighter: "Highlighter"
        case .eraser:      "Eraser"
        case .text:        "Text"
        case .shape:       "Shapes"
        }
    }
    var canDraw: Bool {
        self == .pen || self == .highlighter || self == .eraser
    }
}

/// How the select tool builds its selection.
enum SelectMode: String, CaseIterable, Identifiable, Codable {
    case rectangle, lasso
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .lasso:     "Lasso"
        }
    }
    var symbol: String {
        switch self {
        case .rectangle: "rectangle.dashed"
        case .lasso:     "lasso"
        }
    }
}

/// Canvas backdrop — either infinite paper or a single-page rectangle.
enum CanvasStyle: String, CaseIterable, Identifiable, Codable {
    case infinite, page
    var id: String { rawValue }
    var label: String {
        switch self {
        case .infinite: "Infinite"
        case .page:     "Page"
        }
    }
    var symbol: String {
        switch self {
        case .infinite: "rectangle.expand.vertical"
        case .page:     "doc"
        }
    }
}

/// A rendered mark on the canvas.
struct Stroke: Identifiable, Codable {
    var id: UUID = UUID()
    var points: [StrokePoint]
    var color: CodableColor
    /// Base line width in document points.
    var width: CGFloat
    var tool: ToolKind
    var opacity: Double

    init(id: UUID = UUID(),
         points: [StrokePoint] = [],
         color: Color,
         width: CGFloat,
         tool: ToolKind,
         opacity: Double = 1.0) {
        self.id = id
        self.points = points
        self.color = CodableColor(color)
        self.width = width
        self.tool = tool
        self.opacity = opacity
    }

    var swiftUIColor: Color { color.color }

    /// The minimal bounding rect of the stroke in document space.
    var bounds: CGRect {
        guard let first = points.first?.location else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.location.x); maxX = max(maxX, p.location.x)
            minY = min(minY, p.location.y); maxY = max(maxY, p.location.y)
        }
        let pad = width
        return CGRect(x: minX - pad, y: minY - pad,
                      width: (maxX - minX) + pad * 2,
                      height: (maxY - minY) + pad * 2)
    }
}
