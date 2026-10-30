//
//  ClipboardMediaVault.swift
//  Dynamite — durable media storage for clipboard history
//
//  Problem: Finder / many apps put images & videos on the pasteboard as *file URLs*
//  only. After the app restarts, sandbox + deleted temp files mean those URLs no
//  longer load → cards go blank.
//
//  Fix on capture (and migrate on load):
//    • Images  → store bitmap bytes in the vault and keep only a file URL in memory
//    • Videos  → copy the file into Application Support/ClipboardMedia and
//                rewrite the fileURL content to the durable path
//    • Image files also get a vault copy when useful for Quick Look
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ClipboardMediaVault {
    private static let folderName = "ClipboardMedia"
    private static let markerType = "org.dynamite.clipboard.media-vault"
    private static let compactMarkerType = "org.dynamite.clipboard.media-vault-v2"
    private static let payloadMarkerPrefix = "org.dynamite.clipboard.payload."

    // SwiftData keeps HistoryItemContent objects reachable for the lifetime of
    // the context. Keep rich clipboard payloads small in that graph; the full
    // value remains available for an explicit paste from the vault.
    static let maxInlinePayloadBytes = 2 * 1024 * 1024
    private static let previewPayloadBytes = 64 * 1024

    static var rootURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support
            .appendingPathComponent("Dynamite", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Call right after creating a HistoryItem from the pasteboard, before save.
    static func materialize(_ item: HistoryItem) {
        ensureRoot()
        relocateMediaFileURLs(item)
        offloadEmbeddedImageDataIfNeeded(item)
        offloadLargePayloadsIfNeeded(item)
        markMaterialized(item)
        markCompact(item)
    }

    /// Repair older history rows that only hold fragile file URLs.
    static func migrateIfNeeded(_ items: [HistoryItem]) {
        ensureRoot()
        var changed = false
        for item in items {
            if !isCompact(item) {
                relocateMediaFileURLs(item)
                // Legacy versions embedded full bitmap Data in SwiftData. Move it
                // to the vault before the view can create cards for the item.
                offloadEmbeddedImageDataIfNeeded(item)
                markMaterialized(item)
                markCompact(item)
                changed = true
            }
            // A row can already have the v2 marker while still containing a
            // large HTML/RTF/text value from before the payload budget existed.
            changed = offloadLargePayloadsIfNeeded(item) || changed
        }
        if changed {
            try? ClipboardStorage.shared.context.save()
        }
    }

    /// Remove vault files owned by a history item (on delete / eviction).
    static func removeFiles(for item: HistoryItem) {
        let root = rootURL.path
        for url in fileURLs(in: item) + payloadURLs(in: item) {
            guard url.isFileURL, url.path.hasPrefix(root) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Returns the complete value for paste. Normal UI code should continue
    /// using `HistoryItemContent.value`, which is deliberately only a preview
    /// for oversized payloads.
    static func dataForCopy(_ content: HistoryItemContent, in item: HistoryItem) -> Data? {
        guard !isPayloadMarker(content.type) else { return nil }
        if let url = payloadURL(for: content.type, in: item),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return content.value
    }

    /// Compacts a large pasteboard payload before it is added to a HistoryItem.
    /// This prevents several rich-text representations from being retained in
    /// the model at the same time while the capture is being assembled.
    static func compactCaptureContent(type: String, data: Data) -> [HistoryItemContent]? {
        let imageTypes = Set(ClipboardStorageType.images.types.map(\.rawValue))
        let pasteboardType = NSPasteboard.PasteboardType(type)
        guard data.count > maxInlinePayloadBytes,
              type != NSPasteboard.PasteboardType.fileURL.rawValue,
              !imageTypes.contains(type),
              !isPayloadMarker(type),
              pasteboardType != .fromMaccy,
              let url = writeIntoVault(data: data, fileExtension: "bin") else {
            return nil
        }

        return [
            HistoryItemContent(type: type, value: previewData(for: type, data: data)),
            HistoryItemContent(type: payloadMarkerType(for: type), value: url.dataRepresentation)
        ]
    }

    // MARK: - Image storage

    /// Move embedded bitmap bytes out of SwiftData. The file URL is enough to
    /// render previews and the original bytes are loaded only for an explicit
    /// paste, so large screenshots do not stay resident for the app lifetime.
    private static func offloadEmbeddedImageDataIfNeeded(_ item: HistoryItem) {
        let imageTypes = Set(ClipboardStorageType.images.types.map(\.rawValue))
        let embedded = item.contents.filter {
            guard let value = $0.value else { return false }
            return imageTypes.contains($0.type) && !value.isEmpty
        }
        guard !embedded.isEmpty else { return }

        let existingImageURL = fileURLs(in: item).first(where: { $0.isFileURL && isImageFile($0) })
        var durableImageURL = existingImageURL

        if durableImageURL == nil, let data = embedded.compactMap(\.value).first(where: { !$0.isEmpty }) {
            durableImageURL = writeIntoVault(data: data, fileExtension: fileExtension(for: embedded[0].type, data: data))
        }

        guard let durableImageURL else { return }

        if !fileURLs(in: item).contains(durableImageURL) {
            item.contents.append(
                HistoryItemContent(
                    type: NSPasteboard.PasteboardType.fileURL.rawValue,
                    value: durableImageURL.dataRepresentation
                )
            )
        }

        for content in embedded {
            content.value = nil
        }
    }

    /// Store oversized text/rich-text/custom payloads on disk. Images already
    /// use the media path above, so they are intentionally excluded here.
    @discardableResult
    private static func offloadLargePayloadsIfNeeded(_ item: HistoryItem) -> Bool {
        let imageTypes = Set(ClipboardStorageType.images.types.map(\.rawValue))
        let candidates = item.contents.filter { content in
            guard let value = content.value,
                  value.count > maxInlinePayloadBytes else { return false }
            let type = NSPasteboard.PasteboardType(content.type)
            return content.type != NSPasteboard.PasteboardType.fileURL.rawValue
                && !imageTypes.contains(content.type)
                && !isPayloadMarker(content.type)
                && payloadURL(for: content.type, in: item) == nil
                && type != .fromMaccy
        }

        var changed = false
        for content in candidates {
            guard let value = content.value,
                  let url = writeIntoVault(data: value, fileExtension: "bin") else { continue }

            content.value = previewData(for: content.type, data: value)
            item.contents.append(
                HistoryItemContent(
                    type: payloadMarkerType(for: content.type),
                    value: url.dataRepresentation
                )
            )
            changed = true
        }
        return changed
    }

    private static func previewData(for type: String, data: Data) -> Data {
        if type == NSPasteboard.PasteboardType.string.rawValue,
           let text = String(data: data, encoding: .utf8) {
            return Data(String(text.prefix(8_192)).utf8)
        }
        return Data(data.prefix(previewPayloadBytes))
    }

    private static func writeIntoVault(data: Data, fileExtension: String) -> URL? {
        guard !data.isEmpty else { return nil }
        let destination = rootURL.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        do {
            try data.write(to: destination, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        } catch {
            return nil
        }
    }

    private static func fileExtension(for type: String, data: Data) -> String {
        switch NSPasteboard.PasteboardType(type) {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        default:
            if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
            if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
            return "tiff"
        }
    }

    // MARK: - File relocation

    private static func relocateMediaFileURLs(_ item: HistoryItem) {
        let root = rootURL
        for content in item.contents {
            guard content.type == NSPasteboard.PasteboardType.fileURL.rawValue,
                  let value = content.value,
                  let source = URL(dataRepresentation: value, relativeTo: nil, isAbsolute: true),
                  source.isFileURL else { continue }

            // Already durable?
            if source.path.hasPrefix(root.path) { continue }

            let isImage = isImageFile(source)
            let isVideo = isVideoFile(source)
            guard isImage || isVideo else { continue }

            // Prefer embedding images (above). Still vault-copy so Quick Look / paste
            // keep a stable file URL after the original is gone.
            guard let durable = copyIntoVault(from: source) else { continue }
            content.value = durable.dataRepresentation
        }
    }

    private static func copyIntoVault(from source: URL) -> URL? {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: source.path) else { return nil }

        let ext = source.pathExtension.isEmpty ? defaultExtension(for: source) : source.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        let dest = rootURL.appendingPathComponent(name)

        do {
            // copyItem preserves original; for security-scoped sources we already
            // could read the path at capture time.
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: source, to: dest)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
            return dest
        } catch {
            // Fallback: stream bytes (works when copyItem fails on some volumes).
            do {
                let data = try Data(contentsOf: source)
                try data.write(to: dest, options: [.atomic])
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
                return dest
            } catch {
                return nil
            }
        }
    }

    // MARK: - Markers / helpers

    private static func markMaterialized(_ item: HistoryItem) {
        guard !isMaterialized(item) else { return }
        item.contents.append(
            HistoryItemContent(type: markerType, value: Data("1".utf8))
        )
    }

    private static func markCompact(_ item: HistoryItem) {
        guard !isCompact(item) else { return }
        item.contents.append(
            HistoryItemContent(type: compactMarkerType, value: Data("1".utf8))
        )
    }

    private static func isMaterialized(_ item: HistoryItem) -> Bool {
        item.contents.contains { $0.type == markerType }
    }

    private static func isCompact(_ item: HistoryItem) -> Bool {
        item.contents.contains { $0.type == compactMarkerType }
    }

    static func isPayloadMarker(_ type: String) -> Bool {
        type.hasPrefix(payloadMarkerPrefix)
    }

    private static func payloadMarkerType(for type: String) -> String {
        payloadMarkerPrefix + type
    }

    private static func payloadURL(for type: String, in item: HistoryItem) -> URL? {
        let marker = payloadMarkerType(for: type)
        return item.contents
            .first(where: { $0.type == marker })
            .flatMap { content in
                guard let value = content.value else { return nil }
                return URL(dataRepresentation: value, relativeTo: nil, isAbsolute: true)
            }
    }

    private static func payloadURLs(in item: HistoryItem) -> [URL] {
        item.contents
            .filter { isPayloadMarker($0.type) }
            .compactMap { content in
                guard let value = content.value else { return nil }
                return URL(dataRepresentation: value, relativeTo: nil, isAbsolute: true)
            }
    }

    private static func fileURLs(in item: HistoryItem) -> [URL] {
        item.contents
            .filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }
            .compactMap { content in
                guard let value = content.value else { return nil }
                return URL(dataRepresentation: value, relativeTo: nil, isAbsolute: true)
            }
    }

    private static func ensureRoot() {
        _ = rootURL
    }

    private static func isImageFile(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .image)
        }
        return false
    }

    private static func isVideoFile(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent)
        }
        return false
    }

    private static func pasteboardType(forImageAt url: URL, data: Data) -> NSPasteboard.PasteboardType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        default:
            if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
            if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
            return .tiff
        }
    }

    private static func defaultExtension(for url: URL) -> String {
        if isVideoFile(url) { return "mp4" }
        if isImageFile(url) { return "png" }
        return "bin"
    }
}
