//
//  HomeView.swift
//  Scratchpad
//
//  Grid of all .scratchpad files, with previews, rename, delete, and open.
//

import SwiftUI
import AppKit

struct HomeView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var entries: [Persistence.DocEntry] = []
    @State private var refreshTick: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 18)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(entries) { entry in
                        DocTile(entry: entry, onOpen: {
                            openWindow(value: entry.url)
                        }, onDelete: {
                            try? FileManager.default.trashItem(
                                at: entry.url, resultingItemURL: nil
                            )
                            reload()
                        })
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { reload() }
    }

    private var header: some View {
        HStack {
            Text("Scratchpads")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Spacer()
            Button {
                let url = Persistence.newAutosaveURL(title: "Untitled")
                let empty = ScratchpadFile(
                    title: "Untitled",
                    paperStyle: .dots,
                    strokes: [],
                    items: []
                )
                try? Persistence.save(empty, to: url)
                openWindow(value: url)
                reload()
            } label: {
                Label("New Scratchpad", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func reload() {
        entries = Persistence.list()
    }
}

private struct DocTile: View {
    let entry: Persistence.DocEntry
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                DocPreview(url: entry.url)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(height: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovered ? 0.25 : 0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(formatted(entry.modified))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { onOpen() }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Text("Move to Trash") }
        }
    }

    private func formatted(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

/// Lightweight preview of a .scratchpad file — renders strokes into a
/// thumbnail via SwiftUI's Canvas.
private struct DocPreview: View {
    let url: URL
    @State private var file: ScratchpadFile?

    var body: some View {
        Group {
            if let file {
                GeometryReader { proxy in
                    Canvas { ctx, size in
                        render(file: file, in: ctx, size: size)
                    }
                }
            } else {
                Color.clear
            }
        }
        .onAppear { file = try? Persistence.load(from: url) }
    }

    private func render(file: ScratchpadFile, in ctx: GraphicsContext, size: CGSize) {
        let bounds = contentBounds(file)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(size.width / bounds.width, size.height / bounds.height) * 0.9
        var ctx = ctx
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.midX, y: -bounds.midY)

        for s in file.strokes {
            drawStroke(s, in: &ctx)
        }
    }

    private func contentBounds(_ file: ScratchpadFile) -> CGRect {
        var rect: CGRect?
        for s in file.strokes { rect = rect?.union(s.bounds) ?? s.bounds }
        for i in file.items { rect = rect?.union(i.frame) ?? i.frame }
        return rect ?? CGRect(x: 0, y: 0, width: 400, height: 300)
    }

    private func drawStroke(_ stroke: Stroke, in ctx: inout GraphicsContext) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.move(to: stroke.points[0].location)
        for p in stroke.points.dropFirst() {
            path.addLine(to: p.location)
        }
        ctx.stroke(
            path,
            with: .color(stroke.swiftUIColor.opacity(stroke.opacity)),
            lineWidth: stroke.width
        )
    }
}
