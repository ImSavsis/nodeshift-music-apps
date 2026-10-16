import SwiftUI
import UniformTypeIdentifiers

func pluralTracks(_ count: Int) -> String {
    let mod10 = count % 10
    let mod100 = count % 100
    if mod10 == 1 && mod100 != 11 {
        return "\(count) трек"
    }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) {
        return "\(count) трека"
    }
    return "\(count) треков"
}

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.openStorage) private var openStorage
    @Environment(\.s) private var s

    var body: some View {
        let list = library.favorites
        ScreenScroll {
            PageHeader(
                title: "Избранное",
                subtitle: list.isEmpty ? "Треки, которые вы отметили" : "\(pluralTracks(list.count)), которые вы отметили"
            )
            .reveal(0)
            Button(action: openStorage) {
                ButtonLabel(title: "Скачать лайки с сайта", icon: .cloudDownload)
            }
            .buttonStyle(GhostButtonStyle())
            .padding(.bottom, s(18))
            .reveal(1)
            if list.isEmpty {
                Text("В избранном пока пусто. Нажми на сердце у любого трека.")
                    .font(.nsm(.interRegular, s(14)))
                    .foregroundStyle(Palette.dim)
                    .reveal(1)
            } else {
                HStack(spacing: s(10)) {
                    Button {
                        if let first = list.first {
                            player.shuffle = false
                            player.play(first, in: list)
                        }
                    } label: {
                        ButtonLabel(title: "Слушать", icon: .play)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        let shuffled = list.shuffled()
                        if let first = shuffled.first {
                            player.shuffle = true
                            player.play(first, in: shuffled)
                        }
                    } label: {
                        ButtonLabel(title: "Перемешать", icon: .shuffle)
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                .padding(.bottom, s(22))
                .reveal(1)
                LazyVStack(spacing: s(4)) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, queue: list)
                            .stagger(index, rise: 10, step: 0.03)
                    }
                }
            }
        }
    }
}

struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openStorage) private var openStorage
    @Environment(\.openOverlay) private var openOverlay
    @Environment(\.s) private var s
    @State private var creating = false
    @State private var newName = ""

    private var albums: [(name: String, tracks: [TrackRecord])] {
        Dictionary(grouping: library.tracks.filter { $0.album != nil }, by: { $0.album ?? "" })
            .map { entry in
                (
                    name: entry.key,
                    tracks: entry.value.sorted {
                        ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0)
                    }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: s(14), alignment: .top),
            GridItem(.flexible(), spacing: s(14), alignment: .top),
        ]
    }

    var body: some View {
        let lists = library.playlists
        let shelves = albums
        ScreenScroll {
            PageHeader(title: "Плейлисты", subtitle: "Ваши подборки")
                .reveal(0)
            Button(action: openStorage) {
                ButtonLabel(title: "Скачать плейлисты с сайта", icon: .cloudDownload)
            }
            .buttonStyle(GhostButtonStyle())
            .padding(.bottom, s(22))
            .reveal(1)
            LazyVGrid(columns: columns, spacing: s(24)) {
                Button {
                    newName = ""
                    creating = true
                } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            VStack(spacing: s(10)) {
                                Icon(name: .plus, size: s(24), stroke: 1.6)
                                Text("Новый плейлист")
                                    .font(.nsm(.interMedium, s(13.5)))
                            }
                            .foregroundStyle(Palette.muted)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: s(Radius.tile), style: .continuous)
                                .strokeBorder(Palette.line2, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                        )
                }
                .buttonStyle(PressStyle(pressedOpacity: 0.7))
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, playlist in
                    let tracks = library.tracks(in: playlist)
                    Button {
                        openOverlay(.playlist(playlist.id))
                    } label: {
                        VStack(alignment: .leading, spacing: s(12)) {
                            let lead = tracks.first(where: { $0.coverName != nil })
                            CoverArt(
                                coverName: playlist.coverName ?? lead?.coverName,
                                motionName: playlist.coverName == nil ? lead?.motionName : nil
                            )
                            VStack(alignment: .leading, spacing: s(2)) {
                                Text(playlist.name)
                                    .font(.nsm(.interMedium, s(14)))
                                    .foregroundStyle(Palette.white)
                                    .lineLimit(1)
                                Text(pluralTracks(tracks.count))
                                    .font(.nsm(.monoRegular, s(11)))
                                    .foregroundStyle(Palette.dim)
                            }
                        }
                    }
                    .buttonStyle(PressStyle(pressedOpacity: 0.9))
                    .stagger(index + 1, rise: 16, step: 0.05)
                }
            }
            if !shelves.isEmpty {
                Eyebrow(text: "Альбомы")
                    .padding(.top, s(30))
                LazyVGrid(columns: columns, spacing: s(24)) {
                    ForEach(Array(shelves.enumerated()), id: \.element.name) { index, album in
                        Button {
                            if let first = album.tracks.first {
                                player.shuffle = false
                                player.play(first, in: album.tracks)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: s(12)) {
                                let lead = album.tracks.first(where: { $0.coverName != nil })
                                CoverArt(coverName: lead?.coverName, motionName: lead?.motionName)
                                VStack(alignment: .leading, spacing: s(2)) {
                                    Text(album.name)
                                        .font(.nsm(.interMedium, s(14)))
                                        .foregroundStyle(Palette.white)
                                        .lineLimit(1)
                                    Text(pluralTracks(album.tracks.count))
                                        .font(.nsm(.monoRegular, s(11)))
                                        .foregroundStyle(Palette.dim)
                                }
                            }
                        }
                        .buttonStyle(PressStyle(pressedOpacity: 0.9))
                        .stagger(index + 1, rise: 16, step: 0.05)
                    }
                }
            }
        }
        .alert("Новый плейлист", isPresented: $creating) {
            TextField("Название", text: $newName)
            Button("Создать") {
                if let created = library.createPlaylist(name: newName) {
                    toasts.show("Плейлист «\(created.name)» создан")
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}
