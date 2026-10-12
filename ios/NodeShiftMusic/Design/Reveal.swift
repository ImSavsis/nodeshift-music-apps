import SwiftUI

struct RevealModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var delay: Double {
        switch index {
        case 0: return 0
        case 1: return 0.04
        case 2: return 0.08
        case 3: return 0.12
        default: return 0.16
        }
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 4)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                if shown {
                    return
                }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Motion.expoOut(0.42).delay(delay)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func reveal(_ index: Int = 0) -> some View {
        modifier(RevealModifier(index: index))
    }
}

struct StaggerModifier: ViewModifier {
    let index: Int
    var rise: CGFloat = 16
    var step: Double = 0.04
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : rise)
            .onAppear {
                if shown {
                    return
                }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Motion.spring.delay(min(Double(index), 14) * step)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func stagger(_ index: Int, rise: CGFloat = 16, step: Double = 0.04) -> some View {
        modifier(StaggerModifier(index: index, rise: rise, step: step))
    }
}
