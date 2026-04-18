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
  - `Sparkle` (`2.9.x`) for signed in-app updates with a custom SwiftUI toolbar chip

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
- `MLX` and `MLXNN` are resolved through Swift Package Manager from [`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift).
- `Sparkle` is resolved through Swift Package Manager from [`sparkle-project/Sparkle`](https://github.com/sparkle-project/Sparkle).
- If package resolution is stale/broken, in Xcode run:
  - `File -> Packages -> Reset Package Caches`
  - `File -> Packages -> Resolve Package Versions`

## Releases And Auto-Updates

- The app ships Sparkle, but does not use Sparkle's stock windows. The only surfaced updater UI is the toolbar chip on the right side of the editor toolbar.
- On launch, the updater starts and performs a background check immediately. After that, Sparkle continues checking on the configured interval (`SUScheduledCheckInterval = 3600` seconds).
- The website download CTA should keep pointing at `/download`. That route already redirects to the latest GitHub release DMG, and `/appcast.xml` proxies the latest release's `appcast.xml`.
- `.github/workflows/release.yml` publishes a new GitHub release on every push to `main`, and `scripts/ci/build_release.sh` handles version bumping, archive/export, notarization, DMG creation, and Sparkle appcast generation.

### Required GitHub Secrets

- `BUILD_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`
- `P12_PASSWORD`: password for that `.p12`
- `APPLE_ID`: Apple ID used for notarization
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for `notarytool`
- `APPLE_TEAM_ID`: Apple Developer team ID
- `SPARKLE_PRIVATE_ED_KEY`: private Ed25519 key used by `generate_appcast --ed-key-file`
- `SPARKLE_PUBLIC_ED_KEY`: public Ed25519 key embedded into the app at build time

### Open Source Note

- The Sparkle public key is not sensitive and can be committed once finalized.
- The Sparkle private key must stay out of the repo. Keep it only in GitHub Actions secrets and any trusted local release machines.

### MLX Texo Model Setup

The LaTeX conversion action expects a converted MLX model directory on disk. Runtime inference happens inside the app in Swift using MLX. The Python script is only for one-time weight conversion.

The checked-in weights live in `Scratchpad/TexoMLXModel.bundle/` and are bundled into the app (the `.bundle` suffix keeps the directory intact when Xcode copies resources). `weights.safetensors` (~77 MB) is stored via Git LFS, so:

```bash
# one-time, per machine
brew install git-lfs
git lfs install

# when cloning for the first time (clone will already pull LFS files)
git clone https://github.com/KrishKrosh/Scratchpad.git

# in an existing checkout that predates LFS, fetch the real file
git lfs pull
```

> **TODO:** move to first-run download + cache so the app binary stays lean.
> Tracked in `TexoModelLocator.loadBundle()`.

When you run from Xcode, the app checks these locations automatically (first hit wins):
- `SCRATCHPAD_TEXO_MLX_MODEL` — explicit override
- `.local/TexoMLXModel` inside this worktree — dev override (can be a symlink)
- `TexoMLXModel` in the built app bundle resources — default, picks up the bundled copy
- `~/Library/Application Support/Scratchpad/Models/TexoMLX` — future downloaded cache

For local development you can avoid the 77 MB bundle-copy cost on every debug build by symlinking `.local/TexoMLXModel` at the converted model directory:

1. Prepare a Texo checkpoint and tokenizer locally.
2. Convert the checkpoint:
```bash
python Tools/convert_texo_to_mlx.py \
  --checkpoint /path/to/texo_checkpoint.pt \
  --tokenizer /path/to/Texo/data/tokenizer/tokenizer.json \
  --config /path/to/texo_model_config.json \
  --output ~/Library/Application\\ Support/Scratchpad/Models/TexoMLX
```
3. Link the converted model into the repo for Xcode:
```bash
mkdir -p .local
ln -sfn ~/Library/Application\\ Support/Scratchpad/Models/TexoMLX .local/TexoMLXModel
```

Expected files in that directory:
- `config.json`
- `tokenizer.json`
- `weights.safetensors`

## Current Interaction Notes

- `Cmd+D` toggles drawing mode (see trackpad surface hint in-app).
- `Esc` exits drawing mode.
- Selection supports rectangle/lasso and resize handles.
- Undo/redo flows through `NSUndoManager` in `DocumentModel`.
