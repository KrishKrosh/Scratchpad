//
//  SelectionContextMenu.swift
//  Scratchpad
//
//  Floating context menu anchored to the top-right of a selection.
//  Default-closed; click the ⋯ button to open. Matches the toolbar's
//  glass/material look and flashes a "Copied" confirmation when LaTeX
//  is copied.
//

import SwiftUI

struct SelectionContextMenu: View {
    enum Mode {
        case inkSelection
        case renderedLatex
    }

    /// Screen-space rect of the current selection (used to position the menu).
    let rect: CGRect
    /// True while a model run is in-flight. Displayed via the ⋯ spinner even
    /// when the panel is collapsed — intentionally does NOT auto-expand.
    let isBusy: Bool
    let mode: Mode
    /// A value that changes whenever the underlying selection identity does.
    /// Used to reset the open/closed state when the user picks something new.
    let selectionKey: AnyHashable

    let onConvert: () -> Void
    let onCopyLatex: () -> Void
    let onRevertToHandwriting: () -> Void

    // Fixed panel width so the menu never grows to fill the screen.
    private let panelWidth: CGFloat = 220

    @State private var isExpanded: Bool = false
    @State private var showCopyConfirmation: Bool = false
    @State private var copyResetTask: DispatchWorkItem?

    private var isPanelVisible: Bool {
        isExpanded || showCopyConfirmation
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isPanelVisible {
                panel
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)),
                            removal:   .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                        )
                    )
            }
            ellipsisButton
        }
        // Fixed-width frame so `.position(...)` has a finite layout rectangle
        // and children can sit flush-right without the panel blowing out to
        // fill the window. `allowsHitTesting` on the outer VStack is implicit;
        // hit-testing happens only on the actual button subviews.
        .frame(width: panelWidth, alignment: .trailing)
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: isPanelVisible)
        .position(
            x: max(rect.maxX - panelWidth / 2, panelWidth / 2 + 12),
            y: max(rect.minY - 24, 44)
        )
        .onChange(of: selectionKey) { _, _ in
            // New selection → reset to the default collapsed state.
            isExpanded = false
            cancelCopyConfirmation()
        }
        .onChange(of: mode) { _, _ in
            cancelCopyConfirmation()
        }
    }

    // MARK: - Panel content

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch mode {
            case .inkSelection:
                actionRow(
                    title: isBusy ? "Converting..." : "Convert to LaTeX",
                    systemImage: "function",
                    spinning: isBusy,
                    disabled: isBusy,
                    action: handleConvert
                )
            case .renderedLatex:
                if showCopyConfirmation {
                    confirmationRow(
                        title: "LaTeX copied",
                        systemImage: "checkmark.circle.fill"
                    )
                } else {
                    actionRow(
                        title: "Copy LaTeX",
                        systemImage: "doc.on.doc",
                        action: handleCopy
                    )
                }
                actionRow(
                    title: "Back to Handwriting",
                    systemImage: "scribble.variable",
                    disabled: isBusy,
                    action: handleRevert
                )
            }
        }
        .padding(4)
        .frame(width: panelWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
    }

    // MARK: - Ellipsis trigger

    private var ellipsisButton: some View {
        Button {
            if isBusy { return }
            isExpanded.toggle()
        } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    /// A tappable row. Background is transparent by default and only tints
    /// when the cursor is actually on top of THIS row — no more "looks
    /// pre-hovered" problem.
    private func actionRow(
        title: String,
        systemImage: String,
        spinning: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        RowHoverButton(
            title: title,
            systemImage: systemImage,
            spinning: spinning,
            disabled: disabled,
            tint: .primary,
            action: action
        )
    }

    /// Non-interactive confirmation state (e.g. "LaTeX copied").
    private func confirmationRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(.green)
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action handlers

    private func handleConvert() {
        onConvert()
        // Collapse so the busy spinner on the ⋯ button carries the feedback.
        // If the user wants to re-open the menu mid-run, they can still click.
        isExpanded = false
    }

    private func handleRevert() {
        onRevertToHandwriting()
        isExpanded = false
    }

    private func handleCopy() {
        onCopyLatex()
        cancelCopyConfirmation()
        withAnimation(.easeOut(duration: 0.18)) {
            showCopyConfirmation = true
        }
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.22)) {
                showCopyConfirmation = false
            }
        }
        copyResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)
    }

    private func cancelCopyConfirmation() {
        copyResetTask?.cancel()
        copyResetTask = nil
        if showCopyConfirmation { showCopyConfirmation = false }
    }
}

// MARK: - Per-row hover button

/// A single menu row whose background is transparent until the cursor is
/// actually over it. Lives in its own view so `@State private var isHovered`
/// is scoped to just that row — a single parent-level hover flag would light
/// up every row at once.
private struct RowHoverButton: View {
    let title: String
    let systemImage: String
    let spinning: Bool
    let disabled: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if spinning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(disabled ? .secondary : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            // No delay needed — hover only changes the row highlight, never
            // the open/closed state of the menu itself.
            isHovered = hovering && !disabled
        }
    }

    private var rowFill: Color {
        if isHovered {
            // Soft accent tint on hover — matches the toolbar's selected-tool
            // fill style so the menu feels like part of the same family.
            return Color.accentColor.opacity(0.14)
        }
        return .clear
    }
}

// MARK: - Diffusion animation overlay

/// A soft, animated gradient flash drawn over the selection rect while a
/// conversion is in flight. The goal is to make ink→LaTeX (and back) feel
/// like the content is "diffusing" through the model rather than snapping.
struct DiffusionOverlay: View {
    /// Screen-space rect the overlay should cover. If nil, the overlay
    /// collapses cleanly.
    let rect: CGRect?

    @State private var angle: Double = 0
    @State private var pulse: Double = 0

    var body: some View {
        ZStack {
            if let rect {
                diffusionFlash
                    .frame(width: rect.width + 36, height: rect.height + 36)
                    .position(x: rect.midX, y: rect.midY)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.28), value: rect != nil)
        .onAppear { startAnimations() }
    }

    private var diffusionFlash: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.10 + 0.06 * pulse))
                .blur(radius: 14)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.55, green: 0.45, blue: 0.96).opacity(0.55),
                            Color(red: 0.30, green: 0.72, blue: 0.95).opacity(0.45),
                            Color(red: 0.96, green: 0.54, blue: 0.72).opacity(0.50),
                            Color(red: 0.55, green: 0.45, blue: 0.96).opacity(0.55)
                        ]),
                        center: .center,
                        angle: .degrees(angle)
                    )
                )
                .blur(radius: 18)
                .blendMode(.plusLighter)
                .opacity(0.85)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.55),
                            Color.accentColor.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .opacity(0.75)
        }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            angle = 360
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulse = 1
        }
    }
}
