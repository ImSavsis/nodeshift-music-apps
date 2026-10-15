import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case tracks
    case playlists
    case favorites
    case importer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tracks: return "Треки"
        case .playlists: return "Плейлисты"
        case .favorites: return "Избранное"
        case .importer: return "Импорт"
        }
    }

    var icon: LucideName {
        switch self {
        case .tracks: return .music2
        case .playlists: return .listMusic
        case .favorites: return .heart
        case .importer: return .upload
        }
    }
}

private struct BottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var bottomInset: CGFloat {
        get { self[BottomInsetKey.self] }
        set { self[BottomInsetKey.self] = newValue }
    }
}

struct BarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.bottomInset) private var bottomInset
    @Environment(\.s) private var s

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, s(16))
            .padding(.top, s(22))
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, bottomInset + s(24), for: .scrollContent)
    }
}

struct BottomBar: View {
    @Binding var tab: AppTab
    var moreActive: Bool
    var onMore: () -> Void
    @Environment(\.s) private var s
    @State private var holdIndex: Int?
    @State private var barWidth: CGFloat = 0
    @Namespace private var highlight

    private var itemCount: Int {
        AppTab.allCases.count + 1
    }

    var body: some View {
        let glass = glassActive
        row
            .padding(.horizontal, s(8))
            .padding(.top, s(6))
            .padding(.bottom, s(4))
            .background(alignment: .top) {
                if !glass {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Palette.bg.opacity(0.55)
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(Palette.line2).frame(height: 1)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .glassSurface(Capsule(), interactive: true)
            .padding(.horizontal, glass ? s(14) : 0)
    }

    private var row: some View {
        HStack(spacing: s(2)) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element.id) { index, item in
                barItem(icon: item.icon, title: item.title, active: tab == item && !moreActive, hovered: holdIndex == index) {
                    withAnimation(Motion.bar) {
                        tab = item
                    }
                }
            }
            barItem(icon: .ellipsis, title: "Ещё", active: moreActive, hovered: holdIndex == AppTab.allCases.count, action: onMore)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        barWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        barWidth = width
                    }
            }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case let .second(true, drag?) = value {
                        let raw = Int(drag.location.x / max(barWidth, 1) * CGFloat(itemCount))
                        let index = min(itemCount - 1, max(0, raw))
                        if holdIndex != index {
                            holdIndex = index
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .onEnded { _ in
                    if let index = holdIndex {
                        withAnimation(Motion.bar) {
                            if index < AppTab.allCases.count {
                                tab = AppTab.allCases[index]
                            } else {
                                onMore()
                            }
                        }
                    }
                    holdIndex = nil
                }
        )
    }

    private func barItem(icon: LucideName, title: String, active: Bool, hovered: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: s(3)) {
                Icon(name: icon, size: s(18), stroke: 1.6)
                Text(title)
                    .font(.nsm(.interMedium, s(10)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(active || hovered ? Palette.accent : Palette.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, s(7))
            .padding(.horizontal, s(2))
            .background {
                if active {
                    highlightShape
                } else if hovered {
                    RoundedRectangle(cornerRadius: s(Radius.nav), style: .continuous).fill(Palette.surface2)
                }
            }
            .scaleEffect(hovered ? 1.14 : 1)
            .animation(Motion.spring, value: hovered)
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.7))
        .animation(Motion.bar, value: active)
    }

    private var highlightShape: some View {
        let shape = RoundedRectangle(cornerRadius: s(Radius.nav), style: .continuous)
        return Color.clear
            .glassSurface(shape, interactive: true, tint: Palette.accent.opacity(0.22), fallback: Palette.surface2, stroke: true)
            .overlay {
                if !glassActive {
                    Color.clear.edgeRim(s(Radius.nav))
                }
            }
            .matchedGeometryEffect(id: "bar-highlight", in: highlight)
    }
}

struct MiniPlayer: View {
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.s) private var s

    var body: some View {
        if let track = player.current {
            HStack(spacing: s(12)) {
                Button {
                    withAnimation(Motion.expoOut(0.38)) {
                        player.isFullPlayerOpen = true
                    }
                } label: {
                    HStack(spacing: s(12)) {
                        CoverArt(coverName: track.coverName, live: false, maxPixel: 200)
                            .frame(width: s(44), height: s(44))
                        VStack(alignment: .leading, spacing: s(2)) {
                            Text(track.title)
                                .font(.nsm(.interMedium, s(14)))
                                .foregroundStyle(Palette.white)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.nsm(.monoRegular, s(11)))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(pressedOpacity: 0.8))
                Button {
                    player.togglePlay()
                } label: {
                    PlayCircle(size: 44, playing: player.isPlaying, iconSize: 18)
                }
                .buttonStyle(PressStyle(pressedOpacity: 0.9))
                .tapFeedback(player.isPlaying)
                Button {
                    player.next()
                } label: {
                    Icon(name: .skipForward, size: s(18), stroke: 2, filled: true)
                        .foregroundStyle(Palette.white)
                        .frame(width: s(36), height: s(36))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(pressedOpacity: 0.6))
            }
            .padding(.horizontal, s(8))
            .padding(.vertical, s(8))
            .background(glassActive ? Color.clear : Palette.playerBar)
            .background {
                if !glassActive {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .glassSurface(RoundedRectangle(cornerRadius: s(Radius.card), style: .continuous), interactive: true)
            .overlay(alignment: .top) {
                TimelineView(.animation(minimumInterval: 0.25, paused: !player.isPlaying)) { context in
                    let total = player.duration
                    let fraction = total > 0 ? min(1, player.time(at: context.date) / total) : 0
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * fraction, height: 2)
                    }
                    .frame(height: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: s(Radius.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: s(Radius.card), style: .continuous)
                    .strokeBorder(Palette.line2, lineWidth: 1)
            )
            .floatShadow()
            .padding(.horizontal, s(8))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct MoreSheet: View {
    @Binding var isPresented: Bool
    var loggedIn = false
    var loginTitle = "Войти"
    var versionLine = ""
    var onSelect: (MoreItem) -> Void
    @Environment(\.s) private var s

    enum MoreItem: String, Identifiable {
        case wishlist
        case storage
        case together
        case settings
        case login

        var id: String { rawValue }

        var title: String {
            switch self {
            case .wishlist: return "Вишлист"
            case .storage: return "Хранилище"
            case .together: return "Слушать вместе"
            case .settings: return "Настройки"
            case .login: return "Войти"
            }
        }

        var icon: LucideName {
            switch self {
            case .wishlist: return .bookmark
            case .storage: return .hardDrive
            case .together: return .users
            case .settings: return .settings
            case .login: return .logIn
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: s(4)) {
                Capsule()
                    .fill(Palette.line2)
                    .frame(width: s(36), height: s(4))
                    .padding(.top, s(10))
                    .padding(.bottom, s(8))
                ForEach([MoreItem.wishlist, .storage, .together, .settings, .login]) { item in
                    Button {
                        dismiss()
                        onSelect(item)
                    } label: {
                        HStack(spacing: s(12)) {
                            Icon(name: item == .login && loggedIn ? .logOut : item.icon, size: s(18), stroke: 1.6)
                                .foregroundStyle(Palette.muted)
                            Text(item == .login ? loginTitle : item.title)
                                .font(.nsm(.interMedium, s(14)))
                                .foregroundStyle(Palette.white)
                            Spacer()
                        }
                        .padding(.horizontal, s(14))
                        .frame(height: s(48))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(pressedOpacity: 0.6))
                }
                VStack(spacing: s(4)) {
                    if !versionLine.isEmpty {
                        Text(versionLine)
                            .font(.nsm(.monoRegular, s(11)))
                            .foregroundStyle(Palette.dim)
                    }
                    Text("made by savsis with <3")
                        .font(.nsm(.monoRegular, s(11)))
                        .foregroundStyle(Palette.dim)
                }
                .padding(.top, s(10))
                .padding(.bottom, s(14))
            }
            .padding(.horizontal, s(12))
            .padding(.bottom, s(8))
            .frame(maxWidth: .infinity)
            .background(glassActive ? Color.clear : Palette.sheet)
            .background {
                if !glassActive {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .glassSurface(UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card)))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card)))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card))
                    .strokeBorder(Palette.line2, lineWidth: 1)
            }
            .transition(.move(edge: .bottom))
        }
    }

    private func dismiss() {
        withAnimation(Motion.expoOut(0.32)) {
            isPresented = false
        }
    }
}
