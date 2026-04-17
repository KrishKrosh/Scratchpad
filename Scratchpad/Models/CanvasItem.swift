//
//  CanvasItem.swift
//  Scratchpad
//
//  Non-stroke content on the canvas: text boxes, shapes, images.
//

import Foundation
import SwiftUI

enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case rectangle, ellipse, line, arrow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse:   "Ellipse"
        case .line:      "Line"
        case .arrow:     "Arrow"
        }
    }
    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse:   "oval"
        case .line:      "line.diagonal"
        case .arrow:     "arrow.right"
        }
    }
}

struct CodableColor: Codable, Hashable {
    var r: Double; var g: Double; var b: Double; var a: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.labelColor
        self.init(r: Double(ns.redComponent),
                  g: Double(ns.greenComponent),
                  b: Double(ns.blueComponent),
                  a: Double(ns.alphaComponent))
    }
}

/// A non-stroke visible object placed in document space.
struct CanvasItem: Identifiable, Codable {
    var id: UUID = UUID()
    /// Item bounds in document space.
    var frame: CGRect
    var kind: Kind

    enum Kind: Codable {
        case text(TextContent)
        case latex(LatexContent)
        case shape(ShapeKind, CodableColor, CGFloat /* stroke width */)
        case image(Data /* PNG data */)
    }

    struct TextContent: Codable, Hashable {
        var text: String
        var fontSize: CGFloat
        var color: CodableColor
    }

    struct LatexContent: Codable {
        var latex: String
        var color: CodableColor
        var renderedPNGData: Data?
        var sourceStrokes: [Stroke]
    }
}
