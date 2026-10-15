import SwiftUI
import NSMCore

extension View {
    func edgeRim(_ radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: Color.white.opacity(0), location: 0.12),
                            .init(color: Color.white.opacity(0), location: 0.88),
                            .init(color: Color.white.opacity(0.05), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    func surfaceBox(_ radius: CGFloat, fill: Color = Palette.surface, border: Color = Palette.line) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .edgeRim(radius)
    }

    func floatShadow() -> some View {
        shadow(color: .black.opacity(0.5), radius: 2, y: 2)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 18)
    }
}

struct PressStyle: ButtonStyle {
    var pressedOpacity = 0.7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.s) private var s
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.nsm(.interSemibold, s(13.5)))
            .foregroundStyle(Color(hex: 0x111111))
            .padding(.horizontal, s(18))
            .frame(height: s(40))
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Palette.accentTop, Palette.accentBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.45), radius: s(10), y: s(6))
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.5))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration)
    }
}

private struct GhostButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.s) private var s
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.nsm(.interSemibold, s(13.5)))
            .foregroundStyle(Palette.white)
            .padding(.horizontal, s(18))
            .frame(height: s(40))
            .glassSurface(Capsule(), interactive: true, fallback: Palette.surface, stroke: true)
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.5))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ButtonLabel: View {
    let title: String
    var icon: LucideName?
    @Environment(\.s) private var s

    var body: some View {
        HStack(spacing: s(8)) {
            if let icon {
                Icon(name: icon, size: s(16))
            }
            Text(title)
        }
    }
}

struct Eyebrow: View {
    let text: String
    var bottom: CGFloat = 14
    @Environment(\.s) private var s

    var body: some View {
        Text(text.uppercased())
            .font(.nsm(.monoSemibold, s(11.5)))
            .tracking(0.16 * s(11.5))
            .foregroundStyle(Palette.dim)
            .padding(.bottom, s(bottom))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?
    @Environment(\.s) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: s(6)) {
            Text(title)
                .font(.nsm(.unboundedSemibold, s(20)))
                .tracking(-0.02 * s(20))
                .foregroundStyle(Palette.white)
            if let subtitle {
                Text(subtitle)
                    .font(.nsm(.interRegular, s(13.5)))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, s(18))
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    @Environment(\.s) private var s

    var body: some View {
        content
            .padding(s(padding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceBox(s(Radius.card))
    }
}

struct Chip: View {
    let title: String
    var active = false
    var icon: LucideName?
    var action: () -> Void
    @Environment(\.s) private var s

    var body: some View {
        Button(action: action) {
            HStack(spacing: s(6)) {
                if let icon {
                    Icon(name: icon, size: s(14), stroke: 1.8)
                }
                Text(title)
            }
            .font(.nsm(.interMedium, s(12.5)))
            .foregroundStyle(active ? Color(hex: 0x111111) : Palette.muted)
            .padding(.horizontal, s(14))
            .frame(height: s(32))
            .background(active ? Palette.accent : Color.clear, in: Capsule())
            .glassSurface(Capsule(), interactive: true, fallback: Palette.surface, stroke: true, enabled: !active)
        }
        .buttonStyle(PressStyle())
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

struct IconToggle: View {
    let icon: LucideName
    var active = false
    var size: CGFloat = 36
    var iconSize: CGFloat = 18
    var filled = false
    var tint: Color?
    var glass = false
    var action: () -> Void
    @Environment(\.s) private var s

    var body: some View {
        Button(action: action) {
            Icon(name: icon, size: s(iconSize), stroke: 1.8, filled: filled)
                .foregroundStyle(tint ?? (active ? Palette.white : Palette.dim))
                .frame(width: s(size), height: s(size))
                .glassSurface(Circle(), interactive: true, enabled: glass)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.6))
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

struct PlayCircle: View {
    var size: CGFloat = 44
    var playing = false
    var iconSize: CGFloat = 18
    @Environment(\.s) private var s

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Palette.accentTop, Palette.accentBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            ZStack {
                if playing {
                    Icon(name: .pause, size: s(iconSize), stroke: 2, filled: true)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Icon(name: .play, size: s(iconSize), stroke: 2, filled: true)
                        .offset(x: s(iconSize) * 0.05)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .foregroundStyle(Color(hex: 0x111111))
            .animation(Motion.spring, value: playing)
        }
        .frame(width: s(size), height: s(size))
        .shadow(color: .black.opacity(0.35), radius: s(10), y: s(5))
    }
}

struct FormatBadge: View {
    let format: String
    @Environment(\.s) private var s

    private var lossless: Bool {
        AudioFormats.lossless.contains(format.lowercased()) || format.lowercased() == "atmos"
    }

    private var title: String {
        switch format.lowercased() {
        case "atmos": return "ATMOS"
        case "eac3": return "DD+"
        case "ac3": return "DD"
        default: return format.uppercased()
        }
    }

    var body: some View {
        Text(title)
            .font(.nsm(.monoRegular, s(9.5)))
            .tracking(0.05 * s(9.5))
            .foregroundStyle(lossless ? Palette.white : Palette.dim)
            .padding(.horizontal, s(6))
            .padding(.vertical, 1)
            .background(lossless ? Color.white.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(lossless ? Color.white.opacity(0.4) : Palette.line2, lineWidth: 1)
            )
            .fixedSize()
    }
}

struct EqualizerBars: View {
    var isPlaying: Bool
    @Environment(\.s) private var s

    private static let delays: [Double] = [0, 0.15, 0.3, 0.1]
    private static let keyframes: [Double] = [0.25, 1, 0.4, 0.9, 0.25]

    static func scale(time: Double, delay: Double) -> Double {
        let duration = 1 + delay
        let local = max(0, time - delay)
        let u = (local / duration) - (local / duration).rounded(.down)
        let position = u * 4
        let index = min(3, Int(position.rounded(.down)))
        let fraction = position - Double(index)
        let eased = CubicBezier.easeInOut.value(at: fraction)
        return keyframes[index] + (keyframes[index + 1] - keyframes[index]) * eased
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: s(2)) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: s(2), height: s(14) * (isPlaying ? Self.scale(time: time, delay: Self.delays[index]) : 0.25))
                }
            }
            .frame(height: s(14), alignment: .bottom)
        }
    }
}

struct SeekBar: View {
    var value: Double
    var total: Double
    var onSeek: (Double) -> Void
    @Environment(\.s) private var s
    @State private var dragging = false
    @State private var dragValue = 0.0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let current = dragging ? dragValue : value
            let fraction = total > 0 ? min(1, max(0, current / total)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: s(4))
                Capsule().fill(Palette.accent).frame(width: max(0, width * fraction), height: s(4))
                Circle()
                    .fill(Palette.accent)
                    .frame(width: s(12), height: s(12))
                    .scaleEffect(dragging ? 1.3 : 1)
                    .offset(x: max(0, min(width - s(12), width * fraction - s(6))))
                    .animation(.easeOut(duration: 0.15), value: dragging)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let ratio = min(1, max(0, gesture.location.x / max(width, 1)))
                        dragValue = ratio * total
                    }
                    .onEnded { gesture in
                        let ratio = min(1, max(0, gesture.location.x / max(width, 1)))
                        onSeek(ratio * total)
                        dragging = false
                    }
            )
        }
        .frame(height: s(24))
    }
}

func formatClock(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", total / 60, total % 60)
}

struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if SoundSettings.shared.liquidGlass, #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
        }
    }
}

extension View {
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        modifier(LiquidGlassModifier(shape: shape))
    }
}

@MainActor
var glassActive: Bool {
    if #available(iOS 26.0, *) {
        return SoundSettings.shared.liquidGlass
    }
    return false
}
