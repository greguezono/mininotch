import SwiftUI

struct ControlsView: View {
    @ObservedObject var actions: SystemActions
    let confirm: (SystemActions.Action) -> Void
    let dismissError: () -> Void
    @State private var hovered: SystemActions.Action?
    @FocusState private var focused: SystemActions.Action?
    @Environment(\.colorSchemeContrast) private var contrast
    private func label(_ action: SystemActions.Action) -> String {
        switch action {
        case .hidden: return actions.hiddenFiles == true ? "Hide hidden files" : "Show hidden files"
        case .sleep: return actions.sleepPrevented ? "Allow sleep" : "Prevent sleep"
        case .trash: return "Empty Trash"
        }
    }
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ForEach(SystemActions.Action.allCases, id: \.self) { action in
                    let active = action == .hidden ? actions.hiddenFiles == true : action == .sleep && actions.sleepPrevented
                    Button { if action == .sleep { actions.toggleSleep() } else { confirm(action) } } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 17).fill(active ? Color(red: 0.22, green: 0.21, blue: 0.18) : Color(white: 0.19))
                            RoundedRectangle(cornerRadius: 17).stroke(contrast == .increased || focused == action ? Color.white : Color.white.opacity(0.1), lineWidth: 1)
                            if actions.inFlight.contains(action) { ProgressView().controlSize(.small) }
                            else { Image(systemName: action == .hidden ? "doc.text.magnifyingglass" : action == .sleep ? "cup.and.saucer" : "trash").font(.system(size: 25, weight: .regular)) }
                            if active { Circle().fill(Color(red: 1, green: 0.85, blue: 0.53)).frame(width: 5, height: 5).offset(y: 39) }
                        }
                        .foregroundStyle(action == .trash ? Color(red: 1, green: 0.45, blue: 0.43) : active ? Color(red: 1, green: 0.85, blue: 0.53) : Color(white: 0.85))
                        .frame(width: 64, height: 60)
                    }
                    .buttonStyle(.plain).focused($focused, equals: action)
                    .disabled(actions.inFlight.contains(action))
                    .onHover { hovered = $0 ? action : nil }
                    .accessibilityLabel(label(action))
                    .accessibilityValue(actions.inFlight.contains(action) ? "In progress" : action == .hidden && actions.hiddenFiles == nil ? "Unknown" : action == .trash ? "" : active ? "On" : "Off")
                    .help(label(action))
                }
            }
            Text(hovered.map(label) ?? focused.map(label) ?? (actions.inFlight.isEmpty ? "Quick actions" : "Working…"))
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.8))
            if let error = actions.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Button("Dismiss", action: dismissError).keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 20).padding(.top, 19).padding(.bottom, 12).frame(width: 264)
        .background(Color(red: 0.067, green: 0.067, blue: 0.075))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26))
        .colorScheme(.dark)
    }
}
