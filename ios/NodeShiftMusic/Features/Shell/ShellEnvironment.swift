import SwiftUI

enum AppOverlay: Hashable {
    case storage
    case settings
    case wishlist
    case together
    case playlist(String)
    case sitePlaylist(String)
}

private struct OpenTabKey: EnvironmentKey {
    static let defaultValue: (AppTab) -> Void = { _ in }
}

extension EnvironmentValues {
    var openTab: (AppTab) -> Void {
        get { self[OpenTabKey.self] }
        set { self[OpenTabKey.self] = newValue }
    }
}

private struct OpenStorageKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openStorage: () -> Void {
        get { self[OpenStorageKey.self] }
        set { self[OpenStorageKey.self] = newValue }
    }
}

private struct OpenOverlayKey: EnvironmentKey {
    static let defaultValue: (AppOverlay) -> Void = { _ in }
}

extension EnvironmentValues {
    var openOverlay: (AppOverlay) -> Void {
        get { self[OpenOverlayKey.self] }
        set { self[OpenOverlayKey.self] = newValue }
    }
}

struct BackButton: View {
    var title = "Назад"
    var action: () -> Void
    @Environment(\.s) private var s

    var body: some View {
        Button(action: action) {
            HStack(spacing: s(6)) {
                Icon(name: .chevronLeft, size: s(18), stroke: 2)
                Text(title)
                    .font(.nsm(.interMedium, s(13.5)))
            }
            .foregroundStyle(Palette.muted)
            .padding(.bottom, s(14))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.6))
    }
}
