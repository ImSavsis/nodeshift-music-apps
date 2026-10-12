import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                CrystalMark(size: 72)
                Text("NODESHIFT")
                    .font(.nsm(.unboundedSemibold, 15))
                    .tracking(0.14 * 15)
                    .foregroundStyle(Palette.white)
                Text(EngineProbe.summary())
                    .font(.nsm(.monoRegular, 10))
                    .foregroundStyle(Palette.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
}
