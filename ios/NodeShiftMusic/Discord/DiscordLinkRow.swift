import SwiftUI

struct DiscordLinkRow: View {
    @Environment(\.s) private var s

    private var link: DiscordLink {
        DiscordLink.shared
    }

    var body: some View {
        if link.state != .unavailable {
            VStack(alignment: .leading, spacing: s(10)) {
                Text(detail)
                    .font(.nsm(.interRegular, s(12)))
                    .foregroundStyle(isFailed ? Palette.white : Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: act) {
                    ButtonLabel(title: title)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(link.state == .linking)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = link.state {
            return true
        }
        return false
    }

    private var title: String {
        switch link.state {
        case .linked:
            return "Отвязать Discord"
        case .linking:
            return "Ждём Discord…"
        case .failed:
            return "Попробовать ещё раз"
        default:
            return "Привязать Discord"
        }
    }

    private var detail: String {
        switch link.state {
        case .linked:
            return "Привязано. Статус «Слушает» показывается прямо с телефона, пока играет музыка, компьютер не нужен."
        case .linking:
            return "Открываем Discord для входа."
        case let .failed(message):
            return message
        default:
            return "Привяжи Discord, и статус будет показываться с телефона без компьютера и сервера."
        }
    }

    private func act() {
        if link.state == .linked {
            link.unlink()
        } else {
            Task { await link.link() }
        }
    }
}
