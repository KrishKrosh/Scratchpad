//
//  TrackpadInputManager.swift
//  Scratchpad
//

import Foundation
import Combine
import QuartzCore
import OpenMultitouchSupport

/// A snapshot of one finger on the trackpad, in 0...1 normalized coordinates.
/// y is already flipped so that 0 = top, 1 = bottom (matches canvas coords).
struct NormalizedTouch: Identifiable, Hashable {
    let id: Int32
    let x: CGFloat
    let y: CGFloat
    let pressure: CGFloat
    let isContact: Bool  // true if physically touching (not just hovering)
    let isHovering: Bool
    let timestamp: TimeInterval
}

/// Wraps OpenMultitouchSupport and surfaces the latest per-frame set of touches
/// via a Combine publisher. Always listens (both for drawing and for the hover
/// cursor), so the user sees their finger position even outside drawing mode.
@MainActor
final class TrackpadInputManager: ObservableObject {

    /// Most recent batch of touches from the trackpad, 0 or more fingers.
    @Published private(set) var touches: [NormalizedTouch] = []

    /// Whether the underlying listener is active.
    @Published private(set) var isListening: Bool = false

    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?

    func start() {
        guard !isListening else { return }
        isListening = manager.startListening()

        task = Task { [weak self] in
            guard let stream = self?.manager.touchDataStream else { return }
            for await batch in stream {
                await MainActor.run {
                    self?.ingest(batch)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if isListening {
            _ = manager.stopListening()
            isListening = false
        }
        touches = []
    }

    private func ingest(_ batch: [OMSTouchData]) {
        // Keep only meaningful states. Drop "leaving" / "notTouching" so the
        // cursor doesn't linger after lift-off.
        let filtered = batch.compactMap { d -> NormalizedTouch? in
            let isContact: Bool
            let isHovering: Bool
            switch d.state {
            case .starting, .making, .touching, .lingering:
                isContact = true
                isHovering = false
            case .hovering:
                isContact = false
                isHovering = true
            case .breaking, .leaving, .notTouching:
                return nil
            }
            // OMS y: 0 at bottom, 1 at top. Flip for screen coords.
            let nx = CGFloat(max(0, min(1, d.position.x)))
            let ny = CGFloat(max(0, min(1, 1.0 - d.position.y)))
            return NormalizedTouch(
                id: d.id,
                x: nx,
                y: ny,
                pressure: CGFloat(max(0, d.pressure)),
                isContact: isContact,
                isHovering: isHovering,
                timestamp: CACurrentMediaTime()
            )
        }
        touches = filtered
    }

    deinit {
        task?.cancel()
    }
}
