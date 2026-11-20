import SwiftUI

struct AutoMixIcon: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { context, canvasSize in
            let k = min(canvasSize.width, canvasSize.height) / 24
            let left = Path(ellipseIn: CGRect(x: 4.1 * k, y: 7 * k, width: 10 * k, height: 10 * k))
            let right = Path(ellipseIn: CGRect(x: 9.9 * k, y: 7 * k, width: 10 * k, height: 10 * k))
            context.stroke(left, with: .foreground, style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round))
            context.stroke(right, with: .foreground, style: StrokeStyle(lineWidth: 2.35 * k, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AutoMixToggle: View {
    var size: CGFloat = 36
    var iconSize: CGFloat = 18
    var glass = false
    @Environment(PlayerStore.self) private var player
    @Environment(\.s) private var s

    var body: some View {
        let active = player.autoMix
        Button {
            player.toggleAutoMix()
        } label: {
            AutoMixIcon(size: s(iconSize))
                .foregroundStyle(active ? Palette.white : Palette.dim)
                .frame(width: s(size), height: s(size))
                .glassSurface(Circle(), interactive: true, enabled: glass)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(pressedOpacity: 0.6))
        .animation(.easeOut(duration: 0.2), value: active)
        .accessibilityLabel("Автомикс")
    }
}
