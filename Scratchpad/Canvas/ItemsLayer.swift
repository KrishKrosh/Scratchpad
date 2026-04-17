//
//  ItemsLayer.swift
//  Scratchpad
//
//  Renders text boxes, shapes, and images in document space with the
//  current pan/zoom transform applied.
//

import SwiftUI
import AppKit

struct ItemsLayer: View {
    let items: [CanvasItem]
    let panOffset: CGSize
    let zoom: CGFloat
    let selection: Set<UUID>
    let editingTextID: UUID?
    let onEditText: (UUID, String) -> Void
    let onEndTextEditing: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(items) { item in
                    itemView(for: item, in: proxy.size)
                }
            }
            .allowsHitTesting(true)
        }
    }

    /// Convert document-space rect into screen-space rect using the canvas transform.
    private func screenRect(for docRect: CGRect, in size: CGSize) -> CGRect {
        let cx = size.width / 2 + panOffset.width
        let cy = size.height / 2 + panOffset.height
        return CGRect(
            x: cx + docRect.origin.x * zoom,
            y: cy + docRect.origin.y * zoom,
            width: docRect.width * zoom,
            height: docRect.height * zoom
        )
    }

    @ViewBuilder
    private func itemView(for item: CanvasItem, in size: CGSize) -> some View {
        let r = screenRect(for: item.frame, in: size)
        Group {
            switch item.kind {
            case .text(let content):
                textView(content: content, item: item)
            case .shape(let kind, let color, let width):
                shapeView(kind: kind, color: color.color, width: width * zoom)
            case .image(let data):
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                }
            }
        }
        .frame(width: max(r.width, 1), height: max(r.height, 1))
        .position(x: r.midX, y: r.midY)
        .allowsHitTesting(editingTextID == item.id)
    }

    @ViewBuilder
    private func textView(content: CanvasItem.TextContent, item: CanvasItem) -> some View {
        if editingTextID == item.id {
            EditableTextBox(
                text: Binding(
                    get: { content.text },
                    set: { onEditText(item.id, $0) }
                ),
                fontSize: content.fontSize * zoom,
                color: content.color.color,
                onEndEditing: onEndTextEditing
            )
            .allowsHitTesting(true)
        } else {
            Text(content.text.isEmpty ? " " : content.text)
                .font(.system(size: content.fontSize * zoom))
                .foregroundStyle(content.color.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(4)
        }
    }

    @ViewBuilder
    private func shapeView(kind: ShapeKind, color: Color, width: CGFloat) -> some View {
        switch kind {
        case .rectangle:
            Rectangle().stroke(color, lineWidth: max(width, 0.5))
        case .ellipse:
            Ellipse().stroke(color, lineWidth: max(width, 0.5))
        case .line:
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: 10_000, y: 10_000))
            }
            .stroke(color, lineWidth: max(width, 0.5))
        case .arrow:
            ArrowShape()
                .stroke(color, lineWidth: max(width, 0.5))
        }
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Arrowhead
        let head: CGFloat = min(rect.width, rect.height) * 0.25
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - head, y: rect.maxY - head * 0.3))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - head * 0.3, y: rect.maxY - head))
        return p
    }
}

// MARK: - Editable text box (AppKit-backed)

private struct EditableTextBox: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var color: Color
    var onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEndEditing: onEndEditing)
    }

    func makeNSView(context: Context) -> NSTextView {
        let tv = NSTextView()
        tv.isEditable = true
        tv.isRichText = false
        tv.drawsBackground = false
        tv.delegate = context.coordinator
        tv.string = text
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = NSColor(color)
        tv.focusRingType = .none
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }
        return tv
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != text { nsView.string = text }
        nsView.font = NSFont.systemFont(ofSize: fontSize)
        nsView.textColor = NSColor(color)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let onEndEditing: () -> Void
        init(text: Binding<String>, onEndEditing: @escaping () -> Void) {
            self.text = text
            self.onEndEditing = onEndEditing
        }
        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView {
                text.wrappedValue = tv.string
            }
        }
        func textDidEndEditing(_ notification: Notification) {
            onEndEditing()
        }
    }
}
