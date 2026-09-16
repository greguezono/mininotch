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
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
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
                            RoundedRectangle(cornerRadius: 10).fill(active ? Color(red: 0.22, green: 0.21, blue: 0.18) : Color(white: 0.19))
                            RoundedRectangle(cornerRadius: 10).stroke(contrast == .increased || focused == action ? Color.white : Color.white.opacity(0.1), lineWidth: 1)
                            if actions.inFlight.contains(action) { ProgressView().controlSize(.small) }
                            else { Image(systemName: action == .hidden ? "doc.text.magnifyingglass" : action == .sleep ? "cup.and.saucer" : "trash").font(.system(size: 18, weight: .regular)) }
                            if active { Circle().fill(Color(red: 1, green: 0.85, blue: 0.53)).frame(width: 3, height: 3).offset(y: 21) }
                        }
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
            }
            Text(hovered.map(label) ?? focused.map(label) ?? (actions.inFlight.isEmpty ? "Quick actions" : "Working…"))
                .font(.system(size: 10)).foregroundStyle(Color(white: 0.8)).lineLimit(1)
            if let error = actions.error {
                ScrollView {
                    Text(error).font(.system(size: 12)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                Button("Dismiss", action: dismissError).keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 13).padding(.top, 8).padding(.bottom, 6)
        .frame(width: actions.error == nil ? 150 : 320, height: actions.error == nil ? 70 : 280, alignment: .top)
        .background(Color(red: 0.067, green: 0.067, blue: 0.075))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .colorScheme(.dark)
    }
}
