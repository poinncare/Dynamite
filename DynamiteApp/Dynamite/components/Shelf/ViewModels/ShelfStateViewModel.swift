//
//  ShelfStateViewModel.swift
//  Dynamite
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var lastCleanupAt: Date?

    private init() {
        items = ShelfPersistenceService.shared.load()
        cleanupInvalidItemsIfNeeded()
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                self?.add(dropped)
                self?.isLoading = false
            }
        }
    }

    /// Validate persisted bookmarks away from SwiftUI's layout transaction.
    /// This used to run from ShelfView.onAppear on every tab switch. Resolving
    /// security-scoped bookmarks and probing the filesystem can block the main
    /// thread for an observable amount of time, especially with a large shelf.
    func cleanupInvalidItemsIfNeeded() {
        guard cleanupTask == nil else { return }
        if let lastCleanupAt, Date().timeIntervalSince(lastCleanupAt) < 30 {
            return
        }

        let candidates: [(ShelfItem.ID, Data)] = items.compactMap { item in
            guard case .file(let data) = item.kind else { return nil }
            return (item.id, data)
        }
        guard !candidates.isEmpty else {
            lastCleanupAt = Date()
            return
        }

        lastCleanupAt = Date()
        cleanupTask = Task { [weak self] in
            let invalidIDs = await Task.detached(priority: .utility) {
                var invalid = Set<ShelfItem.ID>()
                for (id, data) in candidates {
                    guard await !Bookmark(data: data).validate() else { continue }
                    invalid.insert(id)
                }
                return invalid
            }.value

            guard let self, !invalidIDs.isEmpty else {
                self?.cleanupTask = nil
                return
            }

            let invalidItems = self.items.filter { invalidIDs.contains($0.id) }
            invalidItems.forEach { $0.cleanupStoredData() }
            self.items.removeAll { invalidIDs.contains($0.id) }
            self.cleanupTask = nil
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
