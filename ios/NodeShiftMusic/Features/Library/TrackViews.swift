import SwiftUI

struct TrackActionsPill: View {
    let track: TrackRecord
    @Environment(LibraryStore.self) private var library
    @Environment(\.s) private var s

    var body: some View {
        HStack(spacing: 0) {
            IconToggle(icon: .heart, active: track.isFavorite, size: 32, iconSize: 16, filled: track.isFavorite) {
                withAnimation(Motion.spring) {
                    library.toggleFavorite(track.id)
                }
            }
            IconToggle(icon: .ellipsis, size: 32, iconSize: 16) {
                library.menuTrack = track
            }
        }
        .padding(.horizontal, s(2))
        .background(Color.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
    }
}

struct TrackCard: View {
    let track: TrackRecord
    let queue: [TrackRecord]
    @Environment(PlayerStore.self) private var player
    @Environment(\.s) private var s

    private var isCurrent: Bool {
        player.current?.id == track.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: s(12)) {
            ZStack(alignment: .topTrailing) {
                Button(action: activate) {
                    CoverArt(coverName: track.coverName)
                        .overlay {
                            ZStack {
                                Color.black.opacity(isCurrent ? 0.30 : 0)
                                PlayCircle(size: 48, playing: isCurrent && player.isPlaying, iconSize: 20)
                                    .scaleEffect(isCurrent ? 1 : 0.9)
                                    .opacity(isCurrent ? 1 : 0)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: s(Radius.tile), style: .continuous))
                            .animation(.easeOut(duration: 0.2), value: isCurrent)
                        }
                }
                .buttonStyle(PressStyle(pressedOpacity: 0.92))
                TrackActionsPill(track: track)
                    .padding(s(6))
            }
            .overlay(alignment: .bottomLeading) {
                if isCurrent {
                    EqualizerBars(isPlaying: player.isPlaying)
                        .padding(.horizontal, s(8))
                        .padding(.vertical, s(4))
                        .background(Palette.bg.opacity(0.8), in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
                        .padding(s(8))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            VStack(alignment: .leading, spacing: s(2)) {
                Text(track.title)
                    .font(.nsm(.interMedium, s(14)))
                    .foregroundStyle(Palette.white)
                    .lineLimit(1)
                HStack(spacing: s(6)) {
                    Text(track.artist)
                        .font(.nsm(.monoRegular, s(11)))
                        .foregroundStyle(Palette.dim)
                        .lineLimit(1)
                    FormatBadge(format: track.format)
                }
            }
        }
    }

    private func activate() {
        if isCurrent {
            player.togglePlay()
        } else {
            player.play(track, in: queue)
        }
    }
}

struct TrackRow: View {
    let track: TrackRecord
    let queue: [TrackRecord]
    var rank: Int?
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.s) private var s

    private var isCurrent: Bool {
        player.current?.id == track.id
    }

    var body: some View {
        Button(action: activate) {
            HStack(spacing: s(12)) {
                if let rank {
                    Text("\(rank)")
                        .font(.nsm(.monoRegular, s(12)))
                        .foregroundStyle(Palette.dim)
                        .frame(width: s(24))
                }
                CoverArt(coverName: track.coverName, live: false, maxPixel: 200)
                    .frame(width: s(44), height: s(44))
                    .overlay {
                        if isCurrent {
                            ZStack {
                                Color.black.opacity(0.4)
                                Icon(name: player.isPlaying ? .pause : .play, size: s(16), stroke: 2, filled: true)
                                    .foregroundStyle(Palette.white)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: s(Radius.tile), style: .continuous))
                        }
                    }
                VStack(alignment: .leading, spacing: s(2)) {
                    Text(track.title)
                        .font(.nsm(.interMedium, s(14)))
                        .foregroundStyle(Palette.white)
                        .lineLimit(1)
                    HStack(spacing: s(8)) {
                        Text(track.artist)
                            .font(.nsm(.monoRegular, s(11)))
                            .foregroundStyle(Palette.dim)
                            .lineLimit(1)
                        FormatBadge(format: track.format)
                    }
                }
                Spacer(minLength: 0)
                if isCurrent {
                    EqualizerBars(isPlaying: player.isPlaying)
                }
                IconToggle(icon: .heart, active: track.isFavorite, size: 32, iconSize: 16, filled: track.isFavorite) {
                    withAnimation(Motion.spring) {
                        library.toggleFavorite(track.id)
                    }
                }
                IconToggle(icon: .ellipsis, size: 32, iconSize: 16) {
                    library.menuTrack = track
                }
            }
            .padding(.horizontal, s(8))
            .padding(.vertical, s(8))
            .background(isCurrent ? Palette.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: s(Radius.tile), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: s(Radius.tile), style: .continuous)
                    .strokeBorder(isCurrent ? Palette.line2 : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.85))
        .animation(.easeOut(duration: 0.2), value: isCurrent)
    }

    private func activate() {
        if isCurrent {
            player.togglePlay()
        } else {
            player.play(track, in: queue)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    @Environment(\.s) private var s
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: s(10)) {
            Icon(name: .search, size: s(16), stroke: 1.8)
                .foregroundStyle(Palette.dim)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.dim))
                .font(.nsm(.interRegular, s(15)))
                .foregroundStyle(Palette.white)
                .tint(Palette.white)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Icon(name: .x, size: s(14), stroke: 2)
                        .foregroundStyle(Palette.dim)
                        .frame(width: s(24), height: s(24))
                }
                .buttonStyle(PressStyle(pressedOpacity: 0.6))
            }
        }
        .padding(.horizontal, s(16))
        .frame(height: s(44))
        .background(focused ? Palette.surface2 : Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Color.white.opacity(0.4) : Palette.line2, lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: focused)
    }
}
