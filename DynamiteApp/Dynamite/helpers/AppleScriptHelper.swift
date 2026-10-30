//
//  AppleScriptHelper.swift
//  Dynamite
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

struct AppleScriptValue: Sendable {
    let booleanValue: Bool?
    let stringValue: String?
    let doubleValue: Double?
    let int32Value: Int32?
    let data: Data?

    init(_ descriptor: NSAppleEventDescriptor) {
        booleanValue = descriptor.booleanValue
        stringValue = descriptor.stringValue
        doubleValue = descriptor.doubleValue
        int32Value = descriptor.int32Value
        data = descriptor.data as Data?
    }
}

struct AppleScriptResult: Sendable {
    private let values: [AppleScriptValue]

    init(_ descriptor: NSAppleEventDescriptor) {
        if descriptor.numberOfItems > 0 {
            values = (1...descriptor.numberOfItems).compactMap { index in
                descriptor.atIndex(index).map(AppleScriptValue.init)
            }
        } else {
            values = [AppleScriptValue(descriptor)]
        }
    }

    var numberOfItems: Int { values.count }
    var booleanValue: Bool { values.first?.booleanValue ?? false }
    var stringValue: String? { values.first?.stringValue }
    var int32Value: Int32 { values.first?.int32Value ?? 0 }

    func atIndex(_ index: Int) -> AppleScriptValue? {
        guard index > 0, values.indices.contains(index - 1) else { return nil }
        return values[index - 1]
    }
}

class AppleScriptHelper {
    @discardableResult
    class func execute(_ scriptText: String) async throws -> AppleScriptResult? {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: AppleScriptResult(descriptor))
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
    
    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
