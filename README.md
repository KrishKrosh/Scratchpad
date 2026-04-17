# Scratchpad

Scratchpad is a macOS SwiftUI drawing app designed for fast whiteboarding with a trackpad surface and a document library.

## What This Project Is

Scratchpad is not a template app anymore. It currently includes:

- Multi-window document workflow (`Home` library + one editor window per `.scratchpad` file)
- Drawing tools: pen, highlighter, eraser
- Editing tools: select (rectangle/lasso), text, and shapes
- Floating toolbar with title editing, paper/canvas style, color palette, width controls, export, and clear/new actions
- Trackpad integration via [`OpenMultitouchSupport`](https://github.com/KrishKrosh/OpenMultitouchSupport)
- Autosave and file persistence in JSON-backed `.scratchpad` documents
- Export options: PNG, PDF, and raw `.scratchpad`

## Tech Stack

- Swift 5 + SwiftUI
- AppKit interop where needed (window/event handling, save/export panels)
- Swift Package dependency:
  - `OpenMultitouchSupport` (`1.0.12`)

## Project Structure

- `Scratchpad/ScratchpadApp.swift`
  - App entrypoint and scene setup (`home` window + document `WindowGroup`)
- `Scratchpad/ContentView.swift`
  - Main editor composition, event monitors, autosave loop, export hooks
- `Scratchpad/Home/`
  - Library view for listing/opening/deleting scratchpad documents
- `Scratchpad/Toolbar/`
  - Floating toolbar and tool controls
- `Scratchpad/Interaction/`
  - Mouse-based interaction layer for selecting, moving, resizing, shape placement, etc.
- `Scratchpad/Canvas/`
  - Render layers (grid, strokes, items, selection overlays)
- `Scratchpad/Trackpad/`
  - Trackpad touch ingestion and surface UI
- `Scratchpad/Models/`
  - Document state, persistence, stroke/item models, naming

## Data and Storage

- Scratchpad files are JSON documents with `.scratchpad` extension.
- Autosaved docs are stored under:
  - `~/Documents/Scratchpad`
- The home/library window lists files from that directory.

## Developing Locally

### Requirements

- macOS
- Xcode 17+

### Run in Xcode

1. Open `/Users/krishshah/Code/Scratchpad/Scratchpad.xcodeproj`.
2. Select the `Scratchpad` scheme.
3. Build and run with `Cmd+R`.

### Build from Terminal

```bash
cd /Users/krishshah/Code/Scratchpad
xcodebuild -project Scratchpad.xcodeproj -scheme Scratchpad -configuration Debug build
```

### Dependency Notes

- `OpenMultitouchSupport` is resolved through Swift Package Manager.
- If package resolution is stale/broken, in Xcode run:
  - `File -> Packages -> Reset Package Caches`
  - `File -> Packages -> Resolve Package Versions`

## Current Interaction Notes

- `Cmd+D` toggles drawing mode (see trackpad surface hint in-app).
- `Esc` exits drawing mode.
- Selection supports rectangle/lasso and resize handles.
- Undo/redo flows through `NSUndoManager` in `DocumentModel`.
