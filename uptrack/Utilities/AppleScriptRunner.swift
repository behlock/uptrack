import Foundation
import os

/// Executes AppleScript off the main thread, one script at a time.
///
/// `NSAppleScript` drives the OSA machinery, which is not safe to use from several
/// threads concurrently. Every AppleScript in the app (playback control, artwork
/// lookup) funnels through this actor so scripts never overlap and never block
/// the UI. A misbehaving target app can only stall this actor's queue.
actor AppleScriptRunner {
    static let shared = AppleScriptRunner()

    /// Run a script for its side effects. Returns `false` on a compile or runtime error.
    @discardableResult
    func execute(_ source: String, label: String) -> Bool {
        run(source, label: label) != nil
    }

    /// Run a script and return its result as a string (`nil` on error or empty result).
    func string(_ source: String, label: String) -> String? {
        guard let value = run(source, label: label)?.stringValue, !value.isEmpty else { return nil }
        return value
    }

    /// Run a script and return its result as raw bytes (`nil` on error or empty result).
    func data(_ source: String, label: String) -> Data? {
        guard let descriptor = run(source, label: label) else { return nil }
        // `raw data` arrives as a typeData descriptor; fall back to coercion if
        // AppleScript wrapped it (e.g. as `typePicture`) instead.
        if !descriptor.data.isEmpty {
            return descriptor.data
        }
        if let coerced = descriptor.coerce(toDescriptorType: typeData)?.data, !coerced.isEmpty {
            return coerced
        }
        return nil
    }

    private func run(_ source: String, label: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            Logger.appleScript.debug("\(label): could not compile script")
            return nil
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            Logger.appleScript.debug("\(label): \(error)")
            return nil
        }
        return result
    }
}
