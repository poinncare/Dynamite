//
//  ClipboardRelativeTime.swift
//  Rough Pasta-style relative time: now / 1m / 1h / 1d (Latin, no localization)
//

import Foundation

enum ClipboardRelativeTime {
    static func format(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return "now"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }
        let days = hours / 24
        return "\(days)d"
    }
}
