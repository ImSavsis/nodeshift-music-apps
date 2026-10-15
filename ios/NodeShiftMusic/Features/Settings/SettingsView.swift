import SwiftUI

struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Environment(\.s) private var s

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: s(3)) {
                Text(title)
                    .font(.nsm(.interMedium, s(14)))
                    .foregroundStyle(Palette.white)
                Text(detail)
                    .font(.nsm(.interRegular, s(12.5)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color(hex: 0x3FB950))
    }
}

struct SettingsView: View {
    var onClose: () -> Void
    @Environment(SiteSession.self) private var site
    @Environment(LibraryStore.self) private var library
    @Environment(EnrichmentService.self) private var enrichment
    @Environment(UpdateChecker.self) private var updates
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openStorage) private var openStorage
    @Environment(\.s) private var s
    @State private var guestName = RoomStore.savedGuestName()

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScreenScroll {
                BackButton(action: onClose)
                PageHeader(title: "Настройки", subtitle: "Звук, анимации, аккаунт и библиотека")
                    .reveal(0)
                accountCard.reveal(1)
                soundCard.reveal(2)
                motionCard.reveal(3)
                appearanceCard.reveal(3)
                libraryCard.reveal(4)
                roomCard.reveal(4)
                aboutCard.reveal(4)
            }
        }
    }

    private var accountCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(12)) {
                Eyebrow(text: "Аккаунт NodeShift", bottom: 0)
                if let user = site.user {
                    Text(user.handle.map { "@\($0)" } ?? user.username ?? "Вы вошли")
                        .font(.nsm(.unboundedSemibold, s(16)))
                        .foregroundStyle(Palette.white)
                    Button {
                        site.logout()
                    } label: {
                        ButtonLabel(title: "Выйти", icon: .logOut)
                    }
                    .buttonStyle(GhostButtonStyle())
                } else {
                    Text("Войди, чтобы ставить лайки на сайт, пользоваться вишлистом и создавать комнаты.")
                        .font(.nsm(.interRegular, s(13.5)))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { _ = await site.login() }
                    } label: {
                        ButtonLabel(title: site.isBusy ? "Открываем…" : "Войти", icon: .logIn)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(site.isBusy)
                    if let error = site.lastError {
                        Text(error)
                            .font(.nsm(.interRegular, s(12.5)))
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
        }
        .padding(.bottom, s(14))
    }

    private var soundCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(14)) {
                Eyebrow(text: "Звук", bottom: 0)
                SoundPicker()
                Text("Dolby Atmos играет из файлов E-AC-3 (.m4a, .ec3), которые ты добавил на телефон. Lossless — оригиналы FLAC с сайта.")
                    .font(.nsm(.interRegular, s(12.5)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, s(14))
    }

    private var motionCard: some View {
        let settings = SoundSettings.shared
        return SurfaceCard {
            VStack(alignment: .leading, spacing: s(14)) {
                Eyebrow(text: "Анимации", bottom: 0)
                SettingToggle(
                    title: "Анимированные обложки",
                    detail: "Видео-обложки в списках, на весь экран в плеере и на экране блокировки",
                    isOn: Binding(get: { settings.motionCovers }, set: { settings.setMotionCovers($0) })
                )
                SettingToggle(
                    title: "Живой фон и обложки",
                    detail: "Плавное движение фона, обложек и пятен света",
                    isOn: Binding(get: { settings.ambientMotion }, set: { settings.setAmbientMotion($0) })
                )
                SettingToggle(
                    title: "Показывать в Discord",
                    detail: "Что ты слушаешь, с обложкой. Появится в Discord на компьютере, где запущено NS Music для Windows",
                    isOn: Binding(get: { settings.discordPresence }, set: { settings.setDiscordPresence($0) })
                )
                Text("Если в iPhone включён режим уменьшения движения, анимации отключаются системой.")
                    .font(.nsm(.interRegular, s(12)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, s(14))
    }

    private var appearanceCard: some View {
        let settings = SoundSettings.shared
        return SurfaceCard {
            VStack(alignment: .leading, spacing: s(14)) {
                Eyebrow(text: "Оформление", bottom: 0)
                SettingToggle(
                    title: "Жидкое стекло",
                    detail: "Стеклянная нижняя панель и мини-плеер в стиле iOS 26. На старых версиях iOS остаётся обычное размытие",
                    isOn: Binding(get: { settings.liquidGlass }, set: { settings.setLiquidGlass($0) })
                )
                Text("Цвет интерфейса")
                    .font(.nsm(.interMedium, s(14)))
                    .foregroundStyle(Palette.white)
                FlowLayout(spacing: s(12), lineSpacing: s(12)) {
                    ForEach(Accent.allCases, id: \.self) { item in
                        Button {
                            withAnimation(Motion.expoOut(0.25)) {
                                settings.setAccent(item)
                            }
                        } label: {
                            Circle()
                                .fill(LinearGradient(colors: [item.top, item.bottom], startPoint: .top, endPoint: .bottom))
                                .frame(width: s(36), height: s(36))
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: settings.accent == item ? 2.5 : 0)
                                        .padding(-s(4))
                                )
                                .padding(s(4))
                        }
                        .buttonStyle(PressStyle(pressedOpacity: 0.8))
                        .accessibilityLabel(item.title)
                    }
                }
                Text("Удерживай панель внизу и веди пальцем, чтобы переключать вкладки. Свайп влево-вправо листает вкладки, а в плеере треки.")
                    .font(.nsm(.interRegular, s(12)))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, s(14))
    }

    private var libraryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(12)) {
                Eyebrow(text: "Библиотека", bottom: 0)
                Text("\(pluralTracks(library.tracks.count)) на телефоне")
                    .font(.nsm(.interMedium, s(14)))
                    .foregroundStyle(Palette.white)
                if enrichment.libraryRunning {
                    VStack(alignment: .leading, spacing: s(6)) {
                        ProgressView(value: Double(enrichment.libraryDone), total: Double(max(1, enrichment.libraryTotal)))
                            .tint(Palette.white)
                        Text("Ищем обложки и анимации: \(enrichment.libraryDone) из \(enrichment.libraryTotal), найдено \(enrichment.libraryFound)")
                            .font(.nsm(.monoRegular, s(11)))
                            .foregroundStyle(Palette.dim)
                    }
                } else {
                    Button {
                        Task { await enrichment.enrichLibrary(force: true) }
                    } label: {
                        ButtonLabel(title: "Найти обложки и анимации", icon: .sparkles)
                    }
                    .buttonStyle(GhostButtonStyle())
                    Text("Для всех треков без обложки и альбомов без анимированной обложки. Идёт в фоне.")
                        .font(.nsm(.interRegular, s(12)))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: openStorage) {
                    ButtonLabel(title: "Хранилище и скачивание", icon: .hardDrive)
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.bottom, s(14))
    }

    private var roomCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(10)) {
                Eyebrow(text: "Слушать вместе", bottom: 0)
                Text("Имя, под которым ты заходишь в комнаты без входа через сайт.")
                    .font(.nsm(.interRegular, s(12.5)))
                    .foregroundStyle(Palette.dim)
                TextField("", text: $guestName, prompt: Text("Имя").foregroundStyle(Palette.dim))
                    .font(.nsm(.interRegular, s(14)))
                    .foregroundStyle(Palette.white)
                    .tint(Palette.white)
                    .autocorrectionDisabled()
                    .padding(.horizontal, s(16))
                    .frame(height: s(40))
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 1))
                    .onChange(of: guestName) { _, value in
                        RoomStore.saveGuestName(value)
                    }
            }
        }
        .padding(.bottom, s(14))
    }

    private var aboutCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: s(6)) {
                Eyebrow(text: "О приложении", bottom: 4)
                Text("NS Music · версия \(updates.currentVersion) (\(updates.currentBuild))")
                    .font(.nsm(.interMedium, s(14)))
                    .foregroundStyle(Palette.white)
                Text("made by savsis with <3")
                    .font(.nsm(.monoRegular, s(11)))
                    .foregroundStyle(Palette.dim)
            }
        }
    }
}
