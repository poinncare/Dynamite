//
//  ClipboardStorage.swift
//  Dynamite — adapted from Maccy Storage.swift
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
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("Dynamite", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("ClipboardHistory.sqlite")

        let config = ModelConfiguration(url: url)

        do {
            container = try ModelContainer(for: HistoryItem.self, HistoryItemContent.self, configurations: config)
        } catch {
            // A damaged/old store must not take down the whole menu-bar app.
            // Keep the original file for recovery and start a fresh persistent
            // store; the user can continue using Clipboard immediately.
            NSLog("Dynamite: clipboard store unavailable, using recovery store: \(error.localizedDescription)")
            let recoveryURL = dir.appendingPathComponent("ClipboardHistory-recovery.sqlite")
            do {
                container = try ModelContainer(
                    for: HistoryItem.self,
                    HistoryItemContent.self,
                    configurations: ModelConfiguration(url: recoveryURL)
                )
            } catch {
                // SwiftData's in-memory configuration is the final safety net
                // for permission or filesystem failures.
                NSLog("Dynamite: clipboard recovery store unavailable, using memory store: \(error.localizedDescription)")
                container = try! ModelContainer(
                    for: HistoryItem.self,
                    HistoryItemContent.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            }
        }
    }
}
