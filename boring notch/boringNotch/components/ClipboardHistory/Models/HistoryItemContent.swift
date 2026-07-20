//
//  HistoryItemContent.swift
//  boringNotch — ported from Maccy
//

import Foundation
import SwiftData

@Model
final class HistoryItemContent {
    var type: String = ""
    var value: Data?

    @Relationship
    var item: HistoryItem?

    init(type: String, value: Data? = nil) {
        self.type = type
        self.value = value
    }
}
