import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class MotionBudget {
    static let shared = MotionBudget()

    private var active = 0
    private let limit = 3

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if allowed && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                MotionVideoView(url: AppPaths.motionURL(motionName)) {
                    ready = true
                }
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
    }
}
