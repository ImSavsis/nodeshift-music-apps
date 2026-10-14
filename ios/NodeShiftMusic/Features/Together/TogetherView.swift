import SwiftUI

struct TogetherView: View {
    var onClose: () -> Void
    @Environment(RoomStore.self) private var room
    @Environment(SiteSession.self) private var site
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.s) private var s
    @State private var codeInput = ""
    @State private var guestName = RoomStore.savedGuestName()
    @State private var busy = false
    @State private var scanning = false
    @State private var bumping = false
    @State private var bump = BumpSession()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if !bumping {
                        onClose()
                    }
                }
            sheet
            if scanning {
                scanner
                    .transition(.opacity)
            }
        }
        .onDisappear {
            bump.stop()
        }
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: s(18)) {
            HStack {
                Text("Слушать вместе")
                    .font(.nsm(.unboundedSemibold, s(16)))
                    .tracking(-0.025 * s(16))
                    .foregroundStyle(Palette.white)
                Spacer()
                IconToggle(icon: .x, size: 36, iconSize: 17, action: onClose)
            }
            if bumping {
                bumpContent
            } else if room.code != nil {
                liveContent
            } else {
                startContent
            }
        }
        .padding(.horizontal, s(18))
        .padding(.bottom, s(24))
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Palette.line2)
                .frame(width: s(36), height: s(4))
                .padding(.top, s(10))
                .padding(.bottom, s(8))
            ViewThatFits(in: .vertical) {
                inner
                ScrollView {
                    inner
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.88, alignment: .top)
        .background(Palette.modal)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card)))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: s(Radius.card), topTrailingRadius: s(Radius.card))
                .strokeBorder(Palette.line2, lineWidth: 1)
        }
        .transition(.move(edge: .bottom))
    }

    private var startContent: some View {
        VStack(alignment: .leading, spacing: s(16)) {
            Text("Одна музыка на всех телефонах: создай комнату и покажи QR, введи код или просто коснись телефонов друг о друга.")
                .font(.nsm(.interRegular, s(13.5)))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if site.isLoggedIn {
                Button {
                    Task {
                        busy = true
                        await room.create()
                        busy = false
                    }
                } label: {
                    ButtonLabel(title: busy ? "Создаём…" : "Создать комнату", icon: .plus)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            } else {
                VStack(alignment: .leading, spacing: s(10)) {
                    Text("Чтобы создать комнату, войди через сайт. Присоединиться по коду можно и без входа.")
                        .font(.nsm(.interRegular, s(12.5)))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { _ = await site.login() }
                    } label: {
                        ButtonLabel(title: site.isBusy ? "Открываем…" : "Войти", icon: .logIn)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(site.isBusy)
                }
            }
            VStack(alignment: .leading, spacing: s(10)) {
                Eyebrow(text: "Войти в комнату", bottom: 0)
                HStack(spacing: s(10)) {
                    TextField("", text: $codeInput, prompt: Text("КОД").foregroundStyle(Palette.dim))
                        .font(.nsm(.monoSemibold, s(18)))
                        .tracking(0.2 * s(18))
                        .foregroundStyle(Palette.white)
                        .tint(Palette.white)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(joinTyped)
                        .padding(.horizontal, s(16))
                        .frame(height: s(44))
                        .background(Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
                        .onChange(of: codeInput) { _, value in
                            let trimmed = String(value.uppercased().filter { !$0.isWhitespace }.prefix(40))
                            if trimmed != value {
                                codeInput = trimmed
                            }
                        }
                    Button(action: joinTyped) {
                        ButtonLabel(title: "Войти")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(busy || codeInput.count < 4)
                }
                if !site.isLoggedIn {
                    TextField("", text: $guestName, prompt: Text("Твоё имя в комнате").foregroundStyle(Palette.dim))
                        .font(.nsm(.interRegular, s(14)))
                        .foregroundStyle(Palette.white)
                        .tint(Palette.white)
                        .autocorrectionDisabled()
                        .padding(.horizontal, s(16))
                        .frame(height: s(40))
                        .background(Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
                }
            }
            HStack(spacing: s(10)) {
                Button {
                    withAnimation(Motion.expoOut(0.3)) {
                        scanning = true
                    }
                } label: {
                    ButtonLabel(title: "Сканировать QR", icon: .camera)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
                Button(action: startBump) {
                    ButtonLabel(title: "Коснуться", icon: .smartphone)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
            }
            if let notice = room.notice {
                Text(notice)
                    .font(.nsm(.interRegular, s(12.5)))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: s(16)) {
            HStack(spacing: s(8)) {
                Circle()
                    .fill(statusColor)
                    .frame(width: s(8), height: s(8))
                Text(statusText)
                    .font(.nsm(.monoRegular, s(12)))
                    .foregroundStyle(Palette.muted)
            }
            if let code = room.code {
                HStack {
                    Text(code)
                        .font(.nsm(.monoSemibold, s(30)))
                        .tracking(0.3 * s(30))
                        .foregroundStyle(Palette.white)
                    Spacer()
                    IconToggle(icon: .copy, size: 40, iconSize: 18) {
                        UIPasteboard.general.string = code
                        toasts.show("Код скопирован")
                    }
                }
                if let link = room.link {
                    HStack {
                        Spacer()
                        QRCodeCard(text: link.absoluteString, side: 190)
                        Spacer()
                    }
                    Text("Покажи QR второму телефону, отправь ссылку или продиктуй код. Музыка пойдёт синхронно на всех.")
                        .font(.nsm(.interRegular, s(12.5)))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: link) {
                        ButtonLabel(title: "Поделиться ссылкой", icon: .share)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
            VStack(alignment: .leading, spacing: s(8)) {
                Eyebrow(text: "Слушают сейчас · \(room.members.count)", bottom: 0)
                ForEach(room.members) { member in
                    HStack(spacing: s(12)) {
                        Icon(name: .userRound, size: s(16), stroke: 1.8)
                            .foregroundStyle(Palette.muted)
                            .frame(width: s(32), height: s(32))
                            .background(Palette.surface, in: Circle())
                        Text(member.name)
                            .font(.nsm(.interMedium, s(14)))
                            .foregroundStyle(Palette.white)
                            .lineLimit(1)
                        Spacer()
                        if member.id == room.you {
                            Text("вы")
                                .font(.nsm(.monoRegular, s(11)))
                                .foregroundStyle(Palette.dim)
                        }
                    }
                }
            }
            Button {
                room.leave()
            } label: {
                ButtonLabel(title: "Выйти из комнаты", icon: .logOut)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var bumpContent: some View {
        VStack(spacing: s(18)) {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        let phase = (time * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .strokeBorder(Color.white.opacity((1 - phase) * 0.5), lineWidth: 2)
                            .scaleEffect(0.35 + phase * 0.9)
                    }
                    Icon(name: .smartphone, size: s(34), stroke: 1.6)
                        .foregroundStyle(Palette.white)
                }
                .frame(width: s(210), height: s(210))
            }
            Text(bumpTitle)
                .font(.nsm(.unboundedSemibold, s(15)))
                .foregroundStyle(Palette.white)
                .multilineTextAlignment(.center)
            Text(bumpSubtitle)
                .font(.nsm(.interRegular, s(13)))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if case .listening = bump.phase {
                Button {
                    bump.triggerManually()
                } label: {
                    ButtonLabel(title: "Нажать одновременно", icon: .radio)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
            }
            Button {
                stopBump()
            } label: {
                ButtonLabel(title: "Отмена")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .onChange(of: bump.phase) { _, phase in
            if case .failed = phase {
                return
            }
            if phase == .idle {
                bumping = false
            }
        }
    }

    private var bumpTitle: String {
        switch bump.phase {
        case .idle, .listening: return "Приложи телефоны друг к другу"
        case .matching: return "Ищем второй телефон…"
        case let .joining(name): return "Подключаем: \(name)"
        case .failed: return "Не получилось"
        }
    }

    private var bumpSubtitle: String {
        switch bump.phase {
        case .idle, .listening:
            return bump.detectorAvailable
                ? "Слегка стукни телефонами друг о друга. На втором телефоне тоже открой «Слушать вместе → Коснуться»."
                : "Датчик движения недоступен. Нажми кнопку одновременно на обоих телефонах."
        case .matching: return "Секунду"
        case .joining: return "Заходим в общую комнату"
        case let .failed(text): return text
        }
    }

    private var statusText: String {
        switch room.status {
        case .idle: return "Не в комнате"
        case .connecting: return "Подключаемся…"
        case .live: return "Вы в комнате"
        case .reconnecting: return "Связь пропала, переподключаемся…"
        }
    }

    private var statusColor: Color {
        switch room.status {
        case .live: return Palette.ok
        case .reconnecting: return Palette.warn
        default: return Palette.dim
        }
    }

    private var scanner: some View {
        ZStack(alignment: .top) {
            QRScannerView { text in
                handleScanned(text)
            } onDenied: {
                scanning = false
                toasts.show("Нет доступа к камере. Разреши его в настройках iPhone")
            }
            .ignoresSafeArea()
            VStack {
                HStack {
                    Text("Наведи на QR комнаты")
                        .font(.nsm(.interSemibold, s(14)))
                        .foregroundStyle(Palette.white)
                    Spacer()
                    IconToggle(icon: .x, size: 40, iconSize: 18) {
                        withAnimation(Motion.expoOut(0.3)) {
                            scanning = false
                        }
                    }
                }
                .padding(.horizontal, s(18))
                .padding(.top, s(54))
                Spacer()
            }
            .background(
                LinearGradient(colors: [Color.black.opacity(0.7), Color.clear], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            )
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func handleScanned(_ text: String) {
        guard let code = RoomStore.normalize(text) else {
            toasts.show("Это не QR комнаты")
            scanning = false
            return
        }
        scanning = false
        Task {
            busy = true
            _ = await room.joinChecked(code: code, name: guestName)
            busy = false
        }
    }

    private func joinTyped() {
        guard !busy else { return }
        RoomStore.saveGuestName(guestName)
        Task {
            busy = true
            let joined = await room.joinChecked(code: codeInput, name: guestName)
            busy = false
            if joined {
                codeInput = ""
            }
        }
    }

    private func startBump() {
        withAnimation(Motion.expoOut(0.3)) {
            bumping = true
        }
        bump.start(site: site) { code in
            Task {
                _ = await room.joinChecked(code: code, name: guestName)
                bumping = false
            }
        }
    }

    private func stopBump() {
        bump.stop()
        withAnimation(Motion.expoOut(0.3)) {
            bumping = false
        }
    }
}
