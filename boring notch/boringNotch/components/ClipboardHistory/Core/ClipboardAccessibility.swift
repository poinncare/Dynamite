//
//  ClipboardAccessibility.swift
//  boringNotch — ported from Maccy
//

import AppKit

enum ClipboardAccessibility {
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    static func check() {
        guard !isTrusted else { return }
        requestIfNeeded()
    }

    static func requestIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
