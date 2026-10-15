import SwiftUI

struct RootView: View {
    @State private var tab: AppTab = .tracks
    @State private var showMore = false
    @State private var barHeight: CGFloat = 0
    @State private var overlay: AppOverlay?
    @State private var model = AppModel(demo: AppModel.launchDemo)

    var body: some View {
        let library = model.library
        let player = model.player
        GeometryReader { proxy in
            let scale = Scale.forWidth(proxy.size.width)
            ZStack {
                Palette.bg.ignoresSafeArea()
                FlowFieldView()
                    .ignoresSafeArea()
                page
                    .simultaneousGesture(tabSwipe)
                    .id(tab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity
                    ))
                    .zIndex(1)
                chrome(scale: scale)
                    .zIndex(30)
                if showMore {
                    MoreSheet(
                        isPresented: $showMore,
                        loggedIn: model.site.isLoggedIn,
                        loginTitle: model.site.isLoggedIn ? "Выйти (\(model.site.user?.handle.map { "@" + $0 } ?? "аккаунт"))" : "Войти",
                        versionLine: "Версия \(model.updates.currentVersion) (\(model.updates.currentBuild))"
                    ) { item in
                        select(item)
                    }
                    .zIndex(61)
                }
                if let overlay {
                    overlayView(overlay)
                        .transition(.move(edge: .trailing))
                        .zIndex(65)
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
                if overlay == .together {
                    TogetherView {
                        withAnimation(Motion.expoOut(0.32)) {
                            overlay = nil
                        }
                    }
                    .transition(.move(edge: .bottom))
                    .zIndex(78)
                }
                if let track = library.menuTrack {
                    TrackMenuSheet(track: track)
                        .zIndex(80)
                }
                if let track = library.playlistTrack {
                    PlaylistPickerSheet(track: track)
                        .zIndex(81)
                }
                if let track = library.editTrack {
                    TrackEditSheet(track: track)
                        .zIndex(82)
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
            .environment(\.openStorage, {
                withAnimation(Motion.expoOut(0.32)) {
                    overlay = .storage
                }
            })
            .environment(\.openOverlay, { target in
                withAnimation(Motion.expoOut(0.32)) {
                    overlay = target
                }
            })
            .environment(library)
            .environment(player)
            .environment(model.lyrics)
            .environment(model.toasts)
            .environment(model.importer)
            .environment(model.site)
            .environment(model.sync)
            .environment(model.catalog)
            .environment(model.updates)
            .environment(model.room)
            .environment(model.enrichment)
            .confirmationDialog(
                "Удалить трек с телефона?",
                isPresented: Binding(
                    get: { library.deleteCandidate != nil },
                    set: { if !$0 { library.deleteCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    if let track = library.deleteCandidate {
                        player.queue.removeAll { $0.id == track.id }
                        library.delete(track)
                        model.toasts.show("Трек удалён")
                    }
                    library.deleteCandidate = nil
                }
                Button("Отмена", role: .cancel) {
                    library.deleteCandidate = nil
                }
            } message: {
                Text(library.deleteCandidate.map { "«\($0.title)» исчезнет с телефона." } ?? "")
            }
        }
        .animation(Motion.page, value: tab)
        .onAppear(perform: bootstrap)
        .onOpenURL { url in
            handleOpen(url)
        }
    }

    @ViewBuilder
    private func overlayView(_ target: AppOverlay) -> some View {
        let close = {
            withAnimation(Motion.expoOut(0.32)) {
                overlay = nil
            }
        }
        switch target {
        case .storage:
            StorageView(onClose: close)
        case .settings:
            SettingsView(onClose: close)
        case .wishlist:
            WishlistView(onClose: close)
        case let .playlist(id):
            PlaylistDetailView(playlistID: id, onClose: close)
        case .sitePlaylist, .together:
            Color.clear
        }
    }

    private func handleOpen(_ url: URL) {
        if url.isFileURL {
            model.importer.add(urls: [url])
            model.toasts.show("Добавляем в библиотеку")
            withAnimation(Motion.page) {
                tab = .importer
            }
            return
        }
        if let code = RoomStore.normalize(url.absoluteString), url.absoluteString.contains("room") {
            Task {
                _ = await model.room.joinChecked(code: code, name: nil)
                withAnimation(Motion.expoOut(0.32)) {
                    overlay = .together
                }
            }
        }
    }

    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 90, abs(dx) > abs(dy) * 1.6 else { return }
                let tabs = AppTab.allCases
                guard let index = tabs.firstIndex(of: tab) else { return }
                let next = dx < 0 ? index + 1 : index - 1
                guard tabs.indices.contains(next) else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(Motion.page) {
                    tab = tabs[next]
                }
            }
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

    private func select(_ item: MoreSheet.MoreItem) {
        switch item {
        case .storage:
            withAnimation(Motion.expoOut(0.32)) {
                overlay = .storage
            }
        case .settings:
            withAnimation(Motion.expoOut(0.32)) {
                overlay = .settings
            }
        case .wishlist:
            withAnimation(Motion.expoOut(0.32)) {
                overlay = .wishlist
            }
        case .together:
            withAnimation(Motion.expoOut(0.32)) {
                overlay = .together
            }
        case .login:
            if model.site.isLoggedIn {
                model.site.logout()
            } else {
                Task { _ = await model.site.login() }
            }
        }
    }

    private func bootstrap() {
        guard model.demo else { return }
        let arguments = ProcessInfo.processInfo.arguments
        let library = model.library
        let player = model.player
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let sorted = library.tracks.sorted { $0.id < $1.id }
            if let routeIndex = arguments.firstIndex(of: "-nsm-route"), routeIndex + 1 < arguments.count {
                switch arguments[routeIndex + 1] {
                case "playlists": tab = .playlists
                case "favorites": tab = .favorites
                case "import": tab = .importer
                case "list": library.changeViewMode(.list)
                case "more": showMore = true
                case "storage": overlay = .storage
                case "player", "lyrics", "queue":
                    if let first = sorted.first {
                        player.play(first, in: sorted)
                        player.isFullPlayerOpen = true
                        player.isQueueOpen = arguments[routeIndex + 1] == "queue"
                    }
                default: break
                }
            }
            if arguments.contains("-nsm-playing"), let track = sorted.dropFirst(2).first {
                player.play(track, in: sorted)
            }
            if let seekIndex = arguments.firstIndex(of: "-nsm-seek"),
               seekIndex + 1 < arguments.count,
               let seconds = Double(arguments[seekIndex + 1]) {
                player.seek(to: seconds)
            }
        }
    }
}
