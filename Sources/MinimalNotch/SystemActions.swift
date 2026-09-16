import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import OSLog

struct ActionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class NativeFinder {
    static func requirePostingAccess(preflight: () -> Bool = CGPreflightPostEventAccess, request: () -> Bool = CGRequestPostEventAccess) throws {
        guard preflight() || request() else {
            throw ActionError("Allow MiniNotch in the macOS Accessibility prompt or System Settings → Privacy & Security → Accessibility, then retry. If it is already enabled but access is still denied, the saved permission may refer to an older build; see README’s permission reset steps.")
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
    static func toggle() throws {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              !finder.isTerminated else {
            throw ActionError("Open a Finder window, then try Toggle hidden files again.")
        }
        try requirePostingAccess()
        let events = try hiddenFileShortcut()
        events.down.postToPid(finder.processIdentifier)
        events.up.postToPid(finder.processIdentifier)
    }
    static func emptyTrash(script: NSAppleScript = NSAppleScript(source: "with timeout of 30 seconds\ntell application \"Finder\"\nif exists items of trash then empty trash\nend tell\nend timeout")!) throws {
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == -1743 { throw ActionError("Allow MiniNotch to control Finder in System Settings → Privacy & Security → Automation.") }
            if code == -128 { return }
            if code == -1712 { throw ActionError("Finder timed out. Trash completion is unknown; check Finder before retrying.") }
            throw ActionError("Finder could not empty Trash: \(error[NSAppleScript.errorMessage] ?? error)")
        }
    }
}

@MainActor final class SystemActions: ObservableObject {
    enum Action: String, CaseIterable { case hidden, sleep, trash }
    @Published private(set) var sleepPrevented = false
    // ponytail: tracks this session's shortcuts; use Finder state observation if external changes must sync.
    @Published private(set) var hiddenFilesShown = false
    @Published private(set) var inFlight: Set<Action> = []
    @Published var error: String?
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
        self.init(toggleHidden: NativeFinder.toggle, trash: { try NativeFinder.emptyTrash() })
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
                case .failure(let failure):
                    error = failure.localizedDescription
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
        if status != kIOReturnSuccess { error = "Could not change sleep prevention (\(status))." }
        inFlight.remove(.sleep); mark(.sleep, "completion")
    }
    func shutdown() { if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0; sleepPrevented = false } }
}
