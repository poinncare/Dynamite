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
    // Main-actor confined and explicitly bounded by entry count and pixel cost.
    private struct CachedImage {
        let image: CGImage
        let cost: Int
    }
    private static var images: [String: CachedImage] = [:]
    private static var imageOrder: [String] = []
    private static var cachedCost = 0
    private static let imageCountLimit = 18
    private static let imageCostLimit = 12 * 1024 * 1024
    private static var inflight: [String: Task<CGImage?, Never>] = [:]

    /// Point size of the card; retinas scale inside generators.
    static func thumbnail(for item: HistoryItem, size: CGSize) async -> NSImage? {
        let key = cacheKey(for: item, size: size)

        if let cached = images[key] {
            touch(key)
            return NSImage(cgImage: cached.image, size: size)
        }
        if let existing = inflight[key] {
            guard let image = await existing.value else { return nil }
            return NSImage(cgImage: image, size: size)
        }

        let task = Task<CGImage?, Never> {
            let image = await generate(for: item, size: size)
            if let image {
                insert(image, for: key)
            }
            inflight[key] = nil
            return image
        }

        inflight[key] = task
        guard let image = await task.value else { return nil }
        return NSImage(cgImage: image, size: size)
    }

    /// Synchronous hit only — used to avoid a flash when the view reappears.
    static func cached(for item: HistoryItem, size: CGSize) -> NSImage? {
        let key = cacheKey(for: item, size: size)
        guard let cached = images[key] else { return nil }
        touch(key)
        return NSImage(cgImage: cached.image, size: size)
    }

    static func clear() {
        images.removeAll()
        imageOrder.removeAll()
        cachedCost = 0
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
    }

    // MARK: - Private

    private static func cacheKey(for item: HistoryItem, size: CGSize) -> String {
        // persistentModelID is stable after insert; include lastCopiedAt so re-copies refresh.
        "\(item.persistentModelID)_\(item.lastCopiedAt.timeIntervalSince1970)_\(Int(size.width))x\(Int(size.height))"
    }

    private static func insert(_ image: CGImage, for key: String) {
        let cost = max(1, image.width * image.height * 4)
        if let previous = images.removeValue(forKey: key) {
            cachedCost -= previous.cost
            imageOrder.removeAll { $0 == key }
        }
        images[key] = CachedImage(image: image, cost: cost)
        imageOrder.append(key)
        cachedCost += cost

        while images.count > imageCountLimit || cachedCost > imageCostLimit {
            guard let oldest = imageOrder.first,
                  let evicted = images.removeValue(forKey: oldest) else { break }
            imageOrder.removeFirst()
            cachedCost -= evicted.cost
        }
    }

    private static func touch(_ key: String) {
        imageOrder.removeAll { $0 == key }
        imageOrder.append(key)
    }

    private static func generate(for item: HistoryItem, size: CGSize) async -> CGImage? {
        // Vaulted images must be downsampled directly from disk. Calling
        // item.imageData first reads the complete original into memory for
        // every visible card; nine large screenshots can otherwise recreate
        // the 250–300 MB footprint even though the history is disk-backed.
        if item.contentKind == .image, let url = item.mediaPreviewURL {
            if let thumbnail = await thumbnailOnBackground(url: url, to: size) {
                return thumbnail
            }
            // Some pasteboard/file providers expose a valid image only through
            // their data representation. Retry just this card; the normal
            // vaulted path above remains a bounded ImageIO downsample.
            if let data = item.imageData {
                guard let thumbnail = await thumbnailOnBackground(data: data, to: size) else { return nil }
                return thumbnail
            }
            return nil
        }

        // Decode directly to a thumbnail. Creating a full-size NSImage first
        // briefly decoded a 4K/8K source and could consume tens of MB per card.
        if let data = item.imageData {
            guard let thumbnail = await thumbnailOnBackground(data: data, to: size) else { return nil }
            return thumbnail
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
            let icon = ClipboardIconCache.fileIcon(path: url.path)
            return icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        return nil
    }

    private static func thumbnailOnBackground(url: URL, to size: CGSize) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            let maxPixelSize = max(1, Int(max(size.width, size.height) * 2.0))
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return cgImage
        }.value
    }

    private static func thumbnailOnBackground(data: Data, to size: CGSize) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            let maxPixelSize = max(1, Int(max(size.width, size.height) * 2.0))
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return cgImage
        }.value
    }
}
