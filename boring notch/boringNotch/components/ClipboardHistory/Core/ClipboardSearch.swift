//
//  ClipboardSearch.swift
//  boringNotch — adapted from Maccy Search.swift
//

import AppKit
import Defaults
import Fuse
import SwiftData

struct ClipboardSearchable: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let item: HistoryItem

    static func == (lhs: ClipboardSearchable, rhs: ClipboardSearchable) -> Bool {
        lhs.id == rhs.id
    }
}

final class ClipboardSearch {
    enum Mode: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
        case exact
        case fuzzy
        case regexp
        case mixed

        var id: Self { self }

        var description: String {
            switch self {
            case .exact: return "Exact"
            case .fuzzy: return "Fuzzy"
            case .regexp: return "Regex"
            case .mixed: return "Mixed"
            }
        }
    }

    struct SearchResult: Equatable {
        var score: Double?
        var object: ClipboardSearchable
        var ranges: [Range<String.Index>] = []
    }

    private let fuse = Fuse(threshold: 0.7)
    private let fuzzySearchLimit = 5_000

    func search(string: String, within: [ClipboardSearchable]) -> [SearchResult] {
        guard !string.isEmpty else {
            return within.map { SearchResult(object: $0) }
        }

        switch Defaults[.clipboardSearchMode] {
        case .mixed:
            return mixedSearch(string: string, within: within)
        case .regexp:
            return simpleSearch(string: string, within: within, options: .regularExpression)
        case .fuzzy:
            return fuzzySearch(string: string, within: within)
        default:
            return simpleSearch(string: string, within: within, options: .caseInsensitive)
        }
    }

    private func fuzzySearch(string: String, within: [ClipboardSearchable]) -> [SearchResult] {
        let pattern = fuse.createPattern(from: string)
        let searchResults: [SearchResult] = within.compactMap { item in
            fuzzySearch(for: pattern, in: item.title, of: item)
        }
        return searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    }

    private func fuzzySearch(
        for pattern: Fuse.Pattern?,
        in searchString: String,
        of item: ClipboardSearchable
    ) -> SearchResult? {
        var searchString = searchString
        if searchString.count > fuzzySearchLimit {
            let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
            searchString = "\(searchString[...stopIndex])"
        }

        if let fuzzyResult = fuse.search(pattern, in: searchString) {
            return SearchResult(
                score: fuzzyResult.score,
                object: item,
                ranges: fuzzyResult.ranges.map {
                    let startIndex = searchString.startIndex
                    let lowerBound = searchString.index(startIndex, offsetBy: $0.lowerBound)
                    let upperBound = searchString.index(startIndex, offsetBy: $0.upperBound + 1)
                    return lowerBound..<upperBound
                }
            )
        }
        return nil
    }

    private func simpleSearch(
        string: String,
        within: [ClipboardSearchable],
        options: NSString.CompareOptions
    ) -> [SearchResult] {
        within.compactMap { simpleSearch(for: string, in: $0.title, of: $0, options: options) }
    }

    private func simpleSearch(
        for string: String,
        in searchString: String,
        of item: ClipboardSearchable,
        options: NSString.CompareOptions
    ) -> SearchResult? {
        if let range = searchString.range(of: string, options: options, range: nil, locale: nil) {
            return SearchResult(object: item, ranges: [range])
        }
        return nil
    }

    private func mixedSearch(string: String, within: [ClipboardSearchable]) -> [SearchResult] {
        var results = simpleSearch(string: string, within: within, options: .caseInsensitive)
        guard results.isEmpty else { return results }

        results = simpleSearch(string: string, within: within, options: .regularExpression)
        guard results.isEmpty else { return results }

        results = fuzzySearch(string: string, within: within)
        guard results.isEmpty else { return results }

        return []
    }
}
