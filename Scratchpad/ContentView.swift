//
//  ContentView.swift
//  Scratchpad
//
//  Created by Krish Shah on 2026-04-17.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 0.91),
                    Color(red: 0.91, green: 0.87, blue: 0.81)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("Scratchpad")
                    .font(.title2.weight(.semibold))

                Text("Capture quick thoughts, cleanly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }
}

#Preview {
    ContentView()
}
