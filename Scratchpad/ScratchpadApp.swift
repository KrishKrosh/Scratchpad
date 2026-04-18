//
//  ScratchpadApp.swift
//  Scratchpad
//

import Foundation
import SwiftUI
import AppKit

@main
struct ScratchpadApp: App {
    @StateObject private var appUpdater = AppUpdater()

    var body: some Scene {
        // Home / library window — opened at launch and via the home button.
        Window("Scratchpads", id: "home") {
            HomeView()
                .environmentObject(appUpdater)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)

        // One window per .scratchpad URL. New Document = save empty and open.
        WindowGroup("Scratchpad", for: URL.self) { $url in
            ContentView(fileURL: url)
                .frame(minWidth: 900, minHeight: 620)
                .environmentObject(appUpdater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appUpdater.checkForUpdates()
                }
            }

            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(".", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appUpdater)
        }
        .windowResizability(.contentSize)
    }
}
