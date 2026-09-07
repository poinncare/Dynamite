//
//  ClipboardIconCache.swift
//  boringNotch — avoid NSWorkspace icon hits on every ScrollView frame
//

import AppKit

enum ClipboardIconCache {
    // NSCache is thread-safe, automatically purges under pressure, and keeps
    // icon lookups bounded. The old dictionaries retained every path ever
    // seen by the shelf/clipboard for the lifetime of the process.
    private static let appIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    private static let fileIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func appIcon(bundleId: String?) -> NSImage? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        let key = bundleId as NSString
        if let cached = appIcons.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        appIcons.setObject(icon, forKey: key, cost: 32 * 32 * 4)
        return icon
    }

    static func fileIcon(path: String?) -> NSImage {
        guard let path, !path.isEmpty else {
            return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        }
        let key = path as NSString
        if let cached = fileIcons.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        fileIcons.setObject(icon, forKey: key, cost: 32 * 32 * 4)
        return icon
    }
}
