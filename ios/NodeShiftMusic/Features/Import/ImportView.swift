import SwiftUI
import UniformTypeIdentifiers

private enum PickerMode {
    case files
    case folders
    case archives

    var types: [UTType] {
        switch self {
        case .files:
            var list: [UTType] = [.audio]
            for ext in ImportScanner.audioExtensions {
                if let type = UTType(filenameExtension: ext) {
                    list.append(type)
                }
            }
            return list
        case .folders:
            return [.folder]
        case .archives:
            var list: [UTType] = [.zip]
            if let sevenZip = UTType(filenameExtension: "7z") {
                list.append(sevenZip)
            }
            return list
        }
    }
}

struct ImportRow: View {
    let item: ImportItem
    @Environment(ImportManager.self) private var importer
    @Environment(\.s) private var s

    private var subtitle: (text: String, color: Color) {
        switch item.state {
        case .waiting:
            return ("В очереди", Palette.dim)
        case let .working(text):
            return (text + "…", Palette.muted)
        case .done:
            return ([item.artist, "Готово"].compactMap { $0 }.joined(separator: " · "), Palette.dim)
        case let .duplicate(_, kind, better):
            let base = kind == "sameTrack" ? "Такой трек уже есть" : "Похожий трек уже есть"
            return (better ? base + " (здесь качество лучше)" : base, Palette.warn)
        case let .skipped(text):
            return (text, Palette.dim)
        case let .failed(text):
            return (text, Palette.danger)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: s(10)) {
            HStack(spacing: s(12)) {
                CoverArt(coverName: item.coverName, live: false, maxPixel: 120)
                    .frame(width: s(40), height: s(40))
                VStack(alignment: .leading, spacing: s(2)) {
                    Text(item.title ?? item.name)
                        .font(.nsm(.interMedium, s(14)))
                        .foregroundStyle(Palette.white)
                        .lineLimit(1)
                    Text(subtitle.text)
                        .font(.nsm(.monoRegular, s(11)))
                        .foregroundStyle(subtitle.color)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                switch item.state {
                case .done:
                    Icon(name: .check, size: s(18), stroke: 2)
                        .foregroundStyle(Palette.ok)
                case .failed:
                    Icon(name: .circleAlert, size: s(18), stroke: 2)
                        .foregroundStyle(Palette.danger)
                case .working:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Palette.white)
                        .scaleEffect(0.8)
                default:
                    EmptyView()
                }
            }
            if case .duplicate = item.state {
                FlowLayout(spacing: s(8), lineSpacing: s(8)) {
                    Chip(title: "Пропустить", active: false) {
                        importer.decide(item.id, .skip)
                    }
                    Chip(title: "Оставить оба", active: false) {
                        importer.decide(item.id, .keepBoth)
                    }
                    Chip(title: "Заменить", active: false) {
                        importer.decide(item.id, .replace)
                    }
                }
            }
        }
        .padding(s(12))
        .surfaceBox(s(Radius.tile))
    }
}

struct ImportView: View {
    @Environment(ImportManager.self) private var importer
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openTab) private var openTab
    @Environment(\.s) private var s
    @State private var mode: PickerMode = .files
    @State private var picking = false

    var body: some View {
        ScreenScroll {
            PageHeader(
                title: "Импорт",
                subtitle: "mp3, flac, wav, ogg, m4a, архивы и папки. Можно сразу много, всё делается на телефоне."
            )
            .reveal(0)
            dropZone.reveal(1)
            FlowLayout(spacing: s(10), lineSpacing: s(10)) {
                Button {
                    open(.files)
                } label: {
                    ButtonLabel(title: "Файлы", icon: .fileMusic)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    open(.folders)
                } label: {
                    ButtonLabel(title: "Папку", icon: .folderUp)
                }
                .buttonStyle(GhostButtonStyle())
                Button {
                    open(.archives)
                } label: {
                    ButtonLabel(title: "Архив", icon: .archive)
                }
                .buttonStyle(GhostButtonStyle())
                Button {
                    importer.add(urls: [AppPaths.inboxDir])
                } label: {
                    ButtonLabel(title: "Из папки приложения", icon: .hardDrive)
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.top, s(18))
            .reveal(2)
            Text("Можно положить файлы в Файлы → На iPhone → NS Music → Import и нажать «Из папки приложения».")
                .font(.nsm(.interRegular, s(12.5)))
                .foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, s(12))
                .reveal(3)
            if !importer.items.isEmpty {
                queue.padding(.top, s(24))
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: mode.types, allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                importer.add(urls: urls)
            case .failure:
                toasts.show("Не получилось открыть выбор")
            }
        }
    }

    private func open(_ target: PickerMode) {
        mode = target
        picking = true
    }

    private var dropZone: some View {
        VStack(spacing: s(12)) {
            Icon(name: .uploadCloud, size: s(28), stroke: 1.6)
                .foregroundStyle(Palette.muted)
            Text("Выбери файлы, папки или архивы")
                .font(.nsm(.interMedium, s(14)))
                .foregroundStyle(Palette.white)
                .multilineTextAlignment(.center)
            Text("НАЗВАНИЕ, ИСПОЛНИТЕЛЬ, АЛЬБОМ И ОБЛОЖКА ПОДТЯНУТСЯ САМИ")
                .font(.nsm(.monoRegular, s(10.5)))
                .tracking(0.12 * s(10.5))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, s(32))
        .padding(.horizontal, s(20))
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: s(Radius.card), style: .continuous)
                .strokeBorder(Palette.line2, style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
        )
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: s(8)) {
            HStack {
                Text(statusLine)
                    .font(.nsm(.interRegular, s(12)))
                    .foregroundStyle(Palette.muted)
                Spacer()
                if importer.pendingDuplicates > 0 {
                    Button("Пропустить все дубликаты") {
                        importer.skipAllDuplicates()
                    }
                    .font(.nsm(.interMedium, s(12)))
                    .foregroundStyle(Palette.white)
                } else if !importer.isRunning {
                    Button("Убрать завершённые") {
                        withAnimation(Motion.expoOut(0.3)) {
                            importer.clearFinished()
                        }
                    }
                    .font(.nsm(.interMedium, s(12)))
                    .foregroundStyle(Palette.dim)
                }
            }
            LazyVStack(spacing: s(8)) {
                ForEach(importer.items) { item in
                    ImportRow(item: item)
                }
            }
            if !importer.isRunning && importer.summary.added > 0 {
                SurfaceCard(padding: 16) {
                    HStack {
                        Text("Добавлено треков: \(importer.summary.added)")
                            .font(.nsm(.interMedium, s(14)))
                            .foregroundStyle(Palette.ok)
                        Spacer()
                        Button {
                            openTab(.tracks)
                        } label: {
                            ButtonLabel(title: "К трекам")
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(.top, s(8))
            }
        }
    }

    private var statusLine: String {
        let summary = importer.summary
        var parts = ["\(importer.items.count) в списке"]
        if summary.added > 0 {
            parts.append("добавлено \(summary.added)")
        }
        if summary.duplicates > 0 {
            parts.append("дубликатов \(summary.duplicates)")
        }
        if summary.failed > 0 {
            parts.append("ошибок \(summary.failed)")
        }
        if summary.ignored > 0 {
            parts.append("лишних файлов \(summary.ignored)")
        }
        return parts.joined(separator: " · ")
    }
}
