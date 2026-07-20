//
//  ClipboardKeyboardMonitor.swift
//  boringNotch — dual-scope keyboard while notch is open
//
//  Notch-wide (any tab): ⌘ held badges, ⌘1–4 tab switch, ⌘⇧[ / ⌘⇧] cycle tabs, Esc close
//  Clipboard-only: WASD/HJKL/arrows, Space → system Quick Look, Enter paste, Delete, ⌘C
//

import AppKit
import Carbon.HIToolbox
import Defaults
import SwiftUI

@MainActor
final class ClipboardKeyboardMonitor: ObservableObject {
    static let shared = ClipboardKeyboardMonitor()

    private var keyDownMonitor: Any?
    private var flagsMonitor: Any?

    /// ⌘ held — drives tab ⌘N badges (and was card badges; cards no longer use this).
    @Published var isCommandHeld: Bool = false

    /// Full clipboard handlers (WASD, Space Quick Look, Enter, Delete, ⌘C) — only while clipboard tab is active.
    private(set) var clipboardHandlersEnabled: Bool = false

    // Clipboard-only callbacks
    var onMove: ((Int, Int) -> Void)?
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    var onCopy: (() -> Void)?

    private init() {}

    // MARK: - Lifecycle

    /// Start notch-wide monitors (⌘ combos + flags). Call when notch opens.
    func startNotchSession() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            return self.handleFlagsChanged(event)
        }
    }

    /// Stop everything (notch closed).
    func stop() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        isCommandHeld = false
        clipboardHandlersEnabled = false
        clearClipboardCallbacks()
    }

    /// Idempotent: safe to call on every clipboard tab entry.
    func enableClipboardHandlers() {
        clipboardHandlersEnabled = true
    }

    /// Clears clipboard-only callbacks. Safe to call repeatedly; does not touch notch-wide monitors.
    func disableClipboardHandlers() {
        guard clipboardHandlersEnabled || onMove != nil || onEnter != nil || onCopy != nil else {
            return
        }
        clipboardHandlersEnabled = false
        clearClipboardCallbacks()
    }

    private func clearClipboardCallbacks() {
        onMove = nil
        onEnter = nil
        onDelete = nil
        onEscape = nil
        onSpace = nil
        onCopy = nil
    }

    // MARK: - Events

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        let held = event.modifierFlags.contains(.command)
        if held != isCommandHeld {
            isCommandHeld = held
        }
        return event
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let keyCode = Int(event.keyCode)
        let hasCmd = mods.contains(.command)
        let hasShift = mods.contains(.shift)
        let hasOpt = mods.contains(.option)
        let hasCtrl = mods.contains(.control)

        // ── Notch-wide: ⌘⇧[ / ⌘⇧] cycle tabs (physical brackets) ──
        if hasCmd, hasShift, !hasOpt, !hasCtrl {
            if keyCode == kVK_ANSI_LeftBracket { // 33
                cycleTab(delta: -1)
                return nil
            }
            if keyCode == kVK_ANSI_RightBracket { // 30
                cycleTab(delta: 1)
                return nil
            }
        }

        // ── Notch-wide: ⌘1–N switch tabs by *visible* spaces order ──
        // ── Notch-wide: ⌘, toggle Settings (layout-independent key code) ──
        if hasCmd, !hasShift, !hasOpt, !hasCtrl {
            // kVK_ANSI_Comma — same physical key on any layout
            if keyCode == kVK_ANSI_Comma {
                toggleSettingsWindow()
                return nil
            }
            let maxN = max(visibleTabOrder.count, 1)
            if let digit = digitFromKeyCode(UInt16(keyCode)), (1...maxN).contains(digit) {
                selectTab(index: digit - 1)
                return nil
            }
            // Clipboard-only: ⌘C
            if clipboardHandlersEnabled, keyCode == kVK_ANSI_C {
                onCopy?()
                return nil
            }
            // Other ⌘ combos fall through
            return event
        }

        // Escape — clipboard handler may dismiss Quick Look; else close notch via callback or default
        if keyCode == kVK_Escape {
            if clipboardHandlersEnabled, let onEscape {
                onEscape()
                return nil
            }
            // Notch-wide: close open notch
            closeNotchIfOpen()
            return nil
        }

        // ── Clipboard-only handlers below ──
        guard clipboardHandlersEnabled else {
            return event
        }

        if keyCode == kVK_Space && mods.isEmpty {
            onSpace?()
            return nil
        }

        if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            onEnter?()
            return nil
        }

        if keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            onDelete?()
            return nil
        }

        guard mods.isEmpty else {
            return event
        }

        if let delta = navigationDelta(keyCode: keyCode) {
            onMove?(delta.dx, delta.dy)
            return nil
        }

        return event
    }

    // MARK: - Tabs

    /// Visible spaces in user-configured order. ⌘N = index N in this list.
    private var visibleTabOrder: [NotchViews] {
        SpacesStore.shared.visibleEntries.map(\.kind.notchView)
    }

    private func selectTab(index: Int) {
        let order = visibleTabOrder
        guard order.indices.contains(index) else { return }
        let target = order[index]
        withAnimation(.easeInOut(duration: 0.15)) {
            BoringViewCoordinator.shared.currentView = target
        }
    }

    private func cycleTab(delta: Int) {
        let available = visibleTabOrder
        guard !available.isEmpty else { return }

        let current = BoringViewCoordinator.shared.currentView
        let idx = available.firstIndex(of: current) ?? 0
        let next = (idx + delta + available.count) % available.count
        withAnimation(.easeInOut(duration: 0.15)) {
            BoringViewCoordinator.shared.currentView = available[next]
        }
    }

    private func closeNotchIfOpen() {
        // Prefer first open view model via coordinator-facing close if possible
        NotificationCenter.default.post(name: .notchRequestClose, object: nil)
    }

    /// ⌘, — open Settings if closed, close if already key. Works on any layout
    /// because we match kVK_ANSI_Comma, not characters.
    private func toggleSettingsWindow() {
        let controller = SettingsWindowController.shared
        if let window = controller.window, window.isVisible {
            window.close()
        } else {
            DispatchQueue.main.async {
                controller.showWindow()
            }
        }
    }

    // MARK: - Key maps

    private func navigationDelta(keyCode: Int) -> (dx: Int, dy: Int)? {
        switch keyCode {
        case kVK_LeftArrow:  return (-1, 0)
        case kVK_RightArrow: return (1, 0)
        case kVK_UpArrow:    return (0, -1)
        case kVK_DownArrow:  return (0, 1)
        case kVK_ANSI_A: return (-1, 0)
        case kVK_ANSI_D: return (1, 0)
        case kVK_ANSI_W: return (0, -1)
        case kVK_ANSI_S: return (0, 1)
        case kVK_ANSI_H: return (-1, 0)
        case kVK_ANSI_L: return (1, 0)
        case kVK_ANSI_K: return (0, -1)
        case kVK_ANSI_J: return (0, 1)
        default: return nil
        }
    }

    private func digitFromKeyCode(_ keyCode: UInt16) -> Int? {
        let map: [UInt16: Int] = [
            UInt16(kVK_ANSI_1): 1,
            UInt16(kVK_ANSI_2): 2,
            UInt16(kVK_ANSI_3): 3,
            UInt16(kVK_ANSI_4): 4,
            UInt16(kVK_ANSI_5): 5,
            UInt16(kVK_ANSI_6): 6,
            UInt16(kVK_ANSI_7): 7,
            UInt16(kVK_ANSI_8): 8,
            UInt16(kVK_ANSI_9): 9
        ]
        return map[keyCode]
    }
}

extension Notification.Name {
    /// Posted by keyboard monitor to request notch close (Escape on non-clipboard tabs).
    static let notchRequestClose = Notification.Name("notchRequestClose")
}
