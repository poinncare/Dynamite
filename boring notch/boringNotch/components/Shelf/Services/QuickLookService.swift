//
//  QuickLookService.swift
//  boringNotch
//
//  System Quick Look via QLPreviewPanel only (no SwiftUI .quickLookPreview —
//  dual presentation was fighting over frame/size).
//  Fixed square window, locked min=max, sized once without animation.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import QuickLookUI
import AppKit

@MainActor
final class QuickLookService: ObservableObject {
    @Published var urls: [URL] = []
    @Published var selectedURL: URL?
    @Published var isQuickLookOpen: Bool = false

    private var scopedURLs: [URL] = []
    private let host = QuickLookHostController.shared

    func show(urls: [URL], selectFirst: Bool = true, slideshow: Bool = false) {
        guard !urls.isEmpty else { return }

        releaseSecurityScopes()

        var scoped: [URL] = []
        for url in urls where url.isFileURL {
            if url.startAccessingSecurityScopedResource() {
                scoped.append(url)
            }
        }
        scopedURLs = scoped

        self.urls = urls
        self.isQuickLookOpen = true
        self.selectedURL = selectFirst ? urls.first : (selectedURL.flatMap { urls.contains($0) ? $0 : nil } ?? urls.first)

        // If already open, only swap items — do not re-open / re-animate the panel.
        if host.isPanelVisible {
            host.reload(urls: urls)
            return
        }

        host.present(urls: urls) { [weak self] in
            Task { @MainActor in
                self?.handlePanelClosedExternally()
            }
        }
    }

    func hide() {
        host.dismiss()
        finishClosed()
    }

    func showQuickLook(urls: [URL]) {
        show(urls: urls, selectFirst: true, slideshow: false)
    }

    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen else { return }
        show(urls: urls, selectFirst: true)
    }

    private func handlePanelClosedExternally() {
        guard isQuickLookOpen else { return }
        finishClosed()
    }

    private func finishClosed() {
        releaseSecurityScopes()
        selectedURL = nil
        urls.removeAll()
        isQuickLookOpen = false
    }

    private func releaseSecurityScopes() {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        scopedURLs.removeAll()
    }
}

// MARK: - Fixed square (locked)

enum QuickLookPanelSizing {
    /// Constant outer size for every content type.
    private static let preferredSide: CGFloat = 640
    private static let screenMargin: CGFloat = 48
    private static let maxScreenFraction: CGFloat = 0.70

    static func squareSide(on screen: NSScreen) -> CGFloat {
        let visible = screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let maxSide = min(visible.width, visible.height) * maxScreenFraction
        return min(preferredSide, maxSide).rounded(.down)
    }

    static func preferredFrame(on screen: NSScreen) -> NSRect {
        let s = squareSide(on: screen)
        let visible = screen.visibleFrame
        return NSRect(
            x: (visible.midX - s / 2).rounded(.down),
            y: (visible.midY - s / 2).rounded(.down),
            width: s,
            height: s
        )
    }

    /// Apply once: fixed frame + hard min/max lock so QL cannot auto-resize.
    static func lockSquare(on panel: QLPreviewPanel) {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = preferredFrame(on: screen)
        let size = frame.size

        // Lock before setFrame so internal layout cannot grow/shrink the window.
        panel.minSize = size
        panel.maxSize = size
        panel.setFrame(frame, display: true, animate: false)

        // Re-assert lock after setFrame (some AppKit paths reset min/max).
        panel.minSize = size
        panel.maxSize = size
    }
}

// MARK: - Host window + first responder

private final class QuickLookKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickLookHostController {
    static let shared = QuickLookHostController()

    private var hostPanel: NSPanel?
    private let hostView = QuickLookHostView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
    private var visibilityTimer: Timer?
    private var onClose: (() -> Void)?
    private var isPresenting = false

    var isPanelVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    private init() {}

    func present(urls: [URL], onClose: @escaping () -> Void) {
        self.onClose = onClose
        hostView.urls = urls
        hostView.onUserClosed = { [weak self] in
            self?.handleUserClosed()
        }

        let host = ensureHostPanel()
        NSApp.activate(ignoringOtherApps: true)
        host.alphaValue = 0
        host.orderFrontRegardless()
        host.makeKeyAndOrderFront(nil)
        host.makeFirstResponder(hostView)

        guard let ql = QLPreviewPanel.shared() else {
            fallbackQLManage(urls: urls)
            return
        }

        isPresenting = true

        ql.updateController()
        if ql.dataSource == nil {
            ql.dataSource = hostView
            ql.delegate = hostView
        }

        // Size + lock BEFORE the panel appears, so the user never sees a wrong size.
        QuickLookPanelSizing.lockSquare(on: ql)

        ql.currentPreviewItemIndex = 0
        ql.reloadData()
        ql.makeKeyAndOrderFront(nil)

        // One more lock after show (no animation) — content load must not change frame.
        QuickLookPanelSizing.lockSquare(on: ql)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let ql = QLPreviewPanel.shared(), ql.isVisible {
                QuickLookPanelSizing.lockSquare(on: ql)
                self.startVisibilityWatch()
            } else {
                self.fallbackQLManage(urls: urls)
            }
            self.isPresenting = false
        }
    }

    /// Swap preview items while the panel stays put (no reopen / no resize dance).
    func reload(urls: [URL]) {
        hostView.urls = urls
        guard let ql = QLPreviewPanel.shared() else { return }
        if ql.dataSource == nil {
            ql.dataSource = hostView
            ql.delegate = hostView
        }
        ql.currentPreviewItemIndex = 0
        ql.reloadData()
        // Keep the same locked square — never re-center/re-animate.
        QuickLookPanelSizing.lockSquare(on: ql)
    }

    func dismiss() {
        stopVisibilityWatch()
        if let ql = QLPreviewPanel.shared(), ql.isVisible {
            ql.orderOut(nil)
        }
        clearPanelDataSource()
        hostPanel?.orderOut(nil)
        hostView.urls = []
        onClose = nil
    }

    private func handleUserClosed() {
        stopVisibilityWatch()
        clearPanelDataSource()
        hostPanel?.orderOut(nil)
        hostView.urls = []
        let cb = onClose
        onClose = nil
        cb?()
    }

    private func startVisibilityWatch() {
        stopVisibilityWatch()
        // Only detect close — never touch frame/size here.
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let visible = QLPreviewPanel.shared()?.isVisible == true
                if !visible, !self.isPresenting {
                    self.handleUserClosed()
                }
            }
        }
    }

    private func stopVisibilityWatch() {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
    }

    private func clearPanelDataSource() {
        if let ql = QLPreviewPanel.shared() {
            if ql.dataSource as AnyObject? === hostView {
                ql.dataSource = nil
            }
            if ql.delegate as AnyObject? === hostView {
                ql.delegate = nil
            }
        }
    }

    private func ensureHostPanel() -> NSPanel {
        if let hostPanel { return hostPanel }

        let p = QuickLookKeyPanel(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 4, height: 4),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.alphaValue = 0
        p.contentView = hostView
        hostPanel = p
        return p
    }

    private func fallbackQLManage(urls: [URL]) {
        let paths = urls.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else {
            handleUserClosed()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p"] + paths
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.handleUserClosed()
                }
            }
        } catch {
            handleUserClosed()
        }
    }
}

/// First-responder view that QLPreviewPanel discovers in the responder chain.
final class QuickLookHostView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []
    var onUserClosed: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !urls.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        if panel.currentPreviewItemIndex < 0 || panel.currentPreviewItemIndex >= urls.count {
            panel.currentPreviewItemIndex = 0
        }
        // Lock size only — no animated resize.
        QuickLookPanelSizing.lockSquare(on: panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        DispatchQueue.main.async { [weak self] in
            if QLPreviewPanel.shared()?.isVisible != true {
                self?.onUserClosed?()
            }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as QLPreviewItem
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.keyCode == 49 {
            panel.orderOut(nil)
            return true
        }
        return false
    }

    /// Suppress zoom-from-source animation (was a source of size thrash).
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        .zero
    }

    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        nil
    }
}

// MARK: - SwiftUI helper (no longer presents QL itself)

struct QuickLookPresenter: ViewModifier {
    @ObservedObject var service: QuickLookService

    func body(content: Content) -> some View {
        // Intentionally no `.quickLookPreview` — AppKit QLPreviewPanel owns presentation.
        content
    }
}

extension View {
    func quickLookPresenter(using service: QuickLookService) -> some View {
        self.modifier(QuickLookPresenter(service: service))
    }
}
