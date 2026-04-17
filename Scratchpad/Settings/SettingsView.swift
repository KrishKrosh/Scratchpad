//
//  SettingsView.swift
//  Scratchpad
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ExperimentalSettingsView()
                .tabItem {
                    Label("Experimental", systemImage: "flask")
                }
        }
        .scenePadding()
        .frame(width: 520, height: 300)
    }
}

private struct ExperimentalSettingsView: View {
    @AppStorage(AppSettings.drawingPressureThresholdKey)
    private var drawingPressureThreshold = AppSettings.defaultDrawingPressureThreshold
    @AppStorage(AppSettings.keyboardPanSensitivityKey)
    private var keyboardPanSensitivity = AppSettings.defaultKeyboardPanSensitivity
    @AppStorage(AppSettings.twoFingerDoubleTapUndoEnabledKey)
    private var twoFingerDoubleTapUndoEnabled = AppSettings.defaultTwoFingerDoubleTapUndoEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Draw Mode")
                .font(.title3.weight(.semibold))

            HStack(spacing: 14) {
                Text("Pressure Threshold")
                    .frame(width: 140, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { AppSettings.clamp(drawingPressureThreshold) },
                        set: { drawingPressureThreshold = AppSettings.clamp($0.rounded()) }
                    ),
                    in: AppSettings.minDrawingPressureThreshold...AppSettings.maxDrawingPressureThreshold
                )

                Text("\(Int(drawingPressureThreshold))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack(spacing: 14) {
                Text("Keyboard Pan")
                    .frame(width: 140, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { AppSettings.clampKeyboardPanSensitivity(keyboardPanSensitivity) },
                        set: { keyboardPanSensitivity = AppSettings.clampKeyboardPanSensitivity($0.rounded()) }
                    ),
                    in: AppSettings.minKeyboardPanSensitivity...AppSettings.maxKeyboardPanSensitivity
                )

                Text("\(Int(keyboardPanSensitivity))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            Toggle("Two-Finger Double Tap to Undo", isOn: $twoFingerDoubleTapUndoEnabled)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

#Preview {
    SettingsView()
}
