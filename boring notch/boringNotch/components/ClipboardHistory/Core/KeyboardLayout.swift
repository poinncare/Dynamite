//
//  KeyboardLayout.swift
//  boringNotch — ported from Maccy
//

import Carbon
import Sauce

final class KeyboardLayout {
    static var current: KeyboardLayout { KeyboardLayout() }

    var commandSwitchesToQWERTY: Bool { localizedName.hasSuffix("⌘") }

    var localizedName: String {
        if let value = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
            return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
        } else {
            return ""
        }
    }

    private var inputSource: TISInputSource!

    init() {
        inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue()
    }
}
