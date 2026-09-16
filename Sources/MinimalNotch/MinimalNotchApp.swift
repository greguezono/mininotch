import AppKit
import SwiftUI
import Combine

final class TrackingView: NSView {
    var changed: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { changed?(true) }
    override func mouseExited(with event: NSEvent) { changed?(false) }
}
final class NotchPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let actions = SystemActions()
    private var state = PanelState()
    private var panel: NotchPanel!
    private var trigger: NSPanel!
    private var status: NSStatusItem!
    private var hide: DispatchWorkItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var screen: NSScreen?
    private var dialog = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.escape = { [weak self] in self?.dismiss() }
        let tracking = TrackingView()
        tracking.changed = { [weak self] in self?.pointer($0) }
        let content = NSHostingView(rootView: ControlsView(actions: actions, confirm: { [weak self] in self?.confirm($0) }, dismissError: { [weak self] in self?.actions.error = nil }))
        tracking.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: tracking.leadingAnchor), content.trailingAnchor.constraint(equalTo: tracking.trailingAnchor), content.topAnchor.constraint(equalTo: tracking.topAnchor), content.bottomAnchor.constraint(equalTo: tracking.bottomAnchor)])
        panel.contentView = tracking
        trigger = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        trigger.isOpaque = false; trigger.backgroundColor = .clear; trigger.hasShadow = false
        trigger.level = .statusBar; trigger.hidesOnDeactivate = false
        trigger.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let activation = TrackingView(); activation.changed = { [weak self] in self?.pointer($0) }; trigger.contentView = activation
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "MinimalNotch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Quick Actions", action: #selector(showHide), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit MinimalNotch", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; status.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(place), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        actions.$error.dropFirst().receive(on: RunLoop.main).sink { [weak self] error in
            guard let self else { return }
            state.hold = dialog || error != nil
            if error != nil { state.enter(); state.exit() }
            place(); render(); scheduleHide()
        }.store(in: &subscriptions)
        place(); actions.refreshHiddenFiles()
    }
    @objc private func place() {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let display = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let display else { panel.orderOut(nil); trigger.orderOut(nil); return }
        let top = screen == nil ? display.visibleFrame.maxY : display.frame.maxY - display.safeAreaInsets.top
        let height: CGFloat = actions.error == nil ? 125 : 265
        panel.setFrame(NSRect(x: display.frame.midX - 132, y: top - height, width: 264, height: height), display: true)
        if let screen {
            let left = screen.auxiliaryTopLeftArea?.maxX ?? (screen.frame.midX - 70)
            let right = screen.auxiliaryTopRightArea?.minX ?? (screen.frame.midX + 70)
            // The two-point bridge sits below the housing, outside the menu bar.
            trigger.setFrame(NSRect(x: left, y: top - 2, width: max(1, right - left), height: 2), display: true)
            trigger.orderFrontRegardless()
        } else { trigger.orderOut(nil) }
    }
    private func pointer(_ entered: Bool) {
        hide?.cancel()
        if entered {
            let wasVisible = state.visible
            state.enter()
            if !wasVisible { actions.refreshHiddenFiles() }
            render()
        } else { state.exit(); scheduleHide() }
    }
    private func scheduleHide() {
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.state.expire(); self?.render() }
        hide = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    private func render() {
        if state.visible {
            guard !panel.isVisible else { return }
            panel.alphaValue = 0; panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
                panel.animator().alphaValue = 1
            }
        } else { panel.orderOut(nil) }
    }
    private func dismiss() { guard !dialog else { return }; state.escape(); render() }
    @objc private func showHide() {
        if state.visible { dismiss() }
        else { state.showKeyboard(); actions.refreshHiddenFiles(); render(); NSApp.activate(); panel.makeKey() }
    }
    private func confirm(_ action: SystemActions.Action) {
        guard !dialog && !actions.inFlight.contains(action) else { return }
        dialog = true; state.hold = true
        let alert = NSAlert()
        if action == .hidden {
            alert.messageText = "Restart Finder to toggle hidden files?"
            alert.informativeText = "Finder must be idle: no copy, move, delete, or other file operation. Finder windows may close briefly. Keep Finder idle until this action finishes."
            alert.addButton(withTitle: "Finder Is Idle — Continue")
        } else {
            alert.messageText = "Empty Trash?"
            alert.informativeText = "Finder will permanently delete the items in Trash. This cannot be undone."
            alert.addButton(withTitle: "Empty Trash")
        }
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = ""; alert.buttons[1].keyEquivalent = "\r"
        NSApp.activate(); panel.makeKey()
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            dialog = false; state.hold = actions.error != nil
            let confirmed = response == .alertFirstButtonReturn
            if action == .hidden { actions.toggleHiddenFiles(confirmed: confirmed) }
            else { actions.emptyTrash(confirmed: confirmed) }
            // Mouse dialogs do not leave keyboard presentation pinned open.
            scheduleHide()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !actions.inFlight.isEmpty { NSSound.beep(); return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { actions.shutdown() }
}
@main struct MinimalNotchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
