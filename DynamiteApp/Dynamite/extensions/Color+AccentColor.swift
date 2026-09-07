//
//  Color+AccentColor.swift
//  Dynamite
//
//  Created by Alexander on 2025-10-24.
//

import SwiftUI
import Defaults
import Combine

/// Publishes a lightweight revision whenever the user changes the accent
/// preference. Defaults values are not themselves SwiftUI state, so views
/// which use Color.effectiveAccent need an explicit invalidation signal.
final class AccentColorStore: ObservableObject {
    static let shared = AccentColorStore()

    @Published private(set) var revision: UInt = 0
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        Defaults.publisher(.useCustomAccentColor)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.revision &+= 1 }
            .store(in: &cancellables)

        Defaults.publisher(.customAccentColorData)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.revision &+= 1 }
            .store(in: &cancellables)
    }
}

extension Color {
    static var effectiveAccent: Color {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return Color(nsColor: nsColor)
        }
        return .accentColor
    }
    
    /// Returns a darker version of the accent color suitable for backgrounds
    static var effectiveAccentBackground: Color {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return Color(nsColor: nsColor.withSystemEffect(.disabled))
        }
        return Color.effectiveAccent.opacity(0.25)
    }
}

extension NSColor {
    static var effectiveAccent: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return nsColor
        }
        return NSColor.controlAccentColor
    }
    
    /// Returns a darker version of the accent color as NSColor suitable for backgrounds
    static var effectiveAccentBackground: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return nsColor.withSystemEffect(.disabled)
        }
        return NSColor.controlAccentColor.withAlphaComponent(0.25)
    }
}
