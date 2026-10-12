import SwiftUI

struct UpdateBanner: View {
    @Environment(UpdateChecker.self) private var updates
    @Environment(\.s) private var s

    var body: some View {
        if let manifest = updates.available {
            HStack(spacing: s(12)) {
                Icon(name: .download, size: s(20), stroke: 1.8)
                    .foregroundStyle(Palette.white)
                VStack(alignment: .leading, spacing: s(2)) {
                    Text("Доступна версия \(manifest.version)")
                        .font(.nsm(.interMedium, s(14)))
                        .foregroundStyle(Palette.white)
                    Text("сборка \(manifest.build)")
                        .font(.nsm(.monoRegular, s(11)))
                        .foregroundStyle(Palette.dim)
                }
                Spacer(minLength: 0)
                Button {
                    updates.openDownloadPage()
                } label: {
                    Text("Скачать")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(s(14))
            .surfaceBox(s(Radius.card))
            .padding(.bottom, s(18))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct DownloadRow: View {
    let title: String
    let state: SiteSync.ListState
    var action: () -> Void
    @Environment(\.s) private var s

    private var subtitle: String {
        switch state.phase {
        case .idle:
            return state.total > 0 ? "\(pluralTracks(state.total))" : "пусто"
        case .loading:
            return "Получаем список…"
        case .downloading:
            return "\(state.done) из \(state.total)"
        case .done:
            return "Скачано · \(pluralTracks(state.total))"
        case let .failed(text):
            return text
        }
    }

    var body: some View {
        HStack(spacing: s(12)) {
            VStack(alignment: .leading, spacing: s(3)) {
                Text(title)
                    .font(.nsm(.interMedium, s(14)))
                    .foregroundStyle(Palette.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.nsm(.monoRegular, s(11)))
                    .foregroundStyle(state.phase == .done ? Palette.ok : Palette.dim)
                    .lineLimit(1)
                if state.phase == .downloading, state.total > 0 {
                    ProgressView(value: Double(state.done), total: Double(state.total))
                        .tint(Palette.white)
                        .padding(.top, s(2))
                }
            }
            Spacer(minLength: 0)
            switch state.phase {
            case .loading, .downloading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Palette.white)
            case .done:
                Button(action: action) {
                    ButtonLabel(title: "Обновить", icon: .refreshCw)
                }
                .buttonStyle(GhostButtonStyle())
            default:
                Button(action: action) {
                    ButtonLabel(title: "Скачать", icon: .download)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(state.total == 0)
            }
        }
        .padding(.vertical, s(10))
    }
}

struct StorageView: View {
    var onClose: () -> Void
    @Environment(SiteSession.self) private var site
    @Environment(SiteSync.self) private var sync
    @Environment(LibraryStore.self) private var library
    @Environment(\.s) private var s

    private var usedBytes: Int64 {
        library.tracks.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScreenScroll {
                Button(action: onClose) {
                    HStack(spacing: s(6)) {
                        Icon(name: .chevronLeft, size: s(18), stroke: 2)
                        Text("Назад")
                            .font(.nsm(.interMedium, s(13.5)))
                    }
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, s(14))
                }
                .buttonStyle(PressStyle(pressedOpacity: 0.6))
                PageHeader(title: "Хранилище", subtitle: "Что лежит на телефоне и что можно скачать с сайта")
                    .reveal(0)
                accountCard.reveal(1)
                if site.isLoggedIn {
                    downloadsCard.reveal(2)
                }
                qualityCard.reveal(3)
                phoneCard.reveal(4)
            }
        }
        .task {
            if site.isLoggedIn {
                await sync.refresh()
            }
        }
        .onChange(of: site.isLoggedIn) { _, loggedIn in
            if loggedIn {
                Task { await sync.refresh() }
            }
        }
    }

    private var accountCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(12)) {
                Eyebrow(text: "Аккаунт NodeShift", bottom: 0)
                if let user = site.user {
                    Text(user.handle.map { "@\($0)" } ?? user.username ?? "Вы вошли")
                        .font(.nsm(.unboundedSemibold, s(16)))
                        .foregroundStyle(Palette.white)
                    Text("Плейлисты и лайки с сайта можно скачать на телефон.")
                        .font(.nsm(.interRegular, s(13)))
                        .foregroundStyle(Palette.muted)
                    Button {
                        site.logout()
                    } label: {
                        ButtonLabel(title: "Выйти", icon: .logOut)
                    }
                    .buttonStyle(GhostButtonStyle())
                } else {
                    Text("Войди через NodeShift SSO, чтобы скачать свои плейлисты и лайки с music.nodeshift.space.")
                        .font(.nsm(.interRegular, s(13.5)))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { _ = await site.login() }
                    } label: {
                        ButtonLabel(title: site.isBusy ? "Открываем…" : "Войти", icon: .logIn)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(site.isBusy)
                    if let error = site.lastError {
                        Text(error)
                            .font(.nsm(.interRegular, s(12.5)))
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
        }
        .padding(.bottom, s(14))
    }

    private var downloadsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(4)) {
                Eyebrow(text: "Скачать с сайта", bottom: 6)
                DownloadRow(title: "Понравившиеся", state: sync.favorites) {
                    Task { await sync.downloadFavorites() }
                }
                if !sync.playlists.isEmpty {
                    Rectangle().fill(Palette.line).frame(height: 1)
                    ForEach(sync.playlists) { playlist in
                        DownloadRow(title: playlist.name, state: playlist) {
                            Task { await sync.downloadPlaylist(playlist.id) }
                        }
                        if playlist.id != sync.playlists.last?.id {
                            Rectangle().fill(Palette.line).frame(height: 1)
                        }
                    }
                }
                if sync.needsLogin {
                    Text("Сессия устарела. Войди ещё раз.")
                        .font(.nsm(.interRegular, s(12.5)))
                        .foregroundStyle(Palette.warn)
                        .padding(.top, s(6))
                }
                Button {
                    Task { await sync.refresh() }
                } label: {
                    ButtonLabel(title: sync.isRefreshing ? "Обновляем…" : "Обновить список", icon: .refreshCw)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(sync.isRefreshing)
                .padding(.top, s(10))
            }
        }
        .padding(.bottom, s(14))
    }

    private var qualityCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(10)) {
                Eyebrow(text: "Качество при скачивании", bottom: 0)
                FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                    Chip(title: "Без потерь", active: sync.lossless) {
                        sync.setLossless(true)
                    }
                    Chip(title: "Быстро (AAC)", active: !sync.lossless) {
                        sync.setLossless(false)
                    }
                }
                Text(sync.lossless
                     ? "Оригинальные файлы как загружены (FLAC и т.д.): точнее, но тяжелее."
                     : "AAC 192 кбит/с для FLAC и WAV: стартует сразу и весит в 5–6 раз меньше.")
                    .font(.nsm(.interRegular, s(12.5)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, s(14))
    }

    private var phoneCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(6)) {
                Eyebrow(text: "На телефоне", bottom: 4)
                Text("\(pluralTracks(library.tracks.count)) · \(formatBytes(usedBytes))")
                    .font(.nsm(.interMedium, s(14)))
                    .foregroundStyle(Palette.white)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f ГБ", gb)
        }
        return String(format: "%.0f МБ", Double(bytes) / 1_048_576)
    }
}
