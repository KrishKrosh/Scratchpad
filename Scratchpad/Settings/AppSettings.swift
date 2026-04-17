//
//  AppSettings.swift
//  Scratchpad
//

import Foundation
import CoreGraphics

enum AppSettings {
    static let drawingPressureThresholdKey = "drawingPressureThreshold"
    static let minDrawingPressureThreshold: Double = 0
    static let maxDrawingPressureThreshold: Double = 500
    static let defaultDrawingPressureThreshold: Double = 0

    static func clamp(_ value: Double) -> Double {
        min(max(value, minDrawingPressureThreshold), maxDrawingPressureThreshold)
    }

    static func beginThreshold(from value: Double) -> CGFloat {
        CGFloat(clamp(value))
    }

    static func releaseThreshold(from value: Double) -> CGFloat {
        max(0, beginThreshold(from: value) * 0.72)
    }
}
