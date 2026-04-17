//
//  ToolbarView.swift
//  Scratchpad
//
//  Floating glass toolbar at the top of the window.
//

import SwiftUI

/// Export formats surfaced by the toolbar's share menu.
enum ExportFormat {
    case png, pdf, scratchpad
}

struct ToolbarView: View {
    @ObservedObject var doc: DocumentModel
    let onHome: () -> Void
    let onExport: (ExportFormat) -> Void
    let onNewDocument: () -> Void
    let onClear: () -> Void
    /// True while ⌘ is held — each tool button shows its 1-based digit shortcut.
    var cmdHeld: Bool = false

    @State private var titleDraft: String = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            leftCluster
            Spacer(minLength: 12)
            middleCluster
            Spacer(minLength: 12)
            rightCluster
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .glassToolbarBackgroundIfAvailable()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 4)
        .onAppear { titleDraft = doc.title }
        .onChange(of: doc.title) { _, new in
            if !titleFocused { titleDraft = new }
        }
    }

    // MARK: - Left: document + paper

    private var leftCluster: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "square.grid.2x2", tint: .secondary, action: onHome)
                .help("Home — all scratchpads")

            TextField("Title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .focused($titleFocused)
                .frame(minWidth: 80, idealWidth: 160, maxWidth: 240)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 2)
                .padding(.trailing, 8)
                .onSubmit {
                    commitTitle()
                    titleFocused = false
                }
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitTitle() }
                }

            Divider().frame(height: 20)

            Menu {
                Section("Paper") {
                    ForEach(PaperStyle.allCases) { style in
                        Button {
                            doc.paperStyle = style
                        } label: {
                            Label(style.label, systemImage: style.symbol)
                        }
                    }
                }
                Section("Canvas") {
                    ForEach(CanvasStyle.allCases) { s in
                        Button {
                            doc.canvasStyle = s
                        } label: {
                            Label(s.label, systemImage: s.symbol)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: doc.paperStyle.symbol)
                    Text(doc.paperStyle.label)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: doc.canvasStyle == .page ? "doc" : "")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Paper & canvas style")
        }
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = trimmed.isEmpty ? doc.title : trimmed
        if final != doc.title { doc.title = final }
        if titleDraft != final { titleDraft = final }
    }

    // MARK: - Middle: tools

    private var middleCluster: some View {
        HStack(spacing: 4) {
            ForEach(Array(ToolKind.allCases.enumerated()), id: \.element.id) { index, tool in
                toolEntry(for: tool, shortcut: index + 1)
            }

            Divider().frame(height: 22).padding(.horizontal, 4)

            // Color palette — applies to selection when non-empty, otherwise
            // just sets the "next stroke" color.
            HStack(spacing: 4) {
                ForEach(Array(doc.palette.enumerated()), id: \.offset) { _, c in
                    ColorSwatch(color: c, isSelected: doc.color.description == c.description) {
                        doc.color = c
                        if !doc.selection.isEmpty {
                            doc.applyColorToSelection(c)
                        }
                    }
                }
            }

            Divider().frame(height: 22).padding(.horizontal, 4)

            // Line-width slider — applies to selection when non-empty.
            HStack(spacing: 6) {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(currentWidth) },
                        set: { setCurrentWidth(CGFloat($0)) }
                    ),
                    in: 1...40
                )
                .frame(width: 90)
            }
        }
    }

    /// Build the button (possibly with a chevron sidecar menu) for `tool`.
    /// Index determines the ⌘-digit shortcut shown when `cmdHeld`.
    @ViewBuilder
    private func toolEntry(for tool: ToolKind, shortcut: Int) -> some View {
        switch tool {
        case .shape:
            SplitToolButton(
                symbol: tool.symbol,
                label: tool.label,
                isSelected: doc.tool == .shape,
                color: doc.color,
                shortcut: shortcut,
                cmdHeld: cmdHeld,
                onActivate: { doc.tool = .shape }
            ) {
                ForEach(ShapeKind.allCases) { kind in
                    Button {
                        doc.shapeKind = kind
                        doc.tool = .shape
                    } label: {
                        Label(kind.label, systemImage: kind.symbol)
                    }
                }
            }
        case .select:
            SplitToolButton(
                symbol: tool.symbol,
                label: tool.label,
                isSelected: doc.tool == .select,
                color: doc.color,
                shortcut: shortcut,
                cmdHeld: cmdHeld,
                onActivate: { doc.tool = .select }
            ) {
                ForEach(SelectMode.allCases) { m in
                    Button {
                        doc.selectMode = m
                        doc.tool = .select
                    } label: {
                        Label(m.label, systemImage: m.symbol)
                    }
                }
            }
        default:
            ToolButton(
                tool: tool,
                isSelected: doc.tool == tool,
                color: doc.color,
                shortcut: shortcut,
                cmdHeld: cmdHeld
            ) {
                doc.tool = tool
            }
        }
    }

    // MARK: - Right: clear / new / share

    private var rightCluster: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "trash", tint: .secondary, action: onClear)
                .help("Clear canvas")

            IconButton(systemName: "doc.badge.plus", tint: .secondary, action: onNewDocument)
                .help("New document")

            Menu {
                Button("Export as PNG")         { onExport(.png) }
                Button("Export as PDF")         { onExport(.pdf) }
                Button("Export as .scratchpad") { onExport(.scratchpad) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Export as PNG / PDF / .scratchpad")
        }
    }

    // MARK: helpers

    private var currentWidth: CGFloat {
        if !doc.selection.isEmpty,
           let first = doc.strokes.first(where: { doc.selection.contains($0.id) }) {
            return first.width
        }
        switch doc.tool {
        case .highlighter: return doc.highlighterWidth
        case .eraser:      return doc.eraserWidth
        default:           return doc.lineWidth
        }
    }

    private func setCurrentWidth(_ v: CGFloat) {
        if !doc.selection.isEmpty {
            doc.applyWidthToSelection(v)
            return
        }
        switch doc.tool {
        case .highlighter: doc.highlighterWidth = v
        case .eraser:      doc.eraserWidth = v
        default:           doc.lineWidth = v
        }
    }
}

// MARK: - Subcomponents

/// Shared visual for a tool slot. Handles the selected outline/fill and the
/// small ⌘-digit badge shown in the bottom-right corner when ⌘ is held.
private struct ToolTile: View {
    let symbol: String
    let isSelected: Bool
    let color: Color
    let shortcut: Int
    let cmdHeld: Bool
    var trailingChevron: Bool = false
    var width: CGFloat = 32
    var height: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? color.opacity(0.18) : Color.clear)

            HStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? color : .secondary)
                if trailingChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }

            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.85), lineWidth: 1.2)
            }

            if cmdHeld {
                Text("\(shortcut)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 12, minHeight: 12)
                    .background(
                        Circle().fill(Color.black.opacity(0.7))
                    )
                    .offset(x: width / 2 - 6, y: height / 2 - 6)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct ToolButton: View {
    let tool: ToolKind
    let isSelected: Bool
    let color: Color
    let shortcut: Int
    let cmdHeld: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolTile(
                symbol: tool.symbol,
                isSelected: isSelected,
                color: color,
                shortcut: shortcut,
                cmdHeld: cmdHeld
            )
        }
        .buttonStyle(.plain)
        .help(tool.label)
    }
}

/// A tool slot that is split into two hit regions: the main icon activates
/// the tool; a small chevron on the right opens a submenu of tool options.
/// This keeps the "it is selected" affordance visible on the main button.
private struct SplitToolButton<Content: View>: View {
    let symbol: String
    let label: String
    let isSelected: Bool
    let color: Color
    let shortcut: Int
    let cmdHeld: Bool
    let onActivate: () -> Void
    @ViewBuilder let menuContent: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? color.opacity(0.18) : Color.clear)
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.85), lineWidth: 1.2)
            }

            HStack(spacing: 0) {
                Button(action: onActivate) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? color : .secondary)
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(label)

                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isSelected ? color : .secondary.opacity(0.75))
                        .frame(width: 10, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("\(label) options")
            }

            if cmdHeld {
                Text("\(shortcut)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 12, minHeight: 12)
                    .background(Circle().fill(Color.black.opacity(0.7)))
                    .offset(x: 12, y: 8)
            }
        }
        .frame(width: 36, height: 28)
    }
}

private struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .shadow(color: color.opacity(0.35), radius: 3, x: 0, y: 1)
                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
}

private struct IconButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func glassToolbarBackgroundIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: 18))
        } else {
            self
        }
    }
}
