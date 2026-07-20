//
//  AppLanguage.swift
//  boringNotch — in-app EN/RU localization without changing system AppleLanguages
//

import Defaults
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Display name always shown in both scripts for the picker itself.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

extension Defaults.Keys {
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .english)
}

/// Observes language so SwiftUI can re-render labels via `.id(LanguageManager.shared.revision)`.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var language: AppLanguage
    /// Bumped on every change to force view refresh.
    @Published private(set) var revision: Int = 0

    private init() {
        language = Defaults[.appLanguage]
    }

    func setLanguage(_ lang: AppLanguage) {
        Defaults[.appLanguage] = lang
        language = lang
        revision &+= 1
    }
}

/// Resolve a localized string for the user-selected app language.
/// Keys are English source strings; `en.lproj` / `ru.lproj` provide values.
func L(_ key: String) -> String {
    let code = Defaults[.appLanguage].rawValue
    if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        let value = NSLocalizedString(key, tableName: "Pocket", bundle: bundle, value: key, comment: "")
        if value != key || code == "en" {
            return value
        }
    }
    // Fallback to English bundle, then key itself
    if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return NSLocalizedString(key, tableName: "Pocket", bundle: bundle, value: key, comment: "")
    }
    return key
}
