//
//  ClipboardQuickLookSupport.swift
//  boringNotch — resolve clipboard HistoryItem → file URL for system Quick Look
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardQuickLookSupport {
    /// Builds a file URL Quick Look can open.
    /// - Returns: `url` to preview, and `isTemporary` if the caller must delete it later.
    static func previewURLs(for item: HistoryItem) -> (urls: [URL], temporary: [URL]) {
        switch item.contentKind {
        case .file, .video:
            let files = item.fileURLs.filter(\.isFileURL)
            if !files.isEmpty {
                return (files, [])
            }
            if let media = item.mediaPreviewURL {
                return ([media], [])
            }
            return textFallback(for: item)

        case .image:
            if let media = item.mediaPreviewURL {
                return ([media], [])
            }
            let imageFiles = item.fileURLs.filter(\.isFileURL)
            if !imageFiles.isEmpty {
                return (imageFiles, [])
            }
            if let url = writeImageTempFile(for: item) {
                return ([url], [url])
            }
            return textFallback(for: item)

        case .link:
            if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               let link = URL(string: text), link.scheme != nil {
                if let webloc = TemporaryFileStorageService.shared.createTempFileSync(for: .url(link)) {
                    return ([webloc], [webloc])
                }
            }
            return textFallback(for: item)

        case .text:
            return textFallback(for: item)
        }
    }

    // MARK: - Private

    private static func textFallback(for item: HistoryItem) -> (urls: [URL], temporary: [URL]) {
        if let data = item.rtfData, let url = writeTemp(data: data, filename: "Clipboard.rtf") {
            return ([url], [url])
        }
        if let data = item.htmlData, let url = writeTemp(data: data, filename: "Clipboard.html") {
            return ([url], [url])
        }
        let text = (item.text ?? item.previewableText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ([], []) }
        if let url = TemporaryFileStorageService.shared.createTempFileSync(for: .text(text)) {
            return ([url], [url])
        }
        return ([], [])
    }

    private static func writeImageTempFile(for item: HistoryItem) -> URL? {
        if let data = item.imageData {
            let filename = imageFilename(for: data)
            if let url = writeTemp(data: data, filename: filename) {
                return url
            }
        }
        // Last resort: re-encode via NSImage → PNG
        guard let image = item.image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return writeTemp(data: png, filename: "Clipboard.png")
    }

    private static func imageFilename(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "Clipboard.png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "Clipboard.jpg" }
        if data.count >= 12 {
            let heic = data.subdata(in: 4..<12)
            if heic == Data("ftypheic".utf8) || heic == Data("ftypheif".utf8) || heic == Data("ftypmif1".utf8) {
                return "Clipboard.heic"
            }
        }
        // TIFF magic / default
        return "Clipboard.tiff"
    }

    private static func writeTemp(data: Data, filename: String) -> URL? {
        TemporaryFileStorageService.shared.createTempFileSync(
            for: .data(data, suggestedName: filename)
        )
    }

    static func cleanupTemporary(_ urls: [URL]) {
        for url in urls {
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
        }
    }
}

// MARK: - Sync temp file API (clipboard Space must be snappy)

extension TemporaryFileStorageService {
    /// Synchronous temp-file creation for keyboard-driven Quick Look.
    func createTempFileSync(for type: TempFileType) -> URL? {
        // Mirror private createTempFile without exposing the whole service surface.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let uuid = UUID().uuidString

        switch type {
        case .data(let data, let suggestedName):
            let filename = suggestedName ?? "clipboard.dat"
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent(filename)
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                return nil
            }

        case .text(let string):
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent("Clipboard.txt")
            guard let data = string.data(using: .utf8) else { return nil }
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                return nil
            }

        case .url(let url):
            let host = url.host ?? "link"
            let safeHost = host.replacingOccurrences(of: "/", with: "-")
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent("\(safeHost).webloc")
            let plist: [String: Any] = ["URL": url.absoluteString]
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                return nil
            }
        }
    }
}
