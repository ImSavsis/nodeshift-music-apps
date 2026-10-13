import SwiftUI

enum LibraryMode: String {
    case mine
    case catalog
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.openTab) private var openTab
    @Environment(\.openStorage) private var openStorage
    @Environment(\.s) private var s
    @State private var chosenMode: LibraryMode?

    private var mode: LibraryMode {
        if let chosenMode {
            return chosenMode
        }
        if let stored = UserDefaults.standard.string(forKey: "nsm_library_mode"), let value = LibraryMode(rawValue: stored) {
            return value
        }
        return library.loaded && library.tracks.isEmpty ? .catalog : .mine
    }

    var body: some View {
        ScreenScroll {
            UpdateBanner()
            PageHeader(
                title: "Треки",
                subtitle: mode == .catalog ? "Все треки NodeShift, играют онлайн" : "Вся твоя музыка у тебя на телефоне"
            )
            .reveal(0)
            modeSwitch
                .reveal(1)
            if mode == .catalog {
                CatalogSection()
                    .reveal(2)
            } else {
                mineContent
            }
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: s(8)) {
            Chip(title: "Моя музыка", active: mode == .mine) {
                choose(.mine)
            }
            Chip(title: "Весь каталог", active: mode == .catalog, icon: .cloud) {
                choose(.catalog)
            }
        }
        .padding(.bottom, s(18))
    }

    private func choose(_ value: LibraryMode) {
        UserDefaults.standard.set(value.rawValue, forKey: "nsm_library_mode")
        withAnimation(Motion.expoOut(0.3)) {
            chosenMode = value
        }
    }

    @ViewBuilder
    private var mineContent: some View {
        @Bindable var library = library
        let list = library.filtered
        SearchField(text: $library.query, placeholder: "Поиск по трекам")
            .padding(.bottom, s(14))
            .reveal(1)
        HStack(spacing: s(10)) {
            Button(action: playWave) {
                ButtonLabel(title: "Случайная волна", icon: .sparkles)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button(action: shuffleAll) {
                ButtonLabel(title: "Перемешать", icon: .shuffle)
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.bottom, s(26))
        .reveal(2)

        if library.tracks.isEmpty {
            emptyLibrary.reveal(3)
        } else {
            if library.query.isEmpty && !library.recent.isEmpty {
                recentSection.reveal(3)
            }
            controls.reveal(4)
            Eyebrow(text: library.query.isEmpty ? "Библиотека" : "Результаты поиска")
                .reveal(4)
            if list.isEmpty {
                Text("Ничего не найдено.")
                    .font(.nsm(.interRegular, s(14)))
                    .foregroundStyle(Palette.dim)
            } else if library.viewMode == .grid {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: s(14), alignment: .top),
                        GridItem(.flexible(), spacing: s(14), alignment: .top),
                    ],
                    spacing: s(24)
                ) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                        TrackCard(track: track, queue: list)
                            .stagger(index, rise: 16, step: 0.04)
                    }
                }
            } else {
                LazyVStack(spacing: s(4)) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, queue: list)
                            .stagger(index, rise: 10, step: 0.03)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Недавно слушали")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: s(20)) {
                    ForEach(library.recent) { track in
                        TrackCard(track: track, queue: library.recent)
                            .frame(width: s(160))
                    }
                }
                .padding(.horizontal, s(16))
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.horizontal, -s(16))
        }
        .padding(.bottom, s(26))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: s(8)) {
            FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                ForEach(LibrarySort.allCases, id: \.self) { sort in
                    Chip(title: sort.label, active: library.sort == sort) {
                        withAnimation(Motion.expoOut(0.3)) {
                            library.sort = sort
                        }
                    }
                }
            }
            FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                ForEach(FormatFilter.allCases, id: \.self) { filter in
                    Chip(title: filter.label, active: library.formatFilter == filter) {
                        withAnimation(Motion.expoOut(0.3)) {
                            library.formatFilter = filter
                        }
                    }
                }
                Chip(title: "Сеткой", active: library.viewMode == .grid, icon: .layoutGrid) {
                    withAnimation(Motion.expoOut(0.3)) {
                        library.changeViewMode(.grid)
                    }
                }
                Chip(title: "Списком", active: library.viewMode == .list, icon: .layoutList) {
                    withAnimation(Motion.expoOut(0.3)) {
                        library.changeViewMode(.list)
                    }
                }
            }
        }
        .padding(.bottom, s(26))
    }

    private var emptyLibrary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(14)) {
                CrystalMark(size: s(40), dim: true)
                Text("Пока пусто")
                    .font(.nsm(.unboundedSemibold, s(16)))
                    .foregroundStyle(Palette.white)
                Text("Добавь треки через вкладку «Импорт»: файлы, папки или архивы. Названия, альбомы и обложки подтянутся сами. Или войди через сайт и скачай свои плейлисты и лайки.")
                    .font(.nsm(.interRegular, s(13.5)))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    openTab(.importer)
                } label: {
                    ButtonLabel(title: "Открыть импорт", icon: .upload)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(action: openStorage) {
                    ButtonLabel(title: "Скачать с сайта", icon: .cloudDownload)
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private func playWave() {
        let picked = Array(library.tracks.shuffled().prefix(40))
        guard let first = picked.first else { return }
        player.shuffle = true
        player.play(first, in: picked)
    }

    private func shuffleAll() {
        let all = library.filtered.shuffled()
        guard let first = all.first else { return }
        player.shuffle = true
        player.play(first, in: all)
    }
}
