//
//  ClipboardStorage.swift
//  boringNotch — adapted from Maccy Storage.swift
//

import Foundation
import SwiftData

@MainActor
final class ClipboardStorage {
    static let shared = ClipboardStorage()

    var container: ModelContainer
    var context: ModelContext { container.mainContext }

    private let url: URL

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("boringNotch", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("ClipboardHistory.sqlite")

        let config = ModelConfiguration(url: url)

        do {
            container = try ModelContainer(for: HistoryItem.self, HistoryItemContent.self, configurations: config)
        } catch {
            fatalError("Cannot load clipboard history database: \(error.localizedDescription)")
        }
    }
}
