import SwiftUI

/// Reuses the MIT app's existing provider marks in the companion's native status item.
public enum RunwayProviderArtwork {
    @MainActor public static func path(for provider: String, in rect: CGRect) -> CGPath? {
        guard let mark = ProviderMarks.mark(for: provider) else { return nil }
        return ProviderIconShape(mark: mark, inset: 0).path(in: rect).cgPath
    }
}
