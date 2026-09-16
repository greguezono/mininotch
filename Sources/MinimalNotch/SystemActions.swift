import AppKit
import IOKit.pwr_mgt
import OSLog

struct ActionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct FinderTransaction {
    var read: () throws -> Any?
    var write: (Any?) throws -> Void
    var restart: () throws -> Void
    func toggle() throws -> Bool {
        let saved = try read()
        let target = !Self.bool(saved)
        do {
            try write(target)
            try restart()
            guard Self.bool(try read()) == target else { throw ActionError("Finder preference readback failed.") }
            return target
        } catch {
            do { try write(saved) }
            catch { throw ActionError("Finder state unknown; preference restoration failed: \(error.localizedDescription)") }
            throw ActionError("Finder state unknown. Original preference restored; reopen Finder when idle. \(error.localizedDescription)")
        }
    }
    static func bool(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        return (value as? NSString)?.boolValue ?? false
    }
}

final class NativeFinder {
    private let domain = "com.apple.finder" as CFString
    private let key = "AppleShowAllFiles" as CFString
    private var pendingQuit: NSRunningApplication?
    func read() throws -> Any? {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw ActionError("Could not read Finder preferences.")
        }
        return CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    func write(_ value: Any?) throws {
        CFPreferencesSetValue(key, value as CFPropertyList?, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let observed = try read()
        guard NSDictionary(dictionary: observed.map { ["value": $0] } ?? [:]).isEqual(to: value.map { ["value": $0] } ?? [:]) else {
            throw ActionError("Finder preference write failed.")
        }
    }
    func restart() throws {
        if let pendingQuit, !pendingQuit.isTerminated {
            throw ActionError("A previous Finder quit remains unresolved. Wait and reopen Finder manually.")
        }
        pendingQuit = nil
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            pendingQuit = finder
            guard finder.terminate() else { throw ActionError("Finder refused to quit normally.") }
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while !finder.isTerminated {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw ActionError("Finder quit timed out; no force quit was used.") }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
            pendingQuit = nil
        }
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), configuration: configuration) { app, error in
            failure = error ?? (app == nil ? ActionError("Finder did not launch.") : nil)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 10) == .success else { throw ActionError("Finder launch timed out.") }
        if let failure { throw failure }
    }
    func toggle() throws -> Bool { try FinderTransaction(read: read, write: write, restart: restart).toggle() }
    static func emptyTrash() throws {
        var error: NSDictionary?
        let script = NSAppleScript(source: "with timeout of 30 seconds\ntell application \"Finder\" to empty trash\nend timeout")!
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == -1743 { throw ActionError("Allow MinimalNotch to control Finder in System Settings → Privacy & Security → Automation.") }
            if code == -128 { throw ActionError("Empty Trash was cancelled.") }
            if code == -1712 { throw ActionError("Finder timed out. Trash completion is unknown; check Finder before retrying.") }
            throw ActionError("Finder could not empty Trash: \(error[NSAppleScript.errorMessage] ?? error)")
        }
    }
}

@MainActor final class SystemActions: ObservableObject {
    enum Action: String, CaseIterable { case hidden, sleep, trash }
    @Published private(set) var hiddenFiles: Bool?
    @Published private(set) var sleepPrevented = false
    @Published private(set) var inFlight: Set<Action> = []
    @Published var error: String?
    private var assertion: IOPMAssertionID = 0
    private var hiddenUncertain = false
    private let queue = DispatchQueue(label: "MinimalNotch.Finder")
    private let readHidden: () throws -> Bool
    private let toggleHidden: () throws -> Bool
    private let trash: () throws -> Void
    private let log = OSLog(subsystem: "local.greguezono.MinimalNotch", category: .pointsOfInterest)
    // Test-only observer; production uses OSLog and never injects destructive diagnostic work.
    var timing: ((Action, String, Double) -> Void)?
    init(readHidden: @escaping () throws -> Bool, toggleHidden: @escaping () throws -> Bool, trash: @escaping () throws -> Void) {
        self.readHidden = readHidden; self.toggleHidden = toggleHidden; self.trash = trash
    }
    convenience init() {
        let finder = NativeFinder()
        self.init(readHidden: { FinderTransaction.bool(try finder.read()) }, toggleHidden: finder.toggle, trash: NativeFinder.emptyTrash)
    }
    private func mark(_ action: Action, _ phase: String) {
        os_signpost(.event, log: log, name: "Action", "%{public}s %{public}s", action.rawValue, phase)
        timing?(action, phase, ProcessInfo.processInfo.systemUptime)
    }
    func refreshHiddenFiles() {
        guard !inFlight.contains(.hidden), !hiddenUncertain else { return }
        let read = readHidden
        queue.async { [self] in
            let result = Result { try read() }
            DispatchQueue.main.async { [self] in
                guard !inFlight.contains(.hidden), !hiddenUncertain else { return }
                switch result {
                case .success(let state): hiddenFiles = state
                case .failure(let failure): hiddenFiles = nil; error = failure.localizedDescription
                }
            }
        }
    }
    private func run(_ action: Action, work: @escaping () throws -> Bool?, completion: @escaping (Bool?) -> Void) {
        guard !inFlight.contains(action) else { return }
        mark(action, "input"); inFlight.insert(action); mark(action, "feedback")
        mark(action, "enqueue")
        queue.async { [self] in
            let result = Result { try work() }
            DispatchQueue.main.async { [self] in
                inFlight.remove(action)
                switch result {
                case .success(let value): completion(value)
                case .failure(let failure):
                    if action == .hidden { hiddenFiles = nil; hiddenUncertain = true }
                    error = failure.localizedDescription
                }
                mark(action, "completion")
            }
        }
    }
    func toggleHiddenFiles(confirmed: Bool) {
        guard confirmed else { return }
        run(.hidden, work: { [self] in try toggleHidden() }) { [self] in hiddenFiles = $0; hiddenUncertain = false }
    }
    func emptyTrash(confirmed: Bool) {
        guard confirmed else { return }
        run(.trash, work: { [self] in try trash(); return nil }) { _ in }
    }
    func toggleSleep() {
        mark(.sleep, "input"); inFlight.insert(.sleep); mark(.sleep, "feedback"); mark(.sleep, "enqueue")
        let status: IOReturn
        if assertion == 0 {
            var created: IOPMAssertionID = 0
            status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "MinimalNotch Keep Awake" as CFString, &created)
            if status == kIOReturnSuccess { assertion = created }
        } else {
            status = IOPMAssertionRelease(assertion)
            if status == kIOReturnSuccess { assertion = 0 }
        }
        sleepPrevented = assertion != 0
        if status != kIOReturnSuccess { error = "Could not change sleep prevention (\(status))." }
        inFlight.remove(.sleep); mark(.sleep, "completion")
    }
    func shutdown() { if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0; sleepPrevented = false } }
}
