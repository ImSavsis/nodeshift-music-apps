import PhotosUI
import SwiftUI

struct WishlistView: View {
    var onClose: () -> Void
    @Environment(SiteSession.self) private var site
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlayerStore.self) private var player
    @Environment(\.s) private var s
    @State private var tracks: [TrackRecord] = []
    @State private var loading = false

    private var visible: [TrackRecord] {
        tracks.filter { catalog.wishlistIDs.contains($0.siteId ?? "") }
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScreenScroll {
                BackButton(action: onClose)
                PageHeader(title: "Вишлист", subtitle: "Треки сайта, которые ты хочешь послушать позже")
                    .reveal(0)
                if !site.isLoggedIn {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: s(12)) {
                            Text("Войди через сайт, чтобы пользоваться вишлистом.")
                                .font(.nsm(.interRegular, s(13.5)))
                                .foregroundStyle(Palette.muted)
                            Button {
                                Task { _ = await site.login() }
                            } label: {
                                ButtonLabel(title: "Войти", icon: .logIn)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                } else if loading && tracks.isEmpty {
                    ProgressView().tint(Palette.white).frame(maxWidth: .infinity).padding(.vertical, s(40))
                } else if visible.isEmpty {
                    Text("Пока пусто. Нажми «В вишлист» в меню любого трека.")
                        .font(.nsm(.interRegular, s(14)))
                        .foregroundStyle(Palette.dim)
                } else {
                    HStack(spacing: s(10)) {
                        Button {
                            if let first = visible.first {
                                player.shuffle = false
                                player.play(first, in: visible)
                            }
                        } label: {
                            ButtonLabel(title: "Слушать", icon: .play)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button {
                            let shuffled = visible.shuffled()
                            if let first = shuffled.first {
                                player.shuffle = true
                                player.play(first, in: shuffled)
                            }
                        } label: {
                            ButtonLabel(title: "Перемешать", icon: .shuffle)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    .padding(.bottom, s(20))
                    LazyVStack(spacing: s(4)) {
                        ForEach(visible) { track in
                            TrackRow(track: track, queue: visible, showsDownloaded: true)
                        }
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard site.isLoggedIn else { return }
        loading = true
        defer { loading = false }
        await catalog.refreshLikes()
        if let list = try? await SiteAPI.shared.wishlist() {
            tracks = list.map { catalog.record(for: $0) }
        }
    }
}

struct PlaylistDetailView: View {
    let playlistID: String
    var onClose: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.s) private var s
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    private var playlist: PlaylistRecord? {
        library.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            if let playlist {
                let tracks = library.tracks(in: playlist)
                ScreenScroll {
                    BackButton(action: onClose)
                    HStack(alignment: .bottom, spacing: s(16)) {
                        let lead = tracks.first(where: { $0.coverName != nil })
                        CoverArt(
                            coverName: playlist.coverName ?? lead?.coverName,
                            motionName: playlist.coverName == nil ? lead?.motionName : nil
                        )
                        .frame(width: s(120), height: s(120))
                        VStack(alignment: .leading, spacing: s(4)) {
                            Text(playlist.name)
                                .font(.nsm(.unboundedSemibold, s(20)))
                                .foregroundStyle(Palette.white)
                                .lineLimit(3)
                            Text(pluralTracks(tracks.count))
                                .font(.nsm(.monoRegular, s(12)))
                                .foregroundStyle(Palette.dim)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, s(20))
                    HStack(spacing: s(10)) {
                        Button {
                            if let first = tracks.first {
                                player.shuffle = false
                                player.play(first, in: tracks)
                            }
                        } label: {
                            ButtonLabel(title: "Слушать", icon: .play)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(tracks.isEmpty)
                        Button {
                            let shuffled = tracks.shuffled()
                            if let first = shuffled.first {
                                player.shuffle = true
                                player.play(first, in: shuffled)
                            }
                        } label: {
                            ButtonLabel(title: "Перемешать", icon: .shuffle)
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(tracks.isEmpty)
                        IconToggle(icon: .pencil, size: 40, iconSize: 18) {
                            newName = playlist.name
                            renaming = true
                        }
                        IconToggle(icon: .trash2, size: 40, iconSize: 18, tint: Palette.danger) {
                            confirmDelete = true
                        }
                    }
                    .padding(.bottom, s(20))
                    if tracks.isEmpty {
                        Text("В плейлисте пока нет треков. Добавляй их через меню трека.")
                            .font(.nsm(.interRegular, s(14)))
                            .foregroundStyle(Palette.dim)
                    } else {
                        LazyVStack(spacing: s(4)) {
                            ForEach(tracks) { track in
                                HStack(spacing: 0) {
                                    TrackRow(track: track, queue: tracks)
                                    IconToggle(icon: .x, size: 32, iconSize: 15) {
                                        withAnimation(Motion.expoOut(0.25)) {
                                            library.removeFromPlaylist(playlist, trackID: track.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .alert("Название плейлиста", isPresented: $renaming) {
                    TextField("Название", text: $newName)
                    Button("Сохранить") {
                        library.renamePlaylist(playlist, name: newName)
                    }
                    Button("Отмена", role: .cancel) {}
                }
                .confirmationDialog("Удалить плейлист «\(playlist.name)»? Треки останутся на телефоне.", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) {
                        library.deletePlaylist(playlist)
                        onClose()
                    }
                    Button("Отмена", role: .cancel) {}
                }
            } else {
                Color.clear.onAppear(perform: onClose)
            }
        }
    }
}

struct PlaylistPickerSheet: View {
    let track: TrackRecord
    @Environment(LibraryStore.self) private var library
    @Environment(SiteSession.self) private var site
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.s) private var s
    @State private var newName = ""
    @State private var sitePlaylists: [SitePlaylist] = []
    @State private var loading = false

    private var remote: Bool {
        track.isRemote
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: s(12)) {
                Capsule()
                    .fill(Palette.line2)
                    .frame(width: s(36), height: s(4))
                    .frame(maxWidth: .infinity)
                    .padding(.top, s(10))
                Text("В плейлист")
                    .font(.nsm(.unboundedSemibold, s(16)))
                    .foregroundStyle(Palette.white)
                HStack(spacing: s(10)) {
                    TextField("", text: $newName, prompt: Text("Новый плейлист").foregroundStyle(Palette.dim))
                        .font(.nsm(.interRegular, s(14)))
                        .foregroundStyle(Palette.white)
                        .tint(Palette.white)
                        .padding(.horizontal, s(16))
                        .frame(height: s(40))
                        .background(Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
                    Button {
                        createAndAdd()
                    } label: {
                        ButtonLabel(title: "Создать")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ScrollView {
                    VStack(spacing: s(2)) {
                        if remote {
                            if !site.isLoggedIn {
                                Text("Войди через сайт, чтобы собирать плейлисты на сайте.")
                                    .font(.nsm(.interRegular, s(13)))
                                    .foregroundStyle(Palette.dim)
                            }
                            ForEach(sitePlaylists) { playlist in
                                row(playlist.name, count: playlist.trackCount ?? 0) {
                                    addToSite(playlist)
                                }
                            }
                        } else {
                            ForEach(library.playlists) { playlist in
                                row(playlist.name, count: library.tracks(in: playlist).count) {
                                    let added = library.addToPlaylist(playlist, trackID: track.id)
                                    toasts.show(added ? "Добавлено в «\(playlist.name)»" : "Уже в «\(playlist.name)»")
                                    close()
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: s(320))
            }
            .padding(.horizontal, s(18))
            .padding(.bottom, s(18))
            .frame(maxWidth: .infinity)
            .background(Palette.modal)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card)))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card))
                    .strokeBorder(Palette.line2, lineWidth: 1)
            }
            .transition(.move(edge: .bottom))
        }
        .task {
            guard remote, site.isLoggedIn else { return }
            sitePlaylists = (try? await SiteAPI.shared.playlists()) ?? []
        }
    }

    private func row(_ title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: s(12)) {
                Icon(name: .listMusic, size: s(18), stroke: 1.6)
                    .foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: s(2)) {
                    Text(title)
                        .font(.nsm(.interMedium, s(14)))
                        .foregroundStyle(Palette.white)
                        .lineLimit(1)
                    Text(pluralTracks(count))
                        .font(.nsm(.monoRegular, s(11)))
                        .foregroundStyle(Palette.dim)
                }
                Spacer()
            }
            .padding(.vertical, s(10))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.6))
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if remote {
            guard site.isLoggedIn, let siteID = track.siteId else {
                toasts.show("Войди через сайт")
                return
            }
            Task {
                do {
                    let created = try await SiteAPI.shared.createPlaylist(name: name)
                    try await SiteAPI.shared.addToPlaylist(created.id.value, trackID: siteID)
                    toasts.show("Добавлено в «\(name)»")
                    close()
                } catch {
                    toasts.show("Не получилось создать плейлист")
                }
            }
        } else if let created = library.createPlaylist(name: name, trackIDs: [track.id]) {
            toasts.show("Добавлено в «\(created.name)»")
            close()
        }
    }

    private func addToSite(_ playlist: SitePlaylist) {
        guard let siteID = track.siteId else { return }
        Task {
            do {
                try await SiteAPI.shared.addToPlaylist(playlist.id.value, trackID: siteID)
                toasts.show("Добавлено в «\(playlist.name)»")
            } catch {
                toasts.show("Не получилось добавить")
            }
            close()
        }
    }

    private func close() {
        withAnimation(Motion.expoOut(0.25)) {
            library.playlistTrack = nil
        }
    }
}

struct TrackEditSheet: View {
    let track: TrackRecord
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.s) private var s
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var year = ""
    @State private var genre = ""
    @State private var number = ""
    @State private var picked: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var saving = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: s(12)) {
                Capsule()
                    .fill(Palette.line2)
                    .frame(width: s(36), height: s(4))
                    .frame(maxWidth: .infinity)
                    .padding(.top, s(10))
                Text("Редактировать")
                    .font(.nsm(.unboundedSemibold, s(16)))
                    .foregroundStyle(Palette.white)
                ScrollView {
                    VStack(spacing: s(10)) {
                        field("Название", $title)
                        field("Исполнитель", $artist)
                        field("Альбом", $album)
                        HStack(spacing: s(10)) {
                            field("Год", $year, numeric: true)
                            field("№ трека", $number, numeric: true)
                        }
                        field("Жанр", $genre)
                        PhotosPicker(selection: $picked, matching: .images) {
                            ButtonLabel(title: coverData == nil ? "Выбрать обложку из фото" : "Обложка выбрана", icon: .imagePlus)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                .frame(maxHeight: s(380))
                HStack(spacing: s(10)) {
                    Button(action: close) {
                        ButtonLabel(title: "Отмена")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GhostButtonStyle())
                    Button(action: save) {
                        ButtonLabel(title: saving ? "Сохраняем…" : "Сохранить", icon: .check)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, s(18))
            .padding(.bottom, s(18))
            .frame(maxWidth: .infinity)
            .background(Palette.modal)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card)))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card))
                    .strokeBorder(Palette.line2, lineWidth: 1)
            }
            .transition(.move(edge: .bottom))
        }
        .onAppear {
            title = track.title
            artist = track.artist
            album = track.album ?? ""
            year = track.year.map(String.init) ?? ""
            genre = track.genre ?? ""
            number = track.trackNumber.map(String.init) ?? ""
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    coverData = ImportManager.normalizedJPEG(data)
                }
            }
        }
    }

    private func field(_ placeholder: String, _ text: Binding<String>, numeric: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Palette.dim))
            .font(.nsm(.interRegular, s(14)))
            .foregroundStyle(Palette.white)
            .tint(Palette.white)
            .keyboardType(numeric ? .numberPad : .default)
            .padding(.horizontal, s(16))
            .frame(height: s(42))
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
    }

    private func save() {
        saving = true
        var updated = track
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.album = album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : album.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.year = Int(year)
        updated.trackNumber = Int(number)
        updated.genre = genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : genre.trimmingCharacters(in: .whitespacesAndNewlines)
        var newCover: String?
        if let coverData {
            let name = "\(UUID().uuidString).jpg"
            if (try? coverData.write(to: AppPaths.coverURL(name))) != nil {
                newCover = name
                updated.coverName = name
            }
        }
        library.save(updated)
        player.updateTrack(updated)
        let tags = WriteTags(
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist,
            genre: updated.genre,
            trackNumber: updated.trackNumber,
            discNumber: updated.discNumber,
            year: updated.year,
            isrc: nil,
            cover: newCover == nil ? nil : coverData
        )
        let url = updated.fileURL
        let skip = updated.usesSystemDecoder
        Task {
            if !skip {
                _ = try? await Task.detached(priority: .userInitiated) {
                    try TagIO.write(url, tags: tags)
                }.value
            }
            toasts.show("Сохранено")
            saving = false
            close()
        }
    }

    private func close() {
        withAnimation(Motion.expoOut(0.25)) {
            library.editTrack = nil
        }
    }
}
