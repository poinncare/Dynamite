//
//  ThumbnailService.swift
//  Dynamite
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

actor ThumbnailService {
    static let shared = ThumbnailService()

    // Actor-confined and explicitly bounded by entry count and pixel cost.
    private struct CachedThumbnail {
        let image: CGImage
        let cost: Int
    }
    private var cache: [String: CachedThumbnail] = [:]
    private var cacheOrder: [String] = []
    private var cachedCost = 0
    private let cacheCountLimit = 128
    private let cacheCostLimit = 12 * 1024 * 1024
    private var pendingRequests: [String: Task<CGImage?, Never>] = [:]
    private let thumbnailGenerator = QLThumbnailGenerator.shared

    private init() {}
    
    /// - Parameter iconMode: When `true` (default), Quick Look may return a type icon.
    ///   Pass `false` for content previews (video frames, image previews).
    func thumbnail(for url: URL, size: CGSize, iconMode: Bool = true) async -> CGImage? {
        let cacheKey = "\(url.path)_\(size.width)x\(size.height)_icon=\(iconMode)"
        
        if let cached = cache[cacheKey] {
            touch(cacheKey)
            return cached.image
        }
        
        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }
        
        let task = Task<CGImage?, Never> {
            let thumbnail = await generateQuickLookThumbnail(for: url, size: size, iconMode: iconMode)
            if let thumbnail = thumbnail {
                insert(thumbnail, for: cacheKey)
            }
            pendingRequests[cacheKey] = nil
            return thumbnail
        }
        
        pendingRequests[cacheKey] = task
        return await task.value
    }
    
    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
        cachedCost = 0
    }

    func clearCache(for url: URL) {
        let prefix = "\(url.path)_"
        for key in cache.keys.filter({ $0.hasPrefix(prefix) }) {
            if let cached = cache.removeValue(forKey: key) {
                cachedCost -= cached.cost
            }
            cacheOrder.removeAll { $0 == key }
        }
    }

    private static func cost(of image: CGImage) -> Int {
        max(1, image.width * image.height * 4)
    }

    private func insert(_ image: CGImage, for key: String) {
        let cost = Self.cost(of: image)
        if let previous = cache.removeValue(forKey: key) {
            cachedCost -= previous.cost
            cacheOrder.removeAll { $0 == key }
        }
        cache[key] = CachedThumbnail(image: image, cost: cost)
        cacheOrder.append(key)
        cachedCost += cost

        while cache.count > cacheCountLimit || cachedCost > cacheCostLimit {
            guard let oldest = cacheOrder.first,
                  let evicted = cache.removeValue(forKey: oldest) else { break }
            cacheOrder.removeFirst()
            cachedCost -= evicted.cost
        }
    }

    private func touch(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }
    
    // MARK: - Private Methods
    
    private func generateQuickLookThumbnail(for url: URL, size: CGSize, iconMode: Bool) async -> CGImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        NSLog("🔐 ThumbnailService: obtaining security scope for \(url.path)")
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )
        request.iconMode = iconMode

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            thumbnailGenerator.generateBestRepresentation(for: request) { representation, error in
                if let rep = representation {
                    NSLog("🔍 ThumbnailService: generated thumbnail for \(url.path)")
                    continuation.resume(returning: rep.cgImage)
                } else {
                    if let err = error {
                        NSLog("⚠️ ThumbnailService: thumbnail error for \(url.path): \(err.localizedDescription)")
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Extensions

extension QLThumbnailRepresentation {
    var nsImage: NSImage {
        return NSImage(cgImage: self.cgImage, size: self.cgImage.size)
    }
}

extension CGImage {
    var size: NSSize {
        return NSSize(width: self.width, height: self.height)
    }
}
