//
//  QuickLookService.swift
//  Dynamite
//
//  System Quick Look via QLPreviewPanel.
//  Media (images / video) is shown at its natural aspect ratio — no forced
//  square window or letterbox “frames”. Window is fitted to content and capped
//  by the screen, then left alone so QL does not thrash on browse.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import QuickLookUI
import AppKit
import AVFoundation
import ImageIO

@MainActor
final class QuickLookService: ObservableObject {
    @Published var urls: [URL] = []
    @Published var selectedURL: URL?
    @Published var isQuickLookOpen: Bool = false

    private var scopedURLs: [URL] = []
    private let host = QuickLookHostController.shared

    func show(urls: [URL], selectFirst: Bool = true, slideshow: Bool = false) {
        guard !urls.isEmpty else { return }
        let isUpdatingOpenPreview = isQuickLookOpen

        var newScoped: [URL] = []
        for url in urls where url.isFileURL {
            if url.startAccessingSecurityScopedResource() {
                newScoped.append(url)
            }
        }
        let previousScoped = scopedURLs
        scopedURLs = newScoped
        for url in previousScoped where !newScoped.contains(url) {
            url.stopAccessingSecurityScopedResource()
        }

        self.urls = urls
        self.isQuickLookOpen = true
        self.selectedURL = selectFirst ? urls.first : (selectedURL.flatMap { urls.contains($0) ? $0 : nil } ?? urls.first)

        let onClose: () -> Void = { [weak self] in
            Task { @MainActor in
                self?.handlePanelClosedExternally()
            }
        }

        if isUpdatingOpenPreview {
            host.reload(urls: urls, onClose: onClose)
            return
        }

        host.present(urls: urls, onClose: onClose)
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

// MARK: - Content-fit sizing (natural aspect ratio)

enum QuickLookPanelSizing {
    private static let screenMargin: CGFloat = 48
    private static let maxScreenFraction: CGFloat = 0.78
    /// Fallback when we cannot probe media size.
    private static let fallbackSize = NSSize(width: 720, height: 480)
    private static let minSize = NSSize(width: 280, height: 200)

    /// Natural pixel size of the first previewable item, if known.
    static func contentSize(for urls: [URL]) -> NSSize {
        guard let url = urls.first else { return fallbackSize }
        if let imageSize = imagePixelSize(url) {
            return imageSize
        }
        if let videoSize = videoPixelSize(url) {
            return videoSize
        }
        return fallbackSize
    }

    /// Frame that fits `content` into the screen while keeping aspect ratio.
    static func preferredFrame(for urls: [URL], on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let maxW = max(minSize.width, visible.width * maxScreenFraction)
        let maxH = max(minSize.height, visible.height * maxScreenFraction)

        let raw = contentSize(for: urls)
        let srcW = max(raw.width, 1)
        let srcH = max(raw.height, 1)

        let scale = min(maxW / srcW, maxH / srcH, 1.0) // never upscale beyond native
        // For tiny assets still give a usable window; for huge ones scale down.
        let fitScale = min(maxW / srcW, maxH / srcH)
        let useScale = (srcW <= maxW && srcH <= maxH) ? min(1.0, fitScale) : fitScale

        var w = (srcW * useScale).rounded(.down)
        var h = (srcH * useScale).rounded(.down)
        w = max(minSize.width, w)
        h = max(minSize.height, h)
        // If min size broke aspect, re-fit inside max box with min constraints.
        if w > maxW || h > maxH {
            let s2 = min(maxW / w, maxH / h)
            w = (w * s2).rounded(.down)
            h = (h * s2).rounded(.down)
        }

        // QL chrome (title bar / toolbar) — give a little extra height so content isn't clipped.
        let chrome: CGFloat = 52
        h = min(h + chrome, visible.height)

        return NSRect(
            x: (visible.midX - w / 2).rounded(.down),
            y: (visible.midY - h / 2).rounded(.down),
            width: w,
            height: h
        )
    }

    /// Size panel to content aspect ratio. Does **not** force a square.
    static func fitContent(on panel: QLPreviewPanel, urls: [URL]) {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = preferredFrame(for: urls, on: screen)
        let visible = screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        // Soft bounds — allow QL internal layout, but never force square min=max.
        panel.minSize = minSize
        panel.maxSize = NSSize(width: visible.width, height: visible.height)
        panel.setFrame(frame, display: true, animate: false)
        NSAnimationContext.endGrouping()
    }

    /// Keep Quick Look's content-driven window resize from exposing an
    /// intermediate frame while a visible preview is being replaced.
    @discardableResult
    static func lockToContentFrame(on panel: QLPreviewPanel, urls: [URL]) -> NSRect? {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return nil }
        let frame = preferredFrame(for: urls, on: screen)

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        // Set max first: the preferred frame already respects the minimum.
        panel.maxSize = frame.size
        panel.minSize = frame.size
        panel.setFrame(frame, display: true, animate: false)
        NSAnimationContext.endGrouping()
        return frame
    }

    static func needsRefit(_ panel: QLPreviewPanel, urls: [URL]) -> Bool {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return false }
        let expected = preferredFrame(for: urls, on: screen)
        let f = panel.frame
        // Generous tolerance — only refit when clearly wrong (e.g. still square 640²).
        return abs(f.width - expected.width) > 24
            || abs(f.height - expected.height) > 24
    }

    // MARK: Media probes

    private static func imagePixelSize(_ url: URL) -> NSSize? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .rawImage) else {
            // Still try ImageIO — some clipboard vault files are images without extension quirks
            return imageIOPixelSize(url)
        }
        return imageIOPixelSize(url)
    }

    private static func imageIOPixelSize(_ url: URL) -> NSSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            // Fallback NSImage
            guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else {
                return nil
            }
            return img.size
        }
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
            ?? (props[kCGImagePropertyPixelWidth] as? Double)
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
            ?? (props[kCGImagePropertyPixelHeight] as? Double)
        guard let w, let h, w > 0, h > 0 else { return nil }
        return NSSize(width: w, height: h)
    }

    private static func videoPixelSize(_ url: URL) -> NSSize? {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return videoTrackSize(url)
        }
        guard type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) else {
            return nil
        }
        return videoTrackSize(url)
    }

    private static func videoTrackSize(_ url: URL) -> NSSize? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let nat = track.naturalSize.applying(track.preferredTransform)
        let w = abs(nat.width)
        let h = abs(nat.height)
        guard w > 1, h > 1 else { return nil }
        return NSSize(width: w, height: h)
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
    private var settleWorkItems: [DispatchWorkItem] = []
    private var revealWorkItem: DispatchWorkItem?
    private var frameUnlockWorkItem: DispatchWorkItem?
    private var panelResizeObserver: QuickLookPanelResizeObserver?
    private var onClose: (() -> Void)?
    private var isPresenting = false
    private var isContentSwapping = false
    private var currentURLs: [URL] = []

    var isPanelVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    private init() {}

    func present(urls: [URL], onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.currentURLs = urls
        frameUnlockWorkItem?.cancel()
        frameUnlockWorkItem = nil
        hostView.keepsContentFrameLocked = false
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
        isContentSwapping = true
        hostView.isProgrammaticUpdate = true
        hostView.keepsContentFrameLocked = true
        cancelSettle()
        revealWorkItem?.cancel()

        // The first presentation has the same asynchronous frame jump as a
        // reload. Hide first, then attach the resize guard before Quick Look
        // starts laying out the preview.
        ql.alphaValue = 0
        ql.updateController()
        if ql.dataSource == nil {
            ql.dataSource = hostView
            ql.delegate = hostView
        }

        hostView.lockedContentFrame = QuickLookPanelSizing.lockToContentFrame(on: ql, urls: urls)
        panelResizeObserver?.stopObserving()
        panelResizeObserver = QuickLookPanelResizeObserver(panel: ql, hostView: hostView)
        panelResizeObserver?.startObserving()

        ql.currentPreviewItemIndex = 0
        ql.reloadData()
        ql.makeKeyAndOrderFront(nil)

        hostView.lockedContentFrame = QuickLookPanelSizing.lockToContentFrame(on: ql, urls: urls)
        startVisibilityWatch()
        // The first QL presentation can resize itself after the first frame.
        // QL performs another content-driven resize after its initial preview
        // control begins. Keep the panel hidden through that later layout and
        // re-apply the target frame before showing it.
        revealWhenStable(urls: urls, after: 0.44, shouldRevealPanel: true)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let ql = QLPreviewPanel.shared(), ql.isVisible {
                if !self.hostView.keepsContentFrameLocked {
                    QuickLookPanelSizing.fitContent(on: ql, urls: urls)
                }
            } else {
                self.fallbackQLManage(urls: urls)
                self.isPresenting = false
            }
        }
    }

    /// Swap items in the current panel without hiding it, so browsing stays seamless.
    func reload(urls: [URL], onClose: @escaping () -> Void) {
        currentURLs = urls
        hostView.urls = urls
        self.onClose = onClose
        guard let ql = QLPreviewPanel.shared() else {
            present(urls: urls, onClose: onClose)
            return
        }

        let needsInitialReveal = isPresenting || ql.alphaValue < 1
        isContentSwapping = true
        hostView.isProgrammaticUpdate = true
        hostView.keepsContentFrameLocked = true
        frameUnlockWorkItem?.cancel()
        frameUnlockWorkItem = nil
        cancelSettle()
        revealWorkItem?.cancel()

        if ql.dataSource == nil || ql.dataSource as AnyObject? !== hostView {
            ql.dataSource = hostView
            ql.delegate = hostView
        }

        if ql.currentPreviewItemIndex != 0 {
            ql.currentPreviewItemIndex = 0
        }
        // Apply the new card's final dimensions before asking Quick Look to
        // reload it. Locking both bounds prevents QL from briefly resizing to
        // its internal intermediate size during the swap.
        hostView.lockedContentFrame = QuickLookPanelSizing.lockToContentFrame(on: ql, urls: urls)
        panelResizeObserver?.stopObserving()
        panelResizeObserver = QuickLookPanelResizeObserver(panel: ql, hostView: hostView)
        panelResizeObserver?.startObserving()
        ql.reloadData()

        // Quick Look may momentarily report the panel as hidden while it swaps
        // preview controllers. Keep the existing window session on screen.
        if !ql.isVisible {
            ql.makeKeyAndOrderFront(nil)
        }

        // Do not call fitContent here: it releases the fixed bounds before
        // Quick Look has finished its asynchronous content-driven layout.
        startVisibilityWatch()
        revealWhenStable(
            urls: urls,
            after: needsInitialReveal ? 0.24 : 0.40,
            shouldRevealPanel: needsInitialReveal
        )
    }

    func dismiss() {
        stopVisibilityWatch()
        cancelSettle()
        revealWorkItem?.cancel()
        revealWorkItem = nil
        frameUnlockWorkItem?.cancel()
        frameUnlockWorkItem = nil
        isContentSwapping = false
        hostView.isProgrammaticUpdate = false
        hostView.keepsContentFrameLocked = false
        hostView.lockedContentFrame = nil
        panelResizeObserver?.stopObserving()
        panelResizeObserver = nil
        if let ql = QLPreviewPanel.shared(), ql.isVisible {
            ql.alphaValue = 1
            ql.orderOut(nil)
        }
        clearPanelDataSource()
        hostPanel?.orderOut(nil)
        hostView.urls = []
        currentURLs = []
        onClose = nil
    }

    private func handleUserClosed() {
        stopVisibilityWatch()
        cancelSettle()
        revealWorkItem?.cancel()
        revealWorkItem = nil
        frameUnlockWorkItem?.cancel()
        frameUnlockWorkItem = nil
        isContentSwapping = false
        hostView.isProgrammaticUpdate = false
        hostView.keepsContentFrameLocked = false
        hostView.lockedContentFrame = nil
        panelResizeObserver?.stopObserving()
        panelResizeObserver = nil
        clearPanelDataSource()
        hostPanel?.orderOut(nil)
        hostView.urls = []
        currentURLs = []
        let cb = onClose
        onClose = nil
        cb?()
    }

    // MARK: - Reveal

    private func revealWhenStable(urls: [URL], after delay: TimeInterval, shouldRevealPanel: Bool) {
        let settleDelays: [TimeInterval] = shouldRevealPanel
            ? [0.0, 0.03, 0.06, 0.10, 0.14, 0.18, 0.22, 0.30, 0.36, 0.40]
            : []
        for d in settleDelays {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isContentSwapping else { return }
                guard let ql = QLPreviewPanel.shared() else { return }
                if self.hostView.keepsContentFrameLocked {
                    self.hostView.lockedContentFrame = QuickLookPanelSizing.lockToContentFrame(on: ql, urls: urls)
                } else {
                    QuickLookPanelSizing.fitContent(on: ql, urls: urls)
                }
            }
            settleWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: work)
        }

        let reveal = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let ql = QLPreviewPanel.shared(), ql.isVisible || self.isPanelVisible else {
                self.isContentSwapping = false
                self.isPresenting = false
                self.hostView.isProgrammaticUpdate = false
                return
            }
            if self.hostView.keepsContentFrameLocked {
                self.hostView.lockedContentFrame = QuickLookPanelSizing.lockToContentFrame(on: ql, urls: urls)
            } else {
                QuickLookPanelSizing.fitContent(on: ql, urls: urls)
            }
            if shouldRevealPanel {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0
                ql.alphaValue = 1
                NSAnimationContext.endGrouping()
            }
            self.isContentSwapping = false
            self.isPresenting = false
            self.hostView.isProgrammaticUpdate = false
            if self.hostView.keepsContentFrameLocked {
                self.scheduleFrameUnlock(after: 0.45, urls: urls)
            }
        }
        revealWorkItem = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: reveal)
    }

    private func scheduleFrameUnlock(after delay: TimeInterval, urls: [URL]) {
        frameUnlockWorkItem?.cancel()
        let unlock = DispatchWorkItem { [weak self] in
            guard let self,
                  self.hostView.keepsContentFrameLocked,
                  !self.isContentSwapping,
                  let ql = QLPreviewPanel.shared(), ql.isVisible else { return }
            QuickLookPanelSizing.fitContent(on: ql, urls: urls)
            self.hostView.keepsContentFrameLocked = false
            self.hostView.lockedContentFrame = nil
            self.panelResizeObserver?.stopObserving()
            self.panelResizeObserver = nil
            self.frameUnlockWorkItem = nil
        }
        frameUnlockWorkItem = unlock
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: unlock)
    }

    private func cancelSettle() {
        settleWorkItems.forEach { $0.cancel() }
        settleWorkItems.removeAll()
    }

    private func startVisibilityWatch() {
        stopVisibilityWatch()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let visible = QLPreviewPanel.shared()?.isVisible == true
                if !visible, !self.isPresenting, !self.isContentSwapping {
                    self.handleUserClosed()
                }
                // Intentionally do NOT re-force frame after reveal — user may resize,
                // and we must not re-square or re-letterbox media.
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
    var isProgrammaticUpdate = false
    var keepsContentFrameLocked = false
    var lockedContentFrame: NSRect?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !urls.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        // Follow system appearance so text QL uses the same document background
        // as Finder (not a tinted/brown paper look from forced dark chrome).
        panel.appearance = NSApp.effectiveAppearance
        if panel.currentPreviewItemIndex < 0 || panel.currentPreviewItemIndex >= urls.count {
            panel.currentPreviewItemIndex = 0
        }
        // A programmatic reload owns the panel bounds until the swap completes.
        if keepsContentFrameLocked, let lockedContentFrame {
            panel.setFrame(lockedContentFrame, display: true, animate: false)
        } else if !isProgrammaticUpdate {
            QuickLookPanelSizing.fitContent(on: panel, urls: urls)
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Capture this synchronously: Quick Look can relinquish control during
        // reloadData(), then deliver the callback after the update has settled.
        let wasProgrammaticUpdate = isProgrammaticUpdate
        DispatchQueue.main.async { [weak self] in
            guard let self, !wasProgrammaticUpdate, !self.isProgrammaticUpdate else { return }
            if QLPreviewPanel.shared()?.isVisible != true {
                self.onUserClosed?()
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

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        .zero
    }

    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        nil
    }

    /// Keep media aspect ratio — do not stretch to fill a foreign frame.
    func previewPanel(_ panel: QLPreviewPanel!, preserveAspectRatioFor item: (any QLPreviewItem)!) -> Bool {
        true
    }
}

@MainActor
private final class QuickLookPanelResizeObserver: NSObject {
    private weak var panel: QLPreviewPanel?
    private weak var hostView: QuickLookHostView?
    private var isObserving = false

    init(panel: QLPreviewPanel, hostView: QuickLookHostView) {
        self.panel = panel
        self.hostView = hostView
    }

    func startObserving() {
        guard !isObserving, let panel else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: panel
        )
        isObserving = true
    }

    func stopObserving() {
        guard isObserving else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: panel)
        isObserving = false
    }

    @objc private func panelDidResize(_ notification: Notification) {
        guard let panel, let hostView,
              hostView.keepsContentFrameLocked,
              let expectedFrame = hostView.lockedContentFrame else { return }
        let current = panel.frame
        guard abs(current.width - expectedFrame.width) > 1
                || abs(current.height - expectedFrame.height) > 1 else { return }

        // Quick Look can resize itself outside NSWindow's min/max limits while
        // a new preview is loading. Restore the target frame synchronously in
        // the resize notification, before the intermediate geometry is drawn.
        panel.setFrame(expectedFrame, display: true, animate: false)
    }
}

// MARK: - SwiftUI helper

struct QuickLookPresenter: ViewModifier {
    @ObservedObject var service: QuickLookService

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func quickLookPresenter(using service: QuickLookService) -> some View {
        self.modifier(QuickLookPresenter(service: service))
    }
}
