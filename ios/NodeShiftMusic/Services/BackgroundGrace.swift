import UIKit

@MainActor
final class BackgroundGrace {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin(_ name: String) {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        let finished = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(finished)
    }
}
