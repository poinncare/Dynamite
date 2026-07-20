//
//  ClipboardTextPopupPanel.swift
//  boringNotch — floating full-text panel below selected card (Space popup)
//
//  Non-activating borderless NSPanel so the notch keeps key focus.
//  Matches card fill (semi-transparent) + corner radius; arrow points at card.
//

import AppKit
import SwiftUI

// MARK: - Panel (never becomes key)

final class ClipboardTextPopupNSPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Triangle (points up)

private struct PopupArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - SwiftUI content (card-matched style)

struct ClipboardFullTextPopupContent: View {
    let text: String
    /// Horizontal offset of arrow tip from panel center (pt).
    let arrowOffsetX: CGFloat
    /// Match pre-iter6 card family (~10–12 continuous radius).
    var cornerRadius: CGFloat = 12

    /// Same family as card fill, slightly more opaque so text is readable, still translucent.
    private let fill = Color.white.opacity(0.12)
    private let border = Color.white.opacity(0.12)
    private let arrowH: CGFloat = 8
    private let arrowW: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            PopupArrow()
                .fill(fill)
                .frame(width: arrowW, height: arrowH)
                .background(
                    PopupArrow()
                        .fill(.ultraThinMaterial)
                        .frame(width: arrowW, height: arrowH)
                )
                .offset(x: arrowOffsetX)
                .zIndex(1)

            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.95))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Slight pull so arrow seams into body
            .padding(.top, -1)
        }
    }

    static let arrowHeight: CGFloat = 8
}

// MARK: - Controller

@MainActor
final class ClipboardTextPopupController {
    static let shared = ClipboardTextPopupController()

    private var panel: ClipboardTextPopupNSPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var hostingView: NSHostingView<ClipboardFullTextPopupContent>?

    private let maxSize = CGSize(width: 600, height: 400)
    private let minSize = CGSize(width: 280, height: 72)
    private let gapBelowNotch: CGFloat = 8
    private let screenMargin: CGFloat = 8
    private let arrowH = ClipboardFullTextPopupContent.arrowHeight

    /// Last known selected-card center X in AppKit screen coords (nil → fall back to notch center).
    private var anchorScreenX: CGFloat?
    private var currentText: String = ""

    var isVisible: Bool { panel?.isVisible == true }

    private init() {}

    func show(text: String, anchorScreenX: CGFloat? = nil) {
        currentText = text
        if let anchorScreenX {
            self.anchorScreenX = anchorScreenX
        }
        let bodySize = preferredSize(for: text)
        let totalSize = CGSize(width: bodySize.width, height: bodySize.height + arrowH)
        let layout = layoutFrame(bodySize: bodySize, totalSize: totalSize)

        let root = ClipboardFullTextPopupContent(text: text, arrowOffsetX: layout.arrowOffsetX)
        if let hostingView {
            hostingView.rootView = root
            hostingView.frame = NSRect(origin: .zero, size: totalSize)
        } else {
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: totalSize)
            hostingView = hosting
        }

        let panel = ensurePanel()
        panel.contentView = hostingView
        panel.setFrame(layout.frame, display: true)
        panel.orderFrontRegardless()
        installOutsideClickMonitors()
    }

    /// Update text + re-anchor under a new card without tearing down the panel.
    func update(text: String?, anchorScreenX: CGFloat?) {
        guard isVisible else { return }
        if let anchorScreenX {
            self.anchorScreenX = anchorScreenX
        }
        guard let text, !text.isEmpty else {
            // No text for this item (image/file) — keep last text or hide? hide is cleaner
            hide(postNotification: true)
            return
        }
        show(text: text, anchorScreenX: self.anchorScreenX)
    }

    /// - Parameter postNotification: when true (default), notifies clipboard view to clear popup state (outside click).
    func hide(postNotification: Bool = true) {
        let wasVisible = isVisible
        removeOutsideClickMonitors()
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        }
        panel?.contentView = nil
        hostingView = nil
        anchorScreenX = nil
        currentText = ""
        if wasVisible && postNotification {
            NotificationCenter.default.post(name: .clipboardTextPopupDidHide, object: nil)
        }
    }

    // MARK: - Private

    private struct Layout {
        var frame: NSRect
        var arrowOffsetX: CGFloat
    }

    private func layoutFrame(bodySize: CGSize, totalSize: CGSize) -> Layout {
        let notchWindow = NSApp.windows.first {
            ($0 is BoringNotchSkyLightWindow || $0 is BoringNotchWindow) && $0.isVisible
        }
        let screen = notchWindow?.screen ?? NSScreen.main
        guard let screen else {
            return Layout(frame: NSRect(origin: .zero, size: totalSize), arrowOffsetX: 0)
        }

        let screenFrame = screen.frame
        let notchBottomY: CGFloat
        if let notchWindow {
            notchBottomY = notchWindow.frame.maxY - openNotchSize.height
        } else {
            notchBottomY = screenFrame.maxY - openNotchSize.height
        }

        let targetX = anchorScreenX
            ?? notchWindow.map { $0.frame.midX }
            ?? screenFrame.midX

        // Ideal: panel centered under card
        var panelX = targetX - totalSize.width / 2
        let minX = screenFrame.minX + screenMargin
        let maxX = screenFrame.maxX - totalSize.width - screenMargin
        panelX = min(max(panelX, minX), max(minX, maxX))

        // Arrow offset so tip still points at card center
        let panelCenterX = panelX + totalSize.width / 2
        var arrowOffset = targetX - panelCenterX
        let maxArrow = totalSize.width / 2 - 16
        arrowOffset = min(max(arrowOffset, -maxArrow), maxArrow)

        let y = max(screenFrame.minY + screenMargin, notchBottomY - gapBelowNotch - totalSize.height)

        return Layout(
            frame: NSRect(x: panelX, y: y, width: totalSize.width, height: totalSize.height),
            arrowOffsetX: arrowOffset
        )
    }

    private func ensurePanel() -> ClipboardTextPopupNSPanel {
        if let panel { return panel }

        let p = ClipboardTextPopupNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: minSize.width, height: minSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovable = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .mainMenu + 4
        p.collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        p.appearance = NSAppearance(named: .darkAqua)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        self.panel = p
        return p
    }

    private func preferredSize(for text: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: 12)
        let padding: CGFloat = 24
        let maxTextW = maxSize.width - padding
        let constraint = NSSize(width: maxTextW, height: .greatestFiniteMagnitude)
        let bounds = (text as NSString).boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let width = min(maxSize.width, max(minSize.width, ceil(bounds.width) + padding))
        let height = min(maxSize.height, max(minSize.height, ceil(bounds.height) + padding))
        return CGSize(width: width, height: height)
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isVisible, let panel = self.panel else { return }
            let loc = event.locationInWindow
            let screenPoint: NSPoint
            if let win = event.window {
                screenPoint = win.convertPoint(toScreen: loc)
            } else {
                screenPoint = NSEvent.mouseLocation
            }
            // Ignore clicks inside the notch (allow card interaction while popup open)
            if let notch = NSApp.windows.first(where: {
                ($0 is BoringNotchSkyLightWindow || $0 is BoringNotchWindow) && $0.isVisible
            }), notch.frame.contains(screenPoint) {
                return
            }
            if !panel.frame.contains(screenPoint) {
                self.hide()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            handler(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            handler(event)
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}
