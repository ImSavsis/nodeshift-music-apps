import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class MotionBudget {
    static let shared = MotionBudget()

    private var active = 0
    private let limit = 4

    func acquire() -> Bool {
        if active >= limit {
            return false
        }
        active += 1
        return true
    }

    func release() {
        active = max(0, active - 1)
    }
}

final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    var onReady: (() -> Void)?

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func start(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer.player = queue
        playerLayer.videoGravity = .resizeAspectFill
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            if layer.isReadyForDisplay {
                DispatchQueue.main.async {
                    self?.onReady?()
                }
            }
        }
        queue.play()
    }

    func stop() {
        readyObservation?.invalidate()
        readyObservation = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
        player = nil
    }

    deinit {
        readyObservation?.invalidate()
    }
}

struct MotionVideoView: UIViewRepresentable {
    let url: URL
    var onReady: () -> Void

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.backgroundColor = .clear
        view.onReady = onReady
        view.start(url: url)
        return view
    }

    func updateUIView(_ view: LoopingPlayerView, context: Context) {
        view.onReady = onReady
    }

    static func dismantleUIView(_ view: LoopingPlayerView, coordinator: ()) {
        view.stop()
    }
}

struct MotionOverlay: View {
    let motionName: String
    @State private var ready = false
    @State private var allowed = false
    @State private var url: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if allowed, !reduceMotion, SoundSettings.shared.motionCovers, let url {
                MotionVideoView(url: url) {
                    ready = true
                }
                .id(url)
                .opacity(ready ? 1 : 0)
                .animation(.easeInOut(duration: 0.7), value: ready)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            allowed = MotionBudget.shared.acquire()
        }
        .onDisappear {
            if allowed {
                MotionBudget.shared.release()
                allowed = false
                ready = false
            }
        }
        .task(id: "\(motionName)#\(allowed)") {
            guard allowed else { return }
            ready = false
            url = await MotionStore.shared.squareURL(motionName)
        }
    }
}

struct MotionFullBleed: View {
    let squareName: String?
    let tallName: String?
    @State private var ready = false
    @State private var url: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let url, !reduceMotion, SoundSettings.shared.motionCovers {
                MotionVideoView(url: url) {
                    ready = true
                }
                .id(url)
                .opacity(ready ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: ready)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(squareName ?? "")|\(tallName ?? "")") {
            ready = false
            url = await MotionStore.shared.tallURL(squareName: squareName, tallName: tallName)
        }
    }
}

struct MotionSquareFill: View {
    let motionName: String
    @State private var ready = false
    @State private var url: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let url, !reduceMotion, SoundSettings.shared.motionCovers {
                MotionVideoView(url: url) {
                    ready = true
                }
                .id(url)
                .opacity(ready ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: ready)
            }
        }
        .allowsHitTesting(false)
        .task(id: motionName) {
            ready = false
            url = await MotionStore.shared.squareURL(motionName)
        }
    }
}

struct SharpCover: View {
    let coverName: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: coverName) {
            guard let coverName else {
                image = nil
                return
            }
            image = await CoverImageLoader.shared.image(url: CoverSource.url(for: coverName, maxPixel: 1000), maxPixel: 1000)
        }
    }
}

struct BlurredCover: View {
    let coverName: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.bg
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 46)
                    .scaleEffect(1.3)
                    .transition(.opacity)
            }
            Color.black.opacity(0.35)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.5), value: image == nil)
        .task(id: coverName) {
            guard let coverName else {
                image = nil
                return
            }
            image = await CoverImageLoader.shared.image(url: CoverSource.url(for: coverName, maxPixel: 300), maxPixel: 300)
        }
    }
}

struct ImmersiveCover: View {
    let track: TrackRecord

    private var hasLocalTall: Bool {
        guard let name = track.motion3x4Name else { return false }
        return FileManager.default.fileExists(atPath: AppPaths.motionURL(name).path)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                BlurredCover(coverName: track.coverName)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                if hasLocalTall {
                    ZStack {
                        SharpCover(coverName: track.coverName)
                        MotionFullBleed(squareName: nil, tallName: track.motion3x4Name)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    ZStack {
                        SharpCover(coverName: track.coverName)
                        if let motion = track.motionName {
                            MotionSquareFill(motionName: motion)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.82),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}
