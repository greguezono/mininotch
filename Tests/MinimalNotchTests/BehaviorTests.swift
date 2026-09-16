import XCTest
@testable import MinimalNotch

final class BehaviorTests: XCTestCase {
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
    func testHiddenRollbackIncludingAbsentValue() throws {
        for initial: Any? in [nil, false, "YES"] {
            var value = initial
            var restarts = 0
            let transaction = FinderTransaction(read: { value }, write: { value = $0 }, restart: {
                restarts += 1; throw ActionError("refused")
            })
            XCTAssertThrowsError(try transaction.toggle())
            XCTAssertEqual(String(describing: value), String(describing: initial))
            XCTAssertEqual(restarts, 1)
        }
    }
    func testHiddenSuccessRequiresReadback() throws {
        var value: Any? = false
        let transaction = FinderTransaction(read: { value }, write: { value = $0 }, restart: {})
        XCTAssertTrue(try transaction.toggle())
        let mismatch = FinderTransaction(read: { false }, write: { _ in }, restart: {})
        XCTAssertThrowsError(try mismatch.toggle())
    }
    @MainActor func testCancelDuplicateAndFailure() async {
        var calls = 0
        let actions = SystemActions(readHidden: { false }, toggleHidden: { throw ActionError("denied") }, trash: { calls += 1; throw ActionError("cancelled") })
        actions.emptyTrash(confirmed: false)
        actions.toggleHiddenFiles(confirmed: false)
        XCTAssertEqual(calls, 0); XCTAssertTrue(actions.inFlight.isEmpty)
        actions.emptyTrash(confirmed: true); actions.emptyTrash(confirmed: true)
        while !actions.inFlight.isEmpty { await Task.yield() }
        XCTAssertEqual(calls, 1); XCTAssertNotNil(actions.error)
        actions.toggleHiddenFiles(confirmed: true)
        while !actions.inFlight.isEmpty { await Task.yield() }
        XCTAssertNil(actions.hiddenFiles); XCTAssertNotNil(actions.error)
    }
    @MainActor func testInjectedTimingAndUnknownState() async throws {
        let actions = SystemActions(readHidden: { false }, toggleHidden: { true }, trash: {})
        var samples: [[String: Any]] = []
        actions.timing = { action, phase, time in samples.append(["action": action.rawValue, "phase": phase, "seconds": time]) }
        for _ in 0..<101 {
            actions.toggleHiddenFiles(confirmed: true)
            while !actions.inFlight.isEmpty { await Task.yield() }
            actions.emptyTrash(confirmed: true)
            while !actions.inFlight.isEmpty { await Task.yield() }
        }
        XCTAssertEqual(samples.count, 808)
        XCTAssertEqual(actions.hiddenFiles, true)
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys])
        if let output = ProcessInfo.processInfo.environment["MINIMAL_NOTCH_TIMING_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: output))
        }
        for message in ["permission denied", "timeout", "cancelled"] {
            let failure = SystemActions(readHidden: { false }, toggleHidden: { throw ActionError(message) }, trash: { throw ActionError(message) })
            failure.toggleHiddenFiles(confirmed: true)
            while !failure.inFlight.isEmpty { await Task.yield() }
            failure.refreshHiddenFiles()
            await Task.yield()
            XCTAssertNil(failure.hiddenFiles)
            XCTAssertTrue(failure.error?.contains(message) == true)
            failure.emptyTrash(confirmed: true)
            while !failure.inFlight.isEmpty { await Task.yield() }
            XCTAssertTrue(failure.error?.contains(message) == true)
        }
    }

    func testRestorationFailureReportsUnknown() {
        var writes = 0
        let transaction = FinderTransaction(read: { nil }, write: { _ in
            writes += 1
            if writes == 2 { throw ActionError("disk unavailable") }
        }, restart: { throw ActionError("timeout") })
        XCTAssertThrowsError(try transaction.toggle()) { error in
            XCTAssertTrue(error.localizedDescription.contains("state unknown"))
            XCTAssertTrue(error.localizedDescription.contains("restoration failed"))
        }
        XCTAssertEqual(writes, 2)
    }

    @MainActor func testActualSleepOptIn() throws {
        guard ProcessInfo.processInfo.environment["MINIMAL_NOTCH_TEST_SLEEP"] == "1" else {
            throw XCTSkip("Set MINIMAL_NOTCH_TEST_SLEEP=1 to exercise actual IOKit assertions.")
        }
        let actions = SystemActions(readHidden: { false }, toggleHidden: { false }, trash: {})
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
