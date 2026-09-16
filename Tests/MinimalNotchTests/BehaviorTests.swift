import XCTest
import AppKit
import CoreGraphics
@testable import MinimalNotch

final class BehaviorTests: XCTestCase {
    func testPostingPermissionRequestsOnlyWhenMissingAndHonorsDenial() {
        for allowed in [false, true] {
            for granted in [false, true] {
                var requests = 0
                let check = { try NativeFinder.requirePostingAccess(preflight: { allowed }, request: { requests += 1; return granted }) }
                if allowed || granted { XCTAssertNoThrow(try check()) }
                else { XCTAssertThrowsError(try check()) }
                XCTAssertEqual(requests, allowed ? 0 : 1)
            }
        }
    }
    func testVisibility() {
        var panel = PanelState()
        panel.enter(); panel.exit(); panel.enter(); panel.expire()
        XCTAssertTrue(panel.visible)
        panel.exit(); panel.expire()
        XCTAssertFalse(panel.visible)
        panel.showKeyboard(); panel.exit(); panel.expire()
        XCTAssertTrue(panel.visible)
        panel.escape(); XCTAssertFalse(panel.visible)
        panel.enter(); panel.hold = true; panel.exit(); panel.expire()
        XCTAssertTrue(panel.visible)
        panel.hold = false; panel.expire(); XCTAssertFalse(panel.visible)
    }
    func testWholeNotchPointerRegion() {
        let notch = CGRect(x: 700, y: 970, width: 160, height: 30)
        let panel = CGRect(x: 648, y: 845, width: 264, height: 125)
        for point in [CGPoint(x: 780, y: 1000), CGPoint(x: 700, y: 985), CGPoint(x: 860, y: 985), CGPoint(x: 780, y: 970)] {
            XCTAssertTrue(pointerInsideActions(point, notch: notch, panel: panel, panelVisible: false))
        }
        XCTAssertFalse(pointerInsideActions(CGPoint(x: 699, y: 985), notch: notch, panel: panel, panelVisible: true))
        XCTAssertFalse(pointerInsideActions(CGPoint(x: 861, y: 985), notch: notch, panel: panel, panelVisible: true))
        XCTAssertTrue(pointerInsideActions(CGPoint(x: 780, y: 969), notch: notch, panel: panel, panelVisible: true))
        XCTAssertTrue(pointerInsideActions(CGPoint(x: 650, y: 900), notch: notch, panel: panel, panelVisible: true))
        XCTAssertFalse(pointerInsideActions(CGPoint(x: 650, y: 900), notch: notch, panel: panel, panelVisible: false))
        XCTAssertFalse(pointerInsideActions(CGPoint(x: 780, y: 844), notch: notch, panel: panel, panelVisible: true))
        XCTAssertFalse(pointerInsideActions(CGPoint(x: 780, y: 1000), notch: nil, panel: panel, panelVisible: false))
    }
    @MainActor func testHiddenShortcutRunsWithoutConfirmationAndSuppressesDuplicates() async {
        var calls = 0
        let actions = SystemActions(toggleHidden: { calls += 1 }, trash: {})
        XCTAssertFalse(actions.hiddenFilesShown)
        actions.toggleHiddenFiles()
        actions.toggleHiddenFiles()
        XCTAssertTrue(actions.inFlight.contains(.hidden))
        while !actions.inFlight.isEmpty { await Task.yield() }
        XCTAssertEqual(calls, 1)
        XCTAssertNil(actions.error)
        XCTAssertTrue(actions.hiddenFilesShown)
        actions.emptyTrash()
        while !actions.inFlight.isEmpty { await Task.yield() }
        XCTAssertTrue(actions.hiddenFilesShown)
        actions.toggleHiddenFiles()
        while !actions.inFlight.isEmpty { await Task.yield() }
        XCTAssertFalse(actions.hiddenFilesShown)
    }
    func testHiddenShortcutUsesCommandShiftPeriod() throws {
        let events = try NativeFinder.hiddenFileShortcut()
        XCTAssertEqual(events.down.type, .keyDown)
        XCTAssertEqual(events.up.type, .keyUp)
        for event in [events.down, events.up] {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 47)
            XCTAssertEqual(event.flags, [.maskCommand, .maskShift])
        }
    }
    @MainActor func testTrashCancellationIsSilentAndFailuresRemainVisible() async {
        for (source, expectedError) in [("return", false), ("error number -128", false), ("error number -1743", true), ("error number -1712", true)] {
            let actions = SystemActions(toggleHidden: {}, trash: {
                try NativeFinder.emptyTrash(script: NSAppleScript(source: source)!)
            })
            actions.emptyTrash()
            while !actions.inFlight.isEmpty { await Task.yield() }
            XCTAssertEqual(actions.error != nil, expectedError, source)
        }
    }
    @MainActor func testDuplicateAndFailure() async {
        var calls = 0
        let actions = SystemActions(toggleHidden: { throw ActionError("denied") }, trash: { calls += 1; throw ActionError("cancelled") })
        actions.emptyTrash(); actions.emptyTrash()
        while !actions.inFlight.isEmpty { await Task.yield() }
        XCTAssertEqual(calls, 1); XCTAssertNotNil(actions.error)
        actions.toggleHiddenFiles()
        while !actions.inFlight.isEmpty { await Task.yield() }
        XCTAssertEqual(actions.error, "denied")
        XCTAssertFalse(actions.hiddenFilesShown)
    }
    @MainActor func testInjectedTimingAndErrors() async throws {
        let actions = SystemActions(toggleHidden: {}, trash: {})
        var samples: [[String: Any]] = []
        actions.timing = { action, phase, time in samples.append(["action": action.rawValue, "phase": phase, "seconds": time]) }
        for _ in 0..<101 {
            actions.toggleHiddenFiles()
            while !actions.inFlight.isEmpty { await Task.yield() }
            actions.emptyTrash()
            while !actions.inFlight.isEmpty { await Task.yield() }
        }
        XCTAssertEqual(samples.count, 808)
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys])
        if let output = ProcessInfo.processInfo.environment["MINIMAL_NOTCH_TIMING_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: output))
        }
        for message in ["permission denied", "timeout", "cancelled"] {
            let failure = SystemActions(toggleHidden: { throw ActionError(message) }, trash: { throw ActionError(message) })
            failure.toggleHiddenFiles()
            while !failure.inFlight.isEmpty { await Task.yield() }
            XCTAssertTrue(failure.error?.contains(message) == true)
            failure.emptyTrash()
            while !failure.inFlight.isEmpty { await Task.yield() }
            XCTAssertTrue(failure.error?.contains(message) == true)
        }
    }

    @MainActor func testActualSleepOptIn() throws {
        guard ProcessInfo.processInfo.environment["MINIMAL_NOTCH_TEST_SLEEP"] == "1" else {
            throw XCTSkip("Set MINIMAL_NOTCH_TEST_SLEEP=1 to exercise actual IOKit assertions.")
        }
        let actions = SystemActions(toggleHidden: {}, trash: {})
        defer { actions.shutdown() }
        var samples: [[String: Any]] = []
        actions.timing = { action, phase, time in samples.append(["action": action.rawValue, "phase": phase, "seconds": time]) }
        for index in 0..<102 {
            actions.toggleSleep()
            XCTAssertNil(actions.error)
            XCTAssertEqual(actions.sleepPrevented, index.isMultiple(of: 2))
            XCTAssertTrue(actions.inFlight.isEmpty)
        }
        XCTAssertFalse(actions.sleepPrevented)
        actions.shutdown()
        XCTAssertFalse(actions.sleepPrevented)
        XCTAssertEqual(samples.count, 408)
        if let output = ProcessInfo.processInfo.environment["MINIMAL_NOTCH_SLEEP_TIMING_OUTPUT"] {
            let data = try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: output))
        }
    }

}
