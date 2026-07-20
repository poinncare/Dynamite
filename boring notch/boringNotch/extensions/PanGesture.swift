//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // If the cursor is over a scrollable area that can still scroll in this
            // direction, let the ScrollView consume the event and do NOT start a
            // notch close/open pan. At the edge (or outside a scroll view), keep
            // the swipe-to-collapse gesture working.
            if scrollViewCanAbsorb(event, direction: direction) {
                // Reset any in-progress pan so mixed scroll→pan doesn't jump-close.
                if active {
                    action(0, .ended)
                    active = false
                    accumulated = 0
                }
                return
            }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }

        /// True when an NSScrollView under the cursor still has room to scroll
        /// along `direction` — then notch pan must not steal the gesture.
        private func scrollViewCanAbsorb(_ event: NSEvent, direction: PanDirection) -> Bool {
            guard let window = event.window,
                  let contentView = window.contentView else { return false }
            let point = contentView.convert(event.locationInWindow, from: nil)
            guard let hit = contentView.hitTest(point) else { return false }

            var node: NSView? = hit
            while let view = node {
                if let scroll = view as? NSScrollView {
                    return scroll.hasScrollRoom(in: direction)
                }
                if let clip = view as? NSClipView, let scroll = clip.superview as? NSScrollView {
                    return scroll.hasScrollRoom(in: direction)
                }
                // SwiftUI hosts scrolling content in nested private views — walk parents.
                node = view.superview
            }
            return false
        }
    }
}

private extension NSScrollView {
    /// Whether the document can still move in the pan-gesture direction.
    func hasScrollRoom(in direction: PanDirection) -> Bool {
        guard let doc = documentView else { return false }
        let visible = contentView.documentVisibleRect
        let bounds = doc.isFlipped ? doc.bounds : doc.bounds
        // Normalize to flipped-like “origin at top-left of content”
        let contentH = bounds.height
        let contentW = bounds.width
        let visH = visible.height
        let visW = visible.width
        let maxY = max(0, contentH - visH)
        let maxX = max(0, contentW - visW)
        let y = visible.origin.y
        let x = visible.origin.x
        let edge: CGFloat = 1.5

        switch direction {
        case .up:
            // Close-notch pan maps to “scroll content further toward bottom” on flipped views
            // (finger swipe up). If not yet at bottom, let scroll absorb.
            if doc.isFlipped {
                return y < maxY - edge
            } else {
                return y > edge
            }
        case .down:
            if doc.isFlipped {
                return y > edge
            } else {
                return y < maxY - edge
            }
        case .left:
            return x > edge
        case .right:
            return x < maxX - edge
        }
    }
}
