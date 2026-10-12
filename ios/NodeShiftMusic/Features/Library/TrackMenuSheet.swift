import SwiftUI

struct TrackMenuSheet: View {
    let track: TrackRecord
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.s) private var s

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let icon: LucideName
        let danger: Bool
    }

    private var entries: [Entry] {
        [
            Entry(id: "next", title: "Играть следом", icon: .listStart, danger: false),
            Entry(id: "queue", title: "Добавить в очередь", icon: .listEnd, danger: false),
            Entry(id: "playlist", title: "В плейлист…", icon: .listMusic, danger: false),
            Entry(id: "edit", title: "Редактировать", icon: .pencil, danger: false),
            Entry(id: "delete", title: "Удалить с телефона", icon: .trash2, danger: true),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(spacing: s(4)) {
                Capsule()
                    .fill(Palette.line2)
                    .frame(width: s(36), height: s(4))
                    .padding(.top, s(10))
                    .padding(.bottom, s(6))
                VStack(spacing: s(4)) {
                    Text(track.title)
                        .font(.nsm(.unboundedSemibold, s(14)))
                        .tracking(-0.025 * s(14))
                        .foregroundStyle(Palette.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.nsm(.monoRegular, s(11)))
                        .foregroundStyle(Palette.dim)
                        .lineLimit(1)
                }
                .padding(.bottom, s(8))
                ForEach(entries) { entry in
                    Button {
                        run(entry.id)
                    } label: {
                        HStack(spacing: s(12)) {
                            Icon(name: entry.icon, size: s(18), stroke: 1.6)
                                .foregroundStyle(entry.danger ? Palette.danger : Palette.muted)
                            Text(entry.title)
                                .font(.nsm(.interMedium, s(14)))
                                .foregroundStyle(entry.danger ? Palette.danger : Palette.white)
                            Spacer()
                        }
                        .padding(.horizontal, s(14))
                        .frame(height: s(48))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(pressedOpacity: 0.6))
                }
            }
            .padding(.horizontal, s(12))
            .padding(.bottom, s(14))
            .frame(maxWidth: .infinity)
            .background(Palette.modal)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card)))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card))
                    .strokeBorder(Palette.line2, lineWidth: 1)
            }
            .transition(.move(edge: .bottom))
        }
    }

    private func run(_ id: String) {
        switch id {
        case "next":
            player.playNext(track)
            toasts.show("Сыграет следующим")
        case "queue":
            player.addToQueue(track)
            toasts.show("Добавлено в очередь")
        default:
            toasts.show("Скоро будет")
        }
        close()
    }

    private func close() {
        withAnimation(Motion.expoOut(0.22)) {
            library.menuTrack = nil
        }
    }
}
