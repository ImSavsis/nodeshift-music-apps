import AVFoundation

@MainActor
final class AudioSessionWatcher {
    private weak var player: PlayerStore?
    private var policy = InterruptionPolicy()
    private var token: NSObjectProtocol?

    init(player: PlayerStore) {
        self.player = player
        token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                self?.handle(rawType: rawType, rawOptions: rawOptions)
            }
        }
    }

    private func handle(rawType: UInt?, rawOptions: UInt) {
        guard let player,
              let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        let event: InterruptionPolicy.Event
        switch type {
        case .began:
            event = .began
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            event = .ended(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return
        }
        switch policy.handle(event, isPlaying: player.isPlaying) {
        case .pause:
            player.pause()
        case .resume:
            player.resume()
        case .nothing:
            break
        }
    }
}
