import Foundation
import Observation
import UIKit
import NSMCore

@MainActor
@Observable
final class UpdateChecker {
    private(set) var available: UpdateManifest?
    private(set) var checking = false

    @ObservationIgnored private var lastCheck: Date?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    func check(force: Bool = false) async {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 6 * 3600 {
            return
        }
        checking = true
        defer { checking = false }
        guard let url = URL(string: "https://music.nodeshift.space/app/update/files/ios"),
              let manifest = try? await Net.json(url, as: UpdateManifest.self) else {
            return
        }
        lastCheck = Date()
        let system = UIDevice.current.systemVersion
        if UpdateCheck.isNewer(manifest, currentVersion: currentVersion, currentBuild: currentBuild),
           UpdateCheck.meetsMinimumOS(manifest, current: system) {
            available = manifest
        } else {
            available = nil
        }
    }

    func openDownloadPage() {
        guard let url = URL(string: "https://music.nodeshift.space/app/files/ios") else { return }
        UIApplication.shared.open(url)
    }
}
