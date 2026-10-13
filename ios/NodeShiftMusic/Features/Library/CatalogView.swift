import SwiftUI

struct CatalogSection: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.s) private var s

    var body: some View {
        @Bindable var catalog = catalog
        let list = catalog.tracks
        VStack(alignment: .leading, spacing: 0) {
            SearchField(text: $catalog.query, placeholder: "Поиск по всем трекам сайта")
                .padding(.bottom, s(14))
                .onChange(of: catalog.query) { _, _ in
                    catalog.queryChanged()
                }
            HStack(spacing: s(10)) {
                Button {
                    Task { await playWave() }
                } label: {
                    ButtonLabel(title: "Случайная волна", icon: .sparkles)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(action: shuffleList) {
                    ButtonLabel(title: "Перемешать", icon: .shuffle)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(list.isEmpty)
            }
            .padding(.bottom, s(26))
            controls
            Eyebrow(text: catalog.query.isEmpty ? "Каталог сайта" : "Результаты поиска")
            content(list)
        }
        .task {
            catalog.startIfNeeded()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: s(8)) {
            FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                ForEach(LibrarySort.allCases, id: \.self) { sort in
                    Chip(title: sort.label, active: catalog.sort == sort) {
                        withAnimation(Motion.expoOut(0.3)) {
                            catalog.sort = sort
                        }
                        catalog.reload()
                    }
                }
            }
            FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                ForEach(FormatFilter.allCases, id: \.self) { filter in
                    Chip(title: filter.label, active: catalog.formatFilter == filter) {
                        withAnimation(Motion.expoOut(0.3)) {
                            catalog.formatFilter = filter
                        }
                        catalog.reload()
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

    @ViewBuilder
    private func content(_ list: [TrackRecord]) -> some View {
        if list.isEmpty {
            if catalog.isLoading {
                ProgressView()
                    .tint(Palette.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, s(40))
            } else if catalog.failed {
                VStack(alignment: .leading, spacing: s(12)) {
                    Text("Не получилось загрузить каталог. Проверь интернет.")
                        .font(.nsm(.interRegular, s(14)))
                        .foregroundStyle(Palette.dim)
                    Button {
                        catalog.reload()
                    } label: {
                        ButtonLabel(title: "Повторить", icon: .refreshCw)
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            } else {
                Text("Ничего не найдено.")
                    .font(.nsm(.interRegular, s(14)))
                    .foregroundStyle(Palette.dim)
            }
        } else {
            VStack(alignment: .leading, spacing: s(24)) {
                if library.viewMode == .grid {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: s(14), alignment: .top),
                            GridItem(.flexible(), spacing: s(14), alignment: .top),
                        ],
                        spacing: s(24)
                    ) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                            TrackCard(track: track, queue: list, showsDownloaded: true)
                                .stagger(index % CatalogStore.pageSize, rise: 16, step: 0.04)
                        }
                    }
                } else {
                    LazyVStack(spacing: s(4)) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, queue: list, showsDownloaded: true)
                                .stagger(index % CatalogStore.pageSize, rise: 10, step: 0.03)
                        }
                    }
                }
                if catalog.hasMore {
                    ProgressView()
                        .tint(Palette.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, s(12))
                        .onAppear {
                            catalog.loadMore()
                        }
                }
            }
        }
    }

    private func playWave() async {
        let picked = await catalog.wave()
        guard let first = picked.first else { return }
        player.shuffle = true
        player.play(first, in: picked)
    }

    private func shuffleList() {
        let all = catalog.tracks.shuffled()
        guard let first = all.first else { return }
        player.shuffle = true
        player.play(first, in: all)
    }
}
