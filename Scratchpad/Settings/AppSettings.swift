//
//  AppSettings.swift
//  Scratchpad
//

import Foundation
import CoreGraphics

enum AppSettings {
    static let drawingPressureThresholdKey = "drawingPressureThreshold"
    static let keyboardPanSensitivityKey = "keyboardPanSensitivity"
    static let twoFingerDoubleTapUndoEnabledKey = "twoFingerDoubleTapUndoEnabled"
    static let minDrawingPressureThreshold: Double = 0
    static let maxDrawingPressureThreshold: Double = 500
    static let defaultDrawingPressureThreshold: Double = 0
    static let minKeyboardPanSensitivity: Double = 8
    static let maxKeyboardPanSensitivity: Double = 160
    static let defaultKeyboardPanSensitivity: Double = 42
    static let defaultTwoFingerDoubleTapUndoEnabled = true

    static func clamp(_ value: Double) -> Double {
        min(max(value, minDrawingPressureThreshold), maxDrawingPressureThreshold)
    }

    static func clampKeyboardPanSensitivity(_ value: Double) -> Double {
        min(max(value, minKeyboardPanSensitivity), maxKeyboardPanSensitivity)
    }

    static func beginThreshold(from value: Double) -> CGFloat {
        CGFloat(clamp(value))
    }

    static func releaseThreshold(from value: Double) -> CGFloat {
        max(0, beginThreshold(from: value) * 0.72)
    }
}
