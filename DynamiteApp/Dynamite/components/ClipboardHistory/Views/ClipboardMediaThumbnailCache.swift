//
//  ClipboardMediaThumbnailCache.swift
//  Dynamite — resized image + video frame thumbnails for clipboard cards
//

import AppKit
import Foundation
import SwiftData

/// Shared cache of card-sized media previews so horizontal scroll stays cheap.
@MainActor
enum ClipboardMediaThumbnailCache {
    // Thumbnails are presentation data, not application state. Never retain
    // an unbounded dictionary of decoded bitmaps in a long-running menu-bar
    // app; NSCache purges them automatically when memory is tight.
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 18
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    private static var inflight: [String: Task<NSImage?, Never>] = [:]
    private static let lock = NSLock()

    /// Point size of the card; retinas scale inside generators.
    static func thumbnail(for item: HistoryItem, size: CGSize) async -> NSImage? {
        let key = cacheKey(for: item, size: size)

        lock.lock()
        if let cached = images.object(forKey: key as NSString) {
            lock.unlock()
            return cached
        }
        if let existing = inflight[key] {
            lock.unlock()
            return await existing.value
        }
        lock.unlock()

        let task = Task<NSImage?, Never> {
            let image = await generate(for: item, size: size)
            lock.lock()
            if let image {
                let pixelCost = max(1, Int(image.size.width * image.size.height * 4))
                images.setObject(image, forKey: key as NSString, cost: pixelCost)
            }
            inflight[key] = nil
            lock.unlock()
            return image
        }

        lock.lock()
        inflight[key] = task
        lock.unlock()

        return await task.value
    }

    /// Synchronous hit only — used to avoid a flash when the view reappears.
    static func cached(for item: HistoryItem, size: CGSize) -> NSImage? {
        let key = cacheKey(for: item, size: size)
        lock.lock()
        defer { lock.unlock() }
        return images.object(forKey: key as NSString)
    }

    static func clear() {
        lock.lock()
        images.removeAllObjects()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        lock.unlock()
    }

    // MARK: - Private

    private static func cacheKey(for item: HistoryItem, size: CGSize) -> String {
        // persistentModelID is stable after insert; include lastCopiedAt so re-copies refresh.
        "\(item.persistentModelID)_\(item.lastCopiedAt.timeIntervalSince1970)_\(Int(size.width))x\(Int(size.height))"
    }

    private static func generate(for item: HistoryItem, size: CGSize) async -> NSImage? {
        // Decode directly to a thumbnail. Creating a full-size NSImage first
        // briefly decoded a 4K/8K source and could consume tens of MB per card.
        if let data = item.imageData {
            return await thumbnailOnBackground(data: data, to: size)
        }

        // Video (or image file that failed NSImage): Quick Look content preview (not type icon).
        if let url = item.mediaPreviewURL ?? item.videoFileURL {
            let pointSize = CGSize(
                width: max(size.width, 1),
                height: max(size.height, 1)
            )
            if let ql = await ThumbnailService.shared.thumbnail(
                for: url,
                size: pointSize,
                iconMode: false
            ) {
                return ql
            }
            // Fallback: workspace file icon (better than empty)
            return ClipboardIconCache.fileIcon(path: url.path)
        }

        return nil
    }

    private static func thumbnailOnBackground(data: Data, to size: CGSize) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            let maxPixelSize = max(1, Int(max(size.width, size.height) * 2.0))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: size)
        }.value
    }
}
