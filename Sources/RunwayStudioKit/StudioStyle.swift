import SwiftUI

enum StudioStyle {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.065)
    static let panel = Color(red: 0.065, green: 0.08, blue: 0.105)
    static let muted = Color(red: 0.59, green: 0.65, blue: 0.73)
    static let mint = Color(red: 0.39, green: 0.94, blue: 0.75)
    static let violet = Color(red: 0.68, green: 0.59, blue: 1)
    static func accent(_ snapshot: StudioSnapshot) -> Color { snapshot.family == "claude" ? mint : violet }
    static func status(_ state: StudioPace.State) -> Color {
        switch state {
        case .ahead, .available: return mint
        case .steady: return .cyan
        case .tight: return .orange
        case .exhausted: return .red
        case .pending, .stale: return muted
        }
    }
}

extension View {
    func studioPanel() -> some View {
        self.padding(22)
            .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.07)))
    }
}
