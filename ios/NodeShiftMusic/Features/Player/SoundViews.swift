import SwiftUI

struct SoundPicker: View {
    @Environment(\.s) private var s

    var body: some View {
        let settings = SoundSettings.shared
        VStack(alignment: .leading, spacing: s(20)) {
            VStack(alignment: .leading, spacing: s(10)) {
                Eyebrow(text: "Качество потока", bottom: 0)
                FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                    ForEach(StreamQuality.allCases, id: \.self) { value in
                        Chip(title: value.title, active: settings.streamQuality == value) {
                            settings.setStreamQuality(value)
                        }
                    }
                }
                Text(settings.streamQuality.detail)
                    .font(.nsm(.interRegular, s(12.5)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: s(10)) {
                Eyebrow(text: "Dolby Atmos", bottom: 0)
                FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                    ForEach(AtmosMode.allCases, id: \.self) { value in
                        Chip(title: value.title, active: settings.atmosMode == value) {
                            settings.setAtmosMode(value)
                        }
                    }
                }
                Text(settings.atmosMode.detail)
                    .font(.nsm(.interRegular, s(12.5)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SoundChip: View {
    let track: TrackRecord
    var action: () -> Void
    @Environment(\.s) private var s

    var body: some View {
        let info = track.soundInfo(wantsLossless: SoundSettings.shared.wantsLossless())
        Button(action: action) {
            HStack(spacing: s(8)) {
                Icon(name: .slidersHorizontal, size: s(13), stroke: 1.8)
                Text(info.label)
                    .font(.nsm(.interSemibold, s(12)))
                if !info.detail.isEmpty {
                    Text(info.detail)
                        .font(.nsm(.monoRegular, s(10.5)))
                        .foregroundStyle(Palette.dim)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(info.isLossless || info.isAtmos ? Palette.white : Palette.muted)
            .padding(.horizontal, s(12))
            .frame(height: s(30))
            .background(Color.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(info.isLossless || info.isAtmos ? Color.white.opacity(0.4) : Palette.line2, lineWidth: 1))
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.7))
    }
}

struct SoundSheet: View {
    let track: TrackRecord?
    var onClose: () -> Void
    @Environment(\.s) private var s

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: s(16)) {
                Capsule()
                    .fill(Palette.line2)
                    .frame(width: s(36), height: s(4))
                    .frame(maxWidth: .infinity)
                    .padding(.top, s(10))
                Text("Звук")
                    .font(.nsm(.unboundedSemibold, s(16)))
                    .tracking(-0.025 * s(16))
                    .foregroundStyle(Palette.white)
                if let track {
                    let info = track.soundInfo(wantsLossless: SoundSettings.shared.wantsLossless())
                    VStack(alignment: .leading, spacing: s(4)) {
                        Text("Сейчас играет")
                            .font(.nsm(.monoRegular, s(11)))
                            .foregroundStyle(Palette.dim)
                        Text(info.label)
                            .font(.nsm(.interSemibold, s(15)))
                            .foregroundStyle(Palette.white)
                        if !info.detail.isEmpty {
                            Text(info.detail)
                                .font(.nsm(.monoRegular, s(11.5)))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(s(14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceBox(s(Radius.tile))
                }
                SoundPicker()
                Text("Настройка действует на следующий трек. Atmos работает с файлами E-AC-3 на телефоне.")
                    .font(.nsm(.interRegular, s(12)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onClose) {
                    ButtonLabel(title: "Готово", icon: .check)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
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
    }
}
