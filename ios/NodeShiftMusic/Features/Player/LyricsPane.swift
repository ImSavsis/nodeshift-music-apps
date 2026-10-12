import SwiftUI
import NSMCore

struct KaraokeWord: View {
    let text: String
    let fill: Double
    let size: CGFloat

    static func maskStops(fill: Double) -> [Gradient.Stop] {
        let head = fill * 1.18 - 0.18
        let tail = fill * 1.18
        func opacity(at x: Double) -> Double {
            if x <= head {
                return 1
            }
            if x >= tail {
                return 0
            }
            return 1 - (x - head) / (tail - head)
        }
        var stops: [Gradient.Stop] = [.init(color: Color.black.opacity(opacity(at: 0)), location: 0)]
        if head > 0 && head < 1 {
            stops.append(.init(color: Color.black, location: head))
        }
        if tail > 0 && tail < 1 {
            stops.append(.init(color: Color.black.opacity(0), location: tail))
        }
        stops.append(.init(color: Color.black.opacity(opacity(at: 1)), location: 1))
        return stops
    }

    var body: some View {
        let label = Text(text)
            .font(.nsm(.unboundedSemibold, size))
            .tracking(-0.015 * size)
        label
            .foregroundStyle(Color.white.opacity(fill >= 1 ? 1 : 0.34))
            .overlay {
                if fill > 0 && fill < 1 {
                    label
                        .foregroundStyle(Color.white)
                        .mask(
                            LinearGradient(
                                stops: Self.maskStops(fill: fill),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
    }
}

struct KaraokeLineView: View {
    let line: LyricLine
    let nextTime: Double?
    let index: Int
    let active: Int
    var onTap: () -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(\.s) private var s

    private struct Item {
        let text: String
        let spaceAfter: Bool
    }

    private var fontSize: CGFloat {
        s(20)
    }

    private var items: [Item] {
        if let words = line.words, !words.isEmpty {
            return words.enumerated().map { offset, word in
                let trimmed = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let space = word.text.last?.isWhitespace == true && offset < words.count - 1
                return Item(text: trimmed, spaceAfter: space)
            }
        }
        let words = Karaoke.syntheticWords(for: line.text)
        return words.enumerated().map { offset, word in
            Item(text: word.text, spaceAfter: offset < words.count - 1)
        }
    }

    var body: some View {
        let style = Karaoke.style(index: index, active: active)
        content
            .padding(.vertical, fontSize * 0.32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(style.opacity)
            .scaleEffect(style.scale, anchor: .leading)
            .blur(radius: s(style.blur))
            .animation(.easeInOut(duration: 0.55), value: active)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var content: some View {
        let list = items
        if index == active {
            TimelineView(.animation) { context in
                let time = player.time(at: context.date)
                let fills = Karaoke.fills(for: line, nextTime: nextTime, at: time)
                flow(list, fills: fills)
            }
        } else {
            flow(list, fills: Array(repeating: index < active ? 1 : 0, count: list.count))
        }
    }

    private func flow(_ list: [Item], fills: [Double]) -> some View {
        FlowLayout(spacing: 0, lineSpacing: fontSize * 0.1) {
            ForEach(list.indices, id: \.self) { position in
                KaraokeWord(
                    text: list[position].text,
                    fill: position < fills.count ? fills[position] : 0,
                    size: fontSize
                )
                .flowSpacingAfter(list[position].spaceAfter ? fontSize * 0.3 : 0)
            }
        }
    }
}

struct LyricsPane: View {
    let state: LyricsState
    @Environment(PlayerStore.self) private var player
    @Environment(\.s) private var s
    @State private var activeIndex = -1
    @State private var userScrollUntil = Date.distantPast

    var body: some View {
        switch state {
        case .loading:
            skeleton
        case let .synced(lines, _):
            synced(lines)
        case let .plain(text, _):
            plain(text)
        case .none:
            empty
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: s(24)) {
            ForEach(Array([0.7, 0.9, 0.55, 0.8, 0.65].enumerated()), id: \.offset) { index, width in
                SkeletonBar(delay: Double(index) * 0.12)
                    .frame(height: s(24))
                    .containerRelativeFrame(.horizontal) { length, _ in length * width }
            }
        }
        .padding(.horizontal, s(8))
        .padding(.vertical, s(40))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(spacing: s(12)) {
            Icon(name: .micOff, size: s(30), stroke: 1.4)
            Text("ТЕКСТ НЕ НАЙДЕН")
                .font(.nsm(.monoRegular, s(12)))
                .tracking(0.16 * s(12))
        }
        .foregroundStyle(Palette.dim)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func plain(_ text: String) -> some View {
        let blocks = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: s(28)) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    Text(block)
                        .font(.nsm(.unboundedMedium, s(17)))
                        .lineSpacing(s(17) * 0.625)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .reveal(min(index, 8))
                }
                Text("ТЕКСТ БЕЗ СИНХРОНИЗАЦИИ")
                    .font(.nsm(.monoRegular, s(11)))
                    .tracking(0.18 * s(11))
                    .foregroundStyle(Palette.dim)
            }
            .padding(.horizontal, s(4))
            .padding(.vertical, s(64))
        }
        .scrollIndicators(.hidden)
    }

    private func synced(_ lines: [LyricLine]) -> some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: proxy.size.height * 0.34)
                        IntroDots(visible: activeIndex == -1)
                        ForEach(lines.indices, id: \.self) { index in
                            KaraokeLineView(
                                line: lines[index],
                                nextTime: index + 1 < lines.count ? lines[index + 1].time : nil,
                                index: index,
                                active: activeIndex
                            ) {
                                player.seek(to: lines[index].time)
                            }
                            .id(index)
                        }
                        Color.clear.frame(height: proxy.size.height * 0.66)
                    }
                    .padding(.horizontal, s(4))
                }
                .scrollIndicators(.hidden)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.14),
                            .init(color: .black, location: 0.82),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let index = Karaoke.activeIndex(in: lines, at: player.time(at: context.date))
                        Color.clear
                            .onChange(of: index) { _, newValue in
                                activeIndex = newValue
                            }
                    }
                }
                .onChange(of: activeIndex) { _, newValue in
                    guard newValue >= 0, Date() >= userScrollUntil else { return }
                    withAnimation(.easeInOut(duration: 0.6)) {
                        reader.scrollTo(newValue, anchor: UnitPoint(x: 0.5, y: 0.34))
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6).onChanged { _ in
                        userScrollUntil = Date().addingTimeInterval(4)
                    }
                )
                .onAppear {
                    activeIndex = Karaoke.activeIndex(in: lines, at: player.time(at: Date()))
                }
            }
        }
    }
}

struct SkeletonBar: View {
    var delay: Double
    @State private var on = false

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(on ? 0.14 : 0.07))
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true).delay(delay)) {
                    on = true
                }
            }
    }
}

struct IntroDots: View {
    var visible: Bool
    @Environment(\.s) private var s

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !visible)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: s(8)) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (time - Double(index) * 0.15).truncatingRemainder(dividingBy: 1.2) / 1.2
                    let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)
                    Circle()
                        .fill(Color.white)
                        .frame(width: s(10), height: s(10))
                        .scaleEffect(0.6 + 0.4 * wave)
                        .opacity(0.35 + 0.65 * wave)
                }
            }
            .frame(height: visible ? s(24) : 0)
            .padding(.vertical, visible ? s(8) : 0)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: visible)
        }
    }
}
