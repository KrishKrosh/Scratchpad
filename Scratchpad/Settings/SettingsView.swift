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
        .frame(width: 520, height: 240)
    }
}

private struct ExperimentalSettingsView: View {
    @AppStorage(AppSettings.drawingPressureThresholdKey)
    private var drawingPressureThreshold = AppSettings.defaultDrawingPressureThreshold

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

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

#Preview {
    SettingsView()
}
