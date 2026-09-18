import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import OSLog

enum PermissionRecovery {
    case accessibility, automation
    var settingsURL: URL {
        switch self {
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .automation: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        }
    }
}

struct ActionError: LocalizedError {
    let message: String
    let recovery: PermissionRecovery?
    init(_ message: String, recovery: PermissionRecovery? = nil) { self.message = message; self.recovery = recovery }
    var errorDescription: String? { message }
}

final class NativeFinder {
    static func requirePostingAccess(preflight: () -> Bool = CGPreflightPostEventAccess, request: () -> Bool = CGRequestPostEventAccess) throws {
        guard preflight() || request() else {
            throw ActionError("MiniNotch needs Accessibility access to send Finder’s hidden-files shortcut. Enable MiniNotch in System Settings → Privacy & Security → Accessibility, then click Toggle hidden files again.", recovery: .accessibility)
        }
    }
    static func hiddenFileShortcut() throws -> (down: CGEvent, up: CGEvent) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Period), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Period), keyDown: false) else {
            throw ActionError("Could not create the Finder keyboard shortcut.")
        }
        down.flags = [.maskCommand, .maskShift]
        up.flags = [.maskCommand, .maskShift]
        return (down, up)
    }
    static func finderPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first { !$0.isTerminated }?.processIdentifier
    }
    static func toggle(finder: pid_t? = finderPID(), access: () throws -> Void = { try requirePostingAccess() }, post: (CGEvent, pid_t) -> Void = { $0.postToPid($1) }) throws {
        guard let finder else { throw ActionError("Open a Finder window, then try Toggle hidden files again.") }
        try access()
        let events = try hiddenFileShortcut()
        post(events.down, finder)
        post(events.up, finder)
    }
    static func emptyTrash(script: NSAppleScript = NSAppleScript(source: "with timeout of 30 seconds\ntell application \"Finder\"\nif exists items of trash then empty trash\nend tell\nend timeout")!) throws {
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == -1743 { throw ActionError("MiniNotch needs permission to control Finder to empty Trash. Enable Finder under MiniNotch in System Settings → Privacy & Security → Automation. Click Empty Trash again only when you want to empty it.", recovery: .automation) }
            if code == -128 { return }
            if code == -1712 { throw ActionError("Finder timed out. Trash completion is unknown; check Finder before retrying.") }
            throw ActionError("Finder could not empty Trash: \(error[NSAppleScript.errorMessage] ?? error)")
        }
    }
}

@MainActor final class SystemActions: ObservableObject {
    enum Action: String, CaseIterable { case hidden, sleep, trash }
    struct Failure: Equatable { let action: Action; let message: String; let recovery: PermissionRecovery? }
    @Published private(set) var sleepPrevented = false
    // ponytail: tracks this session's shortcuts; use Finder state observation if external changes must sync.
    @Published private(set) var hiddenFilesShown = false
    @Published private(set) var inFlight: Set<Action> = []
    @Published var error: Failure?
    private var assertion: IOPMAssertionID = 0
    private let queue = DispatchQueue(label: "MinimalNotch.Finder")
    private let toggleHidden: () throws -> Void
    private let trash: () throws -> Void
    private let log = OSLog(subsystem: "local.greguezono.MinimalNotch", category: .pointsOfInterest)
    // Test-only observer; production uses OSLog and never injects destructive diagnostic work.
    var timing: ((Action, String, Double) -> Void)?
    init(toggleHidden: @escaping () throws -> Void, trash: @escaping () throws -> Void) {
        self.toggleHidden = toggleHidden; self.trash = trash
    }
    convenience init() {
        self.init(toggleHidden: { try NativeFinder.toggle() }, trash: { try NativeFinder.emptyTrash() })
    }
    private func mark(_ action: Action, _ phase: String) {
        os_signpost(.event, log: log, name: "Action", "%{public}s %{public}s", action.rawValue, phase)
        timing?(action, phase, ProcessInfo.processInfo.systemUptime)
    }
    private func run(_ action: Action, work: @escaping () throws -> Void) {
        guard !inFlight.contains(action) else { return }
        mark(action, "input"); inFlight.insert(action); mark(action, "feedback")
        mark(action, "enqueue")
        queue.async { [self] in
            let result = Result { try work() }
            DispatchQueue.main.async { [self] in
                inFlight.remove(action)
                switch result {
                case .success:
                    if action == .hidden { hiddenFilesShown.toggle() }
                    if error?.action == action { error = nil }
                case .failure(let failure):
                    error = Failure(action: action, message: failure.localizedDescription, recovery: (failure as? ActionError)?.recovery)
                }
                mark(action, "completion")
            }
        }
    }
    func toggleHiddenFiles() {
        run(.hidden, work: toggleHidden)
    }
    func emptyTrash() {
        run(.trash, work: trash)
    }
    func toggleSleep() {
        mark(.sleep, "input"); inFlight.insert(.sleep); mark(.sleep, "feedback"); mark(.sleep, "enqueue")
        let status: IOReturn
        if assertion == 0 {
            var created: IOPMAssertionID = 0
            status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "MiniNotch Keep Awake" as CFString, &created)
            if status == kIOReturnSuccess { assertion = created }
        } else {
            status = IOPMAssertionRelease(assertion)
            if status == kIOReturnSuccess { assertion = 0 }
        }
        sleepPrevented = assertion != 0
        if status != kIOReturnSuccess { error = Failure(action: .sleep, message: "Could not change sleep prevention (\(status)).", recovery: nil) }
        else if error?.action == .sleep { error = nil }
        inFlight.remove(.sleep); mark(.sleep, "completion")
    }
    func shutdown() { if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0; sleepPrevented = false } }
}
