import CoreMotion
import Observation
import SwiftUI
import UIKit

struct GlassOrFill<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false
    var tint: Color?
    var fallback: Color = .clear
    var stroke = false
    var enabled = true

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if SoundSettings.shared.liquidGlass, #available(iOS 26.0, *) {
            content.glassEffect(Self.glass(interactive: interactive, tint: tint), in: shape)
        } else if stroke {
            content
                .background(fallback, in: shape)
                .overlay(shape.strokeBorder(Palette.line2, lineWidth: 1))
        } else {
            content.background(fallback, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private static func glass(interactive: Bool, tint: Color?) -> Glass {
        var value = Glass.regular
        if let tint {
            value = value.tint(tint)
        }
        if interactive {
            value = value.interactive()
        }
        return value
    }
}

struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if SoundSettings.shared.liquidGlass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

@MainActor
@Observable
final class TiltMotion {
    static let shared = TiltMotion()

    private(set) var x: Double = 0
    private(set) var y: Double = 0
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            let roll = attitude.roll
            let pitch = attitude.pitch
            MainActor.assumeIsolated {
                self?.update(roll: roll, pitch: pitch)
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        x = 0
        y = 0
    }

    private func update(roll: Double, pitch: Double) {
        let targetX = max(-1, min(1, roll / 0.5))
        let targetY = max(-1, min(1, (pitch - 0.9) / 0.5))
        x = x * 0.85 + targetX * 0.15
        y = y * 0.85 + targetY * 0.15
    }
}

struct TiltParallax: ViewModifier {
    var depth: CGFloat
    var degrees: Double
    @State private var started = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var allowed: Bool {
        SoundSettings.shared.ambientMotion && !reduceMotion
    }

    func body(content: Content) -> some View {
        let tilt = TiltMotion.shared
        content
            .rotation3DEffect(.degrees(-tilt.y * degrees), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(tilt.x * degrees), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .offset(x: CGFloat(tilt.x) * depth, y: CGFloat(tilt.y) * depth)
            .onAppear {
                if allowed, !started {
                    started = true
                    TiltMotion.shared.start()
                }
            }
            .onDisappear {
                if started {
                    started = false
                    TiltMotion.shared.stop()
                }
            }
    }
}

extension View {
    func glassSurface<S: InsettableShape>(
        _ shape: S,
        interactive: Bool = false,
        tint: Color? = nil,
        fallback: Color = .clear,
        stroke: Bool = false,
        enabled: Bool = true
    ) -> some View {
        modifier(GlassOrFill(shape: shape, interactive: interactive, tint: tint, fallback: fallback, stroke: stroke, enabled: enabled))
    }

    func scrollFade() -> some View {
        scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85)), axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.35)
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .blur(radius: phase.isIdentity ? 0 : 2.5)
        }
    }

    func tapFeedback<T: Equatable>(_ trigger: T) -> some View {
        sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: trigger)
    }

    func bounceOnChange<T: Equatable>(_ trigger: T) -> some View {
        keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.32, duration: 0.12)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
        }
    }

    func tiltParallax(depth: CGFloat = 6, degrees: Double = 7) -> some View {
        modifier(TiltParallax(depth: depth, degrees: degrees))
    }
}
