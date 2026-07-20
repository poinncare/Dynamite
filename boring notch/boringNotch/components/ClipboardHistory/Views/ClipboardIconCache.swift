//
//  ClipboardIconCache.swift
//  boringNotch — avoid NSWorkspace icon hits on every ScrollView frame
//

import AppKit

enum ClipboardIconCache {
    private static var appIcons: [String: NSImage] = [:]
    private static var fileIcons: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func appIcon(bundleId: String?) -> NSImage? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = appIcons[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        appIcons[bundleId] = icon
        return icon
    }

    static func fileIcon(path: String?) -> NSImage {
        guard let path, !path.isEmpty else {
            return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        }
        lock.lock()
        defer { lock.unlock() }
        if let cached = fileIcons[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        fileIcons[path] = icon
        return icon
    }
}
