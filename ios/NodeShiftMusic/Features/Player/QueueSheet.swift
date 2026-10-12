import SwiftUI

struct QueueSheet: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.s) private var s

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                VStack(spacing: 0) {
                    header
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(spacing: s(2)) {
                                ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                                    row(index: index, track: track)
                                        .id(index)
                                }
                            }
                            .padding(.horizontal, s(8))
                            .padding(.bottom, s(16))
                        }
                        .scrollIndicators(.hidden)
                        .onAppear {
                            if let current = player.currentIndex {
                                reader.scrollTo(current, anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * 0.8)
                .background(Palette.queue)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card)))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card))
                        .strokeBorder(Palette.line2, lineWidth: 1)
                }
                .transition(.move(edge: .bottom))
            }
        }
    }

    private var header: some View {
        HStack(spacing: s(4)) {
            VStack(alignment: .leading, spacing: s(4)) {
                Text("Очередь")
                    .font(.nsm(.unboundedSemibold, s(14)))
                    .tracking(-0.025 * s(14))
                    .foregroundStyle(Palette.white)
                Text("\(player.queue.count) в списке · \(player.upcomingCount) далее")
                    .font(.nsm(.monoRegular, s(11)))
                    .foregroundStyle(Palette.dim)
            }
            Spacer()
            IconToggle(icon: .shuffle, active: player.shuffle, size: 36, iconSize: 17) {
                player.toggleShuffle()
            }
            IconToggle(icon: player.repeatMode == .one ? .repeat1 : .repeatAll, active: player.repeatMode != .off, size: 36, iconSize: 17) {
                player.cycleRepeat()
            }
            IconToggle(icon: .trash2, size: 36, iconSize: 17) {
                withAnimation(Motion.expoOut(0.3)) {
                    player.clearUpcoming()
                }
            }
            IconToggle(icon: .x, size: 36, iconSize: 17, action: close)
        }
        .padding(.horizontal, s(18))
        .padding(.vertical, s(14))
    }

    private func row(index: Int, track: TrackRecord) -> some View {
        let isCurrent = index == player.currentIndex
        let played = (player.currentIndex ?? -1) > index
        return Button {
            player.jump(to: index)
        } label: {
            HStack(spacing: s(12)) {
                Text("\(index + 1)")
                    .font(.nsm(.monoRegular, s(11)))
                    .foregroundStyle(Palette.dim)
                    .frame(width: s(22))
                CoverArt(coverName: track.coverName, live: false, maxPixel: 160)
                    .frame(width: s(40), height: s(40))
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
                if isCurrent {
                    EqualizerBars(isPlaying: player.isPlaying)
                } else {
                    IconToggle(icon: .x, size: 32, iconSize: 15) {
                        withAnimation(Motion.expoOut(0.25)) {
                            player.remove(at: index)
                        }
                    }
                }
            }
            .padding(.horizontal, s(8))
            .padding(.vertical, s(6))
            .background(isCurrent ? Palette.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: s(Radius.tile), style: .continuous))
            .opacity(played ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.8))
    }

    private func close() {
        withAnimation(Motion.expoOut(0.32)) {
            player.isQueueOpen = false
        }
    }
}
