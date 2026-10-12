import SwiftUI

struct RootView: View {
    @State private var tab: AppTab = .tracks
    @State private var showMore = false
    @State private var barHeight: CGFloat = 0
    @State private var library = LibraryStore()
    @State private var player = PlayerStore()
    @State private var lyrics = LyricsStore()
    @State private var toasts = ToastCenter()

    var body: some View {
        GeometryReader { proxy in
            let scale = Scale.forWidth(proxy.size.width)
            ZStack {
                Palette.bg.ignoresSafeArea()
                FlowFieldView()
                    .ignoresSafeArea()
                page
                    .id(tab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity
                    ))
                    .zIndex(1)
                chrome(scale: scale)
                    .zIndex(30)
                if showMore {
                    MoreSheet(isPresented: $showMore) { item in
                        toasts.show(item == .login ? "Вход через SSO скоро будет" : "\(item.title) скоро будет")
                    }
                    .zIndex(61)
                }
                if player.isFullPlayerOpen {
                    FullPlayerView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(70)
                }
                if player.isQueueOpen {
                    QueueSheet()
                        .zIndex(75)
                }
                if let track = library.menuTrack {
                    TrackMenuSheet(track: track)
                        .zIndex(80)
                }
                ToastHost()
                    .zIndex(90)
            }
            .environment(\.s, scale)
            .environment(\.bottomInset, barHeight)
            .environment(\.openTab, { target in
                withAnimation(Motion.page) {
                    tab = target
                }
            })
            .environment(library)
            .environment(player)
            .environment(lyrics)
            .environment(toasts)
        }
        .animation(Motion.page, value: tab)
        .onAppear(perform: bootstrap)
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .tracks: LibraryView()
        case .playlists: PlaylistsView()
        case .favorites: FavoritesView()
        case .importer: ImportView()
        }
    }

    private func chrome(scale: Scale) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: scale(8)) {
                MiniPlayer()
                BottomBar(tab: $tab, moreActive: showMore) {
                    withAnimation(Motion.expoOut(0.32)) {
                        showMore.toggle()
                    }
                }
            }
            .background(
                GeometryReader { inner in
                    Color.clear.preference(key: BarHeightKey.self, value: inner.size.height)
                }
            )
        }
        .onPreferenceChange(BarHeightKey.self) { value in
            barHeight = value
        }
    }

    private func bootstrap() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-nsm-demo") {
            let engine = DemoEngine()
            player.attach(engine)
            library.tracks = DemoData.tracks()
            if let routeIndex = arguments.firstIndex(of: "-nsm-route"), routeIndex + 1 < arguments.count {
                switch arguments[routeIndex + 1] {
                case "playlists": tab = .playlists
                case "favorites": tab = .favorites
                case "import": tab = .importer
                case "list": library.changeViewMode(.list)
                case "more": showMore = true
                case "player", "lyrics", "queue":
                    if let first = library.tracks.first {
                        player.play(first, in: library.tracks)
                        player.isFullPlayerOpen = true
                        player.isQueueOpen = arguments[routeIndex + 1] == "queue"
                    }
                default: break
                }
            }
            if arguments.contains("-nsm-playing"), let track = library.tracks.dropFirst(2).first {
                player.play(track, in: library.tracks)
            }
            if let seekIndex = arguments.firstIndex(of: "-nsm-seek"),
               seekIndex + 1 < arguments.count,
               let seconds = Double(arguments[seekIndex + 1]) {
                player.seek(to: seconds)
            }
        }
    }
}
