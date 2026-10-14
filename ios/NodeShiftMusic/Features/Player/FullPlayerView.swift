import SwiftUI
import NSMCore

enum PlayerTab: String {
    case player
    case lyrics
}

struct FullPlayerView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(CatalogStore.self) private var catalog
    @Environment(LyricsStore.self) private var lyrics
    @Environment(\.openOverlay) private var openOverlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.s) private var s
    @State private var tab: PlayerTab = .player
    @State private var drag: CGFloat = 0
    @State private var palette: [RGB8] = PaletteExtractor.fallback
    @State private var showSound = false

    init() {
        _tab = State(initialValue: ProcessInfo.processInfo.arguments.contains("-nsm-lyrics") ? .lyrics : .player)
    }

    private static var windowTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.compactMap { $0.keyWindow }.first?.safeAreaInsets.top ?? 47
    }

    private var immersive: Bool {
        guard tab == .player, let track = player.current, !reduceMotion else { return false }
        return SoundSettings.shared.motionCovers && MotionStore.hasAny(track)
    }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                tabs
                content
            }
            if showSound {
                SoundSheet(track: player.current) {
                    withAnimation(Motion.expoOut(0.3)) {
                        showSound = false
                    }
                }
                .transition(.move(edge: .bottom))
                .zIndex(5)
            }
        }
        .offset(y: drag)
        .task(id: player.current?.id) {
            guard let track = player.current else { return }
            palette = await PaletteProvider.shared.palette(coverName: track.coverName)
            await lyrics.ensure(track)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        Palette.bg.ignoresSafeArea()
        if immersive, let track = player.current {
            ZStack {
                ImmersiveCover(track: track, topInset: Self.windowTop + s(96))
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.45), location: 0),
                        .init(color: Color.black.opacity(0), location: 0.18),
                        .init(color: Color.black.opacity(0), location: 0.4),
                        .init(color: Color.black.opacity(0.7), location: 0.62),
                        .init(color: Color.black.opacity(0.9), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
            .transition(.opacity)
        } else {
            AmbientBackdrop(palette: palette, playing: player.isPlaying)
                .ignoresSafeArea()
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            Group {
                if tab == .player {
                    if immersive {
                        immersivePane
                    } else {
                        playerPane(size: proxy.size)
                    }
                } else if let track = player.current {
                    lyricsPane(track)
                }
            }
            .transition(.opacity)
            .animation(Motion.opacity, value: tab)
        }
    }

    private var header: some View {
        HStack {
            Button(action: close) {
                Icon(name: .chevronDown, size: s(24), stroke: 2)
                    .foregroundStyle(Palette.white)
                    .frame(width: s(40), height: s(40))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(pressedOpacity: 0.6))
            Spacer()
            VStack(spacing: s(6)) {
                Capsule()
                    .fill(Palette.line2)
                    .frame(width: s(36), height: s(4))
                Text("СЕЙЧАС ИГРАЕТ")
                    .font(.nsm(.monoRegular, s(11)))
                    .tracking(0.2 * s(11))
                    .foregroundStyle(Palette.dim)
            }
            Spacer()
            Button {
                withAnimation(Motion.expoOut(0.32)) {
                    player.isQueueOpen = true
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Icon(name: .listMusic, size: s(20), stroke: 2)
                        .foregroundStyle(Palette.white)
                        .frame(width: s(40), height: s(40))
                    if player.upcomingCount > 0 {
                        Text(player.upcomingCount > 99 ? "99+" : "\(player.upcomingCount)")
                            .font(.nsm(.monoSemibold, s(9)))
                            .foregroundStyle(Color(hex: 0x111111))
                            .padding(.horizontal, s(4))
                            .frame(minWidth: s(16), minHeight: s(16))
                            .background(Color.white, in: Capsule())
                            .offset(x: s(-2), y: s(2))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(pressedOpacity: 0.6))
        }
        .padding(.horizontal, s(14))
        .padding(.top, s(8))
        .padding(.bottom, s(6))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    drag = value.translation.height > 0 ? value.translation.height * 0.5 : 0
                }
                .onEnded { value in
                    if value.translation.height > 140 || value.predictedEndTranslation.height > 560 {
                        close()
                    } else {
                        withAnimation(Motion.spring) {
                            drag = 0
                        }
                    }
                }
        )
    }

    private var tabs: some View {
        HStack(spacing: s(8)) {
            tabPill("Плеер", tab: .player)
            tabPill("Текст", tab: .lyrics)
        }
        .padding(.bottom, s(8))
    }

    private func tabPill(_ title: String, tab target: PlayerTab) -> some View {
        let active = tab == target
        return Button {
            withAnimation(Motion.opacity) {
                tab = target
            }
        } label: {
            Text(title)
                .font(.nsm(.interSemibold, s(13)))
                .foregroundStyle(active ? Palette.white : Palette.dim)
                .padding(.horizontal, s(20))
                .padding(.vertical, s(7))
                .background(active ? Palette.surface2 : Color.clear, in: Capsule())
                .overlay {
                    if active {
                        Capsule().strokeBorder(Palette.line2, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.7))
        .animation(.easeOut(duration: 0.2), value: active)
    }

    private func playerPane(size: CGSize) -> some View {
        let track = player.current
        let side = max(s(140), min(size.width * 0.84, size.height - s(310)))
        return VStack(spacing: s(22)) {
            Spacer(minLength: 0)
            CoverArt(coverName: track?.coverName, motionName: track?.motionName, radius: Radius.card, maxPixel: 1000)
                .frame(width: side, height: side)
                .scaleEffect(player.isPlaying ? 1 : 0.92)
                .animation(Motion.coverSpring, value: player.isPlaying)
                .shadow(color: .black.opacity(0.55), radius: s(40), y: s(30))
            VStack(spacing: s(16)) {
                titleRow(track)
                soundRow(track)
                progressRow
                transport
                actions(track)
            }
            .padding(.horizontal, s(20))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var immersivePane: some View {
        let track = player.current
        return VStack(spacing: s(16)) {
            Spacer(minLength: 0)
            titleRow(track)
            soundRow(track)
            progressRow
            transport
            actions(track)
        }
        .padding(.horizontal, s(20))
        .padding(.bottom, s(10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lyricsPane(_ track: TrackRecord) -> some View {
        VStack(spacing: s(10)) {
            LyricsPane(state: lyrics.state(for: track))
                .padding(.horizontal, s(20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: s(8)) {
                progressRow
                compactTransport
            }
            .padding(.horizontal, s(20))
            .padding(.bottom, s(8))
        }
    }

    @ViewBuilder
    private func soundRow(_ track: TrackRecord?) -> some View {
        if let track {
            SoundChip(track: track) {
                withAnimation(Motion.expoOut(0.32)) {
                    showSound = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func titleRow(_ track: TrackRecord?) -> some View {
        HStack(alignment: .center, spacing: s(12)) {
            VStack(alignment: .leading, spacing: s(6)) {
                Text(track?.title ?? "")
                    .font(.nsm(.unboundedSemibold, s(20)))
                    .tracking(-0.025 * s(20))
                    .foregroundStyle(Palette.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: s(8)) {
                    Text(track?.artist ?? "")
                        .font(.nsm(.monoRegular, s(12)))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    if let format = track?.format {
                        FormatBadge(format: format)
                    }
                }
            }
            Spacer(minLength: 0)
            EqualizerBars(isPlaying: player.isPlaying)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressRow: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !player.isPlaying)) { context in
            let time = player.time(at: context.date)
            HStack(spacing: s(12)) {
                Text(formatClock(time))
                    .font(.nsm(.monoRegular, s(11)))
                    .foregroundStyle(Palette.muted)
                    .frame(width: s(40), alignment: .trailing)
                SeekBar(value: time, total: player.duration) { target in
                    player.seek(to: target)
                }
                Text(formatClock(player.duration))
                    .font(.nsm(.monoRegular, s(11)))
                    .foregroundStyle(Palette.muted)
                    .frame(width: s(40), alignment: .leading)
            }
        }
    }

    private var transport: some View {
        HStack {
            IconToggle(icon: .shuffle, active: player.shuffle, size: 44, iconSize: 19) {
                player.toggleShuffle()
            }
            Spacer()
            IconToggle(icon: .skipBack, active: true, size: 48, iconSize: 24, filled: true) {
                player.previous()
            }
            Spacer()
            Button {
                player.togglePlay()
            } label: {
                PlayCircle(size: 64, playing: player.isPlaying, iconSize: 26)
            }
            .buttonStyle(PressStyle(pressedOpacity: 0.95))
            Spacer()
            IconToggle(icon: .skipForward, active: true, size: 48, iconSize: 24, filled: true) {
                player.next()
            }
            Spacer()
            IconToggle(icon: player.repeatMode == .one ? .repeat1 : .repeatAll, active: player.repeatMode != .off, size: 44, iconSize: 19) {
                player.cycleRepeat()
            }
        }
    }

    private var compactTransport: some View {
        HStack {
            Spacer()
            IconToggle(icon: .skipBack, active: true, size: 48, iconSize: 24, filled: true) {
                player.previous()
            }
            Spacer()
            Button {
                player.togglePlay()
            } label: {
                PlayCircle(size: 56, playing: player.isPlaying, iconSize: 24)
            }
            .buttonStyle(PressStyle(pressedOpacity: 0.95))
            Spacer()
            IconToggle(icon: .skipForward, active: true, size: 48, iconSize: 24, filled: true) {
                player.next()
            }
            Spacer()
        }
    }

    private func actions(_ track: TrackRecord?) -> some View {
        HStack(spacing: s(28)) {
            if let track {
                IconToggle(icon: .heart, active: catalog.isFavorite(track), size: 40, iconSize: 19, filled: catalog.isFavorite(track)) {
                    withAnimation(Motion.spring) {
                        catalog.toggleFavorite(track, library: library)
                        if !track.isRemote, let updated = library.track(id: track.id) {
                            player.updateTrack(updated)
                        }
                    }
                }
                IconToggle(icon: .listPlus, size: 40, iconSize: 19) {
                    library.playlistTrack = track
                }
                IconToggle(icon: .users, size: 40, iconSize: 19) {
                    openOverlay(.together)
                }
                IconToggle(icon: .ellipsis, size: 40, iconSize: 19) {
                    library.menuTrack = track
                }
            }
        }
    }

    private func close() {
        withAnimation(Motion.expoOut(0.38)) {
            player.isFullPlayerOpen = false
            drag = 0
        }
    }
}
