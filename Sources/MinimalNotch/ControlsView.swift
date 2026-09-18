import SwiftUI

struct ControlsView: View {
    @ObservedObject var actions: SystemActions
    let dismissError: () -> Void
    @State private var hovered: SystemActions.Action?
    @FocusState private var focused: SystemActions.Action?
    @Environment(\.colorSchemeContrast) private var contrast
    private func label(_ action: SystemActions.Action) -> String {
        switch action {
        case .hidden: return "Toggle hidden files"
        case .sleep: return actions.sleepPrevented ? "Allow sleep" : "Prevent sleep"
        case .trash: return "Empty Trash"
        }
    }
    private let panel = UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
    private let tileRim = LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
    private let panelRim = LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.25)], startPoint: .top, endPoint: .bottom)
    private let dim = LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
    var body: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 8) { HStack(spacing: 8) {
                ForEach(SystemActions.Action.allCases, id: \.self) { action in
                    let active = action == .hidden ? actions.hiddenFilesShown : action == .sleep && actions.sleepPrevented
                    Button {
                        switch action {
                        case .hidden: actions.toggleHiddenFiles()
                        case .sleep: actions.toggleSleep()
                        case .trash: actions.emptyTrash()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(active ? 0.12 : 0))
                            RoundedRectangle(cornerRadius: 10).strokeBorder(contrast == .increased || focused == action ? AnyShapeStyle(Color.white) : AnyShapeStyle(tileRim), lineWidth: 1)
                            if actions.inFlight.contains(action) { ProgressView().controlSize(.small) }
                            else { Image(systemName: action == .hidden ? "doc.text.magnifyingglass" : action == .sleep ? "cup.and.saucer" : "trash").font(.system(size: 18, weight: .medium)) }
                            if active { Circle().fill(Color(red: 1, green: 0.85, blue: 0.53)).frame(width: 3, height: 3).offset(y: 21) }
                        }
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(action == .trash ? Color(red: 1, green: 0.45, blue: 0.43) : active ? Color(red: 1, green: 0.85, blue: 0.53) : Color(white: 0.85))
                        .frame(width: 36, height: 34)
                    }
                    .buttonStyle(.plain).focused($focused, equals: action)
                    .disabled(actions.inFlight.contains(action))
                    .onHover { hovered = $0 ? action : nil }
                    .accessibilityLabel(label(action))
                    .accessibilityValue(actions.inFlight.contains(action) ? "In progress" : action != .trash ? (active ? "On" : "Off") : "")
                    .help(label(action))
                }
            } }
            Text(hovered.map(label) ?? focused.map(label) ?? (actions.inFlight.isEmpty ? "Quick actions" : "Working…"))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            if let error = actions.error {
                ScrollView {
                    Text(error.message).font(.system(size: 12)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if let recovery = error.recovery {
                        Button("Open Settings") { NSWorkspace.shared.open(recovery.settingsURL) }
                    }
                    Button("Dismiss", action: dismissError).keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(.horizontal, 13).padding(.top, 8).padding(.bottom, 6)
        .frame(width: actions.error == nil ? 150 : 320, height: actions.error == nil ? 70 : 280, alignment: .top)
        .glassEffect(.clear.interactive(), in: panel)
        .background(panel.fill(dim))
        .overlay(panel.strokeBorder(panelRim, lineWidth: 1))
        .colorScheme(.dark)
    }
}
