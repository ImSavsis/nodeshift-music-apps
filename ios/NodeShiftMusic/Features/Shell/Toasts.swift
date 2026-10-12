import SwiftUI
import Observation

@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let text: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    private(set) var toasts: [Toast] = []

    func show(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let toast = Toast(text: text, actionTitle: actionTitle, action: action)
        withAnimation(Motion.expoOut(0.22)) {
            toasts.append(toast)
            if toasts.count > 3 {
                toasts.removeFirst(toasts.count - 3)
            }
        }
        let lifetime: UInt64 = actionTitle == nil ? 3_000_000_000 : 6_000_000_000
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: lifetime)
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID) {
        withAnimation(Motion.expoOut(0.22)) {
            toasts.removeAll { $0.id == id }
        }
    }
}

struct ToastHost: View {
    @Environment(ToastCenter.self) private var center
    @Environment(\.bottomInset) private var bottomInset
    @Environment(\.s) private var s

    var body: some View {
        VStack(spacing: s(8)) {
            Spacer()
            ForEach(center.toasts) { toast in
                HStack(spacing: s(12)) {
                    Text(toast.text)
                        .font(.nsm(.interMedium, s(13.5)))
                        .foregroundStyle(Palette.white)
                        .multilineTextAlignment(.leading)
                    if let title = toast.actionTitle, let action = toast.action {
                        Button {
                            action()
                            center.dismiss(toast.id)
                        } label: {
                            Text(title)
                                .font(.nsm(.interSemibold, s(13.5)))
                                .foregroundStyle(Palette.white)
                                .underline()
                        }
                        .buttonStyle(PressStyle(pressedOpacity: 0.6))
                    }
                }
                .padding(.horizontal, s(18))
                .padding(.vertical, s(12))
                .background(Palette.toast, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
                .floatShadow()
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    )
                )
            }
        }
        .frame(maxWidth: min(s(420), .infinity))
        .padding(.horizontal, s(16))
        .padding(.bottom, bottomInset + s(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(!center.toasts.isEmpty)
    }
}
