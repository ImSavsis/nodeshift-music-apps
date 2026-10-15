import Foundation
import Network
import Observation

enum StreamQuality: String, CaseIterable, Sendable {
    case auto
    case lossless
    case compact

    var title: String {
        switch self {
        case .auto: return "Авто"
        case .lossless: return "Lossless"
        case .compact: return "Экономия"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Без потерь по Wi-Fi, AAC по мобильной сети"
        case .lossless: return "Оригинал без потерь (FLAC и т.д.) везде"
        case .compact: return "AAC 192 кбит/с: стартует сразу, мало трафика"
        }
    }
}

enum AtmosMode: String, CaseIterable, Sendable {
    case auto
    case on
    case off

    var title: String {
        switch self {
        case .auto: return "Авто"
        case .on: return "Всегда"
        case .off: return "Выкл"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Пространственный звук, когда его поддерживают наушники или динамики"
        case .on: return "Всегда отдавать многоканальный звук системе"
        case .off: return "Обычное стерео без пространственного звука"
        }
    }
}

final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var unmetered = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.unmetered = !path.isExpensive && !path.isConstrained
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "space.nodeshift.music.network"))
    }

    var isUnmetered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return unmetered
    }
}

@MainActor
@Observable
final class SoundSettings {
    static let shared = SoundSettings()

    private(set) var streamQuality: StreamQuality
    private(set) var atmosMode: AtmosMode
    private(set) var motionCovers: Bool
    private(set) var ambientMotion: Bool
    private(set) var discordPresence: Bool
    private(set) var accent: Accent
    private(set) var liquidGlass: Bool

    private init() {
        discordPresence = UserDefaults.standard.object(forKey: "nsm_discord_presence") as? Bool ?? true
        accent = Accent(rawValue: UserDefaults.standard.string(forKey: "nsm_accent") ?? "") ?? .silver
        liquidGlass = UserDefaults.standard.object(forKey: "nsm_liquid_glass") as? Bool ?? true
        let defaults = UserDefaults.standard
        streamQuality = StreamQuality(rawValue: defaults.string(forKey: "nsm_stream_quality") ?? "") ?? .auto
        atmosMode = AtmosMode(rawValue: defaults.string(forKey: "nsm_atmos_mode") ?? "") ?? .auto
        motionCovers = defaults.object(forKey: "nsm_motion_covers") as? Bool ?? true
        ambientMotion = defaults.object(forKey: "nsm_ambient_motion") as? Bool ?? true
        _ = NetworkMonitor.shared
    }

    func setStreamQuality(_ value: StreamQuality) {
        streamQuality = value
        UserDefaults.standard.set(value.rawValue, forKey: "nsm_stream_quality")
    }

    func setAtmosMode(_ value: AtmosMode) {
        atmosMode = value
        UserDefaults.standard.set(value.rawValue, forKey: "nsm_atmos_mode")
    }

    func setMotionCovers(_ value: Bool) {
        motionCovers = value
        UserDefaults.standard.set(value, forKey: "nsm_motion_covers")
    }

    func setAmbientMotion(_ value: Bool) {
        ambientMotion = value
        UserDefaults.standard.set(value, forKey: "nsm_ambient_motion")
    }

    func setAccent(_ value: Accent) {
        accent = value
        UserDefaults.standard.set(value.rawValue, forKey: "nsm_accent")
    }

    func setLiquidGlass(_ value: Bool) {
        liquidGlass = value
        UserDefaults.standard.set(value, forKey: "nsm_liquid_glass")
    }

    func setDiscordPresence(_ value: Bool) {
        discordPresence = value
        UserDefaults.standard.set(value, forKey: "nsm_discord_presence")
    }

    func wantsLossless() -> Bool {
        switch streamQuality {
        case .lossless: return true
        case .compact: return false
        case .auto: return NetworkMonitor.shared.isUnmetered
        }
    }
}

struct SoundInfo: Equatable, Sendable {
    var label: String
    var detail: String
    var isLossless: Bool
    var isAtmos: Bool
}

enum AudioFormats {
    static let lossless: Set<String> = ["flac", "wav", "alac", "aiff", "aif", "ape", "wv"]
    static let systemDecoded: Set<String> = ["atmos", "eac3", "ac3"]
    static let systemDecodedExtensions: Set<String> = ["ec3", "eac3", "ac3"]
}

extension TrackRecord {
    var usesSystemDecoder: Bool {
        !isRemote && AudioFormats.systemDecoded.contains(format.lowercased())
    }

    var isDolbyAtmos: Bool {
        format.lowercased() == "atmos"
    }

    var hasCompactVariant: Bool {
        guard let compact = streamURL, let original = losslessURL else { return false }
        return compact != original
    }

    func soundInfo(wantsLossless: Bool) -> SoundInfo {
        let kind = format.lowercased()
        if kind == "atmos" {
            return SoundInfo(label: "Dolby Atmos", detail: "E-AC-3 JOC · пространственный звук", isLossless: false, isAtmos: true)
        }
        if kind == "eac3" || kind == "ac3" {
            return SoundInfo(label: "Dolby Digital", detail: kind == "eac3" ? "E-AC-3" : "AC-3", isLossless: false, isAtmos: false)
        }
        if isRemote {
            if wantsLossless && AudioFormats.lossless.contains(kind) {
                return SoundInfo(label: "Lossless", detail: "\(kind.uppercased()) · оригинал", isLossless: true, isAtmos: false)
            }
            if hasCompactVariant {
                return SoundInfo(label: "AAC 192", detail: "поток · экономия трафика", isLossless: false, isAtmos: false)
            }
            return SoundInfo(label: kind.uppercased(), detail: "поток", isLossless: false, isAtmos: false)
        }
        if AudioFormats.lossless.contains(kind) {
            var parts: [String] = [kind.uppercased()]
            if let rate = sampleRate, rate > 0 {
                parts.append(String(format: "%.1f кГц", Double(rate) / 1000).replacingOccurrences(of: ".", with: ","))
            }
            if let depth = bitDepth, depth > 0 {
                parts.append("\(depth) бит")
            }
            let hires = (bitDepth ?? 16) > 16 || (sampleRate ?? 44_100) > 48_000
            return SoundInfo(label: hires ? "Hi-Res Lossless" : "Lossless", detail: parts.joined(separator: " · "), isLossless: true, isAtmos: false)
        }
        var parts: [String] = []
        if let bitrate = bitrateKbps, bitrate > 0 {
            parts.append("\(bitrate) кбит/с")
        }
        return SoundInfo(label: kind.uppercased(), detail: parts.joined(separator: " · "), isLossless: false, isAtmos: false)
    }
}
