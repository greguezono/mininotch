import AppKit
import CoreFoundation

let domain = "com.apple.finder" as CFString
let key = "AppleShowAllFiles" as CFString
let fm = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fixtureRoot = root.appendingPathComponent(".build/finder-fixture")
let recovery = fixtureRoot.appendingPathComponent("recovery.plist")

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func readPreference() throws -> Any? {
    guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
        throw ProbeError("Could not synchronize Finder preferences")
    }
    return CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
}

func snapshot(_ value: Any?) -> [String: Any] {
    var result: [String: Any] = ["present": value != nil]
    if let value { result["value"] = value }
    return result
}

func writePreference(_ value: Any?) throws {
    CFPreferencesSetValue(key, value as CFPropertyList?, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    let observed = try readPreference()
    guard NSDictionary(dictionary: snapshot(observed)).isEqual(to: snapshot(value)) else {
        throw ProbeError("Preference readback mismatch; recovery snapshot retained")
    }
}

func restore(_ saved: [String: Any]) throws {
    guard let present = saved["present"] as? Bool,
          present == (saved["value"] != nil) else { throw ProbeError("Invalid recovery snapshot") }
    try writePreference(saved["value"])
    print("Saved preference restored; value readback agrees. Finder pixels remain unverified.")
}

func script(_ body: String) throws {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: "with timeout of 10 seconds\n" + body + "\nend timeout") else {
        throw ProbeError("Could not construct AppleScript")
    }
    _ = script.executeAndReturnError(&error)
    if let error { throw ProbeError("Finder Apple Event failed: \(error)") }
}

func literal(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 10) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while !condition() {
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            throw ProbeError("Finder lifecycle timed out; no force termination attempted")
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
}

func launchFinder() throws {
    var completed = false
    var failure: Error?
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
        configuration: configuration
    ) { application, error in
        DispatchQueue.main.async {
            failure = error ?? (application == nil ? ProbeError("Finder launch returned no application") : nil)
            completed = true
        }
    }
    try waitUntil { completed }
    if let failure { throw failure }
}

func relaunchFinder(pendingQuit: inout NSRunningApplication?) throws {
    if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
        pendingQuit = finder
        guard finder.terminate() else { throw ProbeError("Finder normal quit request refused") }
        try waitUntil { finder.isTerminated }
        pendingQuit = nil
    }
    try launchFinder()
}

func exercise(relaunch: Bool = false) throws {
    if relaunch {
        print("This test normally quits and reopens Finder for each setting and restoration; Finder windows may close.")
        print("Do not start file operations until restoration finishes. No force quit will be used.")
    }
    print("Only proceed after confirming no Finder copy/move/delete operation is active.")
    print("Type IDLE to confirm; any other input exits without changing preferences:")
    guard readLine() == "IDLE" else { throw ProbeError("Idle precondition not confirmed") }
    guard !fm.fileExists(atPath: recovery.path) else {
        throw ProbeError("Recovery snapshot already exists. Restore and archive it before rerunning: \(recovery.path)")
    }
    let saved = snapshot(try readPreference())
    try fm.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: saved, format: .xml, options: 0)
    try data.write(to: recovery, options: .withoutOverwriting)
    var target: String?
    var restorationFailed = false
    var relaunchAttempted = false
    var pendingQuit: NSRunningApplication?
    defer {
        do {
            try restore(saved)
            if relaunchAttempted {
                if let pendingQuit, !pendingQuit.isTerminated {
                    throw ProbeError("Quit did not complete; saved preference restored, but delayed termination remains possible. Reopen Finder manually if it exits.")
                }
                try relaunchFinder(pendingQuit: &pendingQuit)
                if let target { try script("tell application \"Finder\" to open " + target) }
            }
            if let target {
                try script("tell application \"Finder\" to update " + target + " without registering applications")
            }
        }
        catch { restorationFailed = true; print("RESTORATION FAILED: \(error). Run --restore.") }
        print("Recovery snapshot retained: \(recovery.path)")
        if restorationFailed { exit(2) }
    }
    let fixture = fixtureRoot.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
    try Data("visible fixture\n".utf8).write(to: fixture.appendingPathComponent("visible.txt"))
    try Data("hidden fixture\n".utf8).write(to: fixture.appendingPathComponent(".hidden.txt"))
    let fixtureTarget = "(POSIX file " + literal(fixture.path) + " as alias)"
    target = fixtureTarget
    try script("tell application \"Finder\" to open " + fixtureTarget)
    for show in [true, false] {
        try writePreference(show)
        if relaunch {
            relaunchAttempted = true
            try relaunchFinder(pendingQuit: &pendingQuit)
            try script("tell application \"Finder\" to open " + fixtureTarget)
        }
        try script("tell application \"Finder\" to update " + fixtureTarget + " without registering applications")
        print("Preference = \(show); update returned. Inspect \(fixture.path)")
        print("Type VISIBLE or HIDDEN for actual .hidden.txt pixels; anything else aborts and restores:")
        guard let observed = readLine(), ["VISIBLE", "HIDDEN"].contains(observed) else {
            throw ProbeError("Visual observation cancelled")
        }
        guard (observed == "VISIBLE") == show else {
            throw ProbeError("BLOCKED: stored preference and visible Finder contents disagree")
        }
    }
    print("Both manual fixture observations matched; this does not establish an app-visible state API.")
}

do {
    switch CommandLine.arguments.dropFirst().first {
    case "--inspect":
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Exact current-user/any-host preference: \(snapshot(try readPreference()))")
        print("Recovery snapshot exists: \(fm.fileExists(atPath: recovery.path))")
        print("Candidate: CFPreferencesSetValue + Synchronize, then Finder update (fndrfupd).")
        print("No documented hidden-file visible-state or file-operation-idle property in Finder.sdef.")
        print("Read-only inspection; no Finder Apple Events sent.")
    case "--exercise": try exercise()
    case "--exercise-relaunch": try exercise(relaunch: true)
    case "--restore":
        let data = try Data(contentsOf: recovery)
        guard let saved = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ProbeError("Invalid recovery plist")
        }
        try restore(saved)
        print("Snapshot retained; manually verify Finder and archive snapshot before another exercise.")
    case "--self-test":
        for value: Any? in [nil, true, false, "YES", 1] {
            let saved = snapshot(value)
            let data = try PropertyListSerialization.data(fromPropertyList: saved, format: .xml, options: 0)
            let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            assert(NSDictionary(dictionary: saved).isEqual(to: decoded))
            assert((decoded["present"] as! Bool) == (value != nil))
        }
        assert(literal("a\"b\\c") == "\"a\\\"b\\\\c\"")
        try waitUntil({ true }, timeout: 0)
        do {
            try waitUntil({ false }, timeout: 0)
            assertionFailure("A false condition must time out")
        } catch is ProbeError { }
        print("PASS: lifecycle wait success/timeout; snapshot round trips preserve absent/value state; AppleScript escaping. No Finder writes.")
    default: throw ProbeError("Usage: FinderProbe.swift --inspect | --exercise | --exercise-relaunch | --restore | --self-test")
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
