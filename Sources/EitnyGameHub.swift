import SwiftUI
import AppKit

private let mint = Color(red: 0.63, green: 0.59, blue: 1.0)
private let gold = Color(red: 0.83, green: 0.72, blue: 0.45)
private let canvasBackground = Color(red: 0.073, green: 0.077, blue: 0.083)
private let panel = Color(red: 0.112, green: 0.118, blue: 0.125)

final class BridgeModel: ObservableObject {
    @Published var checks: [String: String] = [:]
    @Published var busy = false
    @Published var status = "Проверяю готовность…"
    @Published var error: String?
    @Published var journal = ""
    @Published var currentAction = ""
    @Published var selectedTab = 0
    @Published var showLog = false
    @Published var profile: SteamProfile?
    @Published var games: [SteamGame] = []
    @Published var libraryNote = "Открой Steam и войди в свой аккаунт."
    @Published var syncing = false
    @Published var search = ""
    @Published var filter = "Все игры"
    @Published var sorting = "Название"
    @Published var syncedAt: Date?
    @Published var poePreset = "balanced"
    let dataURL: URL
    let backend: URL
    private var currentProcess: Process?
    private var authorizedDataURL: URL?

    init() {
        backend = Bundle.main.resourceURL!.appendingPathComponent("bridge.sh")
        let fm = FileManager.default
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let portableLocations = ["EitnyGameHub Data", "GwentBridge Data"].map { parent.appendingPathComponent($0) }
        let custom = ProcessInfo.processInfo.environment["EITNY_GAMEHUB_DATA"] ?? ProcessInfo.processInfo.environment["GWENT_BRIDGE_DATA"]
        let remembered = UserDefaults.standard.url(forKey: "dataDirectory")
        if let custom, custom.hasPrefix("/") {
            dataURL = URL(fileURLWithPath: custom, isDirectory: true)
        } else if let existing = portableLocations.first(where: { fm.fileExists(atPath: $0.appendingPathComponent(".portable").path) }) {
            dataURL = existing
        } else if let remembered, remembered.isFileURL, fm.fileExists(atPath: remembered.appendingPathComponent("Bottle/.configured-v1").path) {
            dataURL = remembered
        } else if fm.fileExists(atPath: home.appendingPathComponent("EitnyGameHub").path) {
            dataURL = home.appendingPathComponent("EitnyGameHub")
        } else if fm.fileExists(atPath: home.appendingPathComponent("GwentBridge").path) {
            dataURL = home.appendingPathComponent("GwentBridge")
        } else {
            dataURL = home.appendingPathComponent("EitnyGameHub")
        }
        // A locally stored preference keeps the user's library when moving the app.
        // This preference is outside the app bundle and is never part of a shared copy.
        UserDefaults.standard.set(dataURL, forKey: "dataDirectory")
        if let bookmark = UserDefaults.standard.data(forKey: "dataFolderBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale),
               url.standardizedFileURL == dataURL.standardizedFileURL,
               url.startAccessingSecurityScopedResource() { authorizedDataURL = url }
        }
        refresh()
        reloadLibrary()
    }

    var ready: Bool { checks["runtime"] == "ready" && checks["bottle"] == "ready" && checks["steam"] == "ready" }
    var poeReady: Bool { checks["poe_environment"] == "ready" }
    var poeInstalled: Bool { checks["poe"] == "present" }
    var poeGraphicsReady: Bool { checks["poe_graphics"] == "d3dmetal" }
    var gamePresent: Bool { checks["gwent"] == "present" }
    var importAvailable: Bool {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/GWENT The Witcher Card Game/Gwent.exe")
        return FileManager.default.fileExists(atPath: base.path)
    }

    private func process(_ action: String, arguments: [String] = []) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        if action.hasPrefix("poe-") {
            p.arguments = [backend.deletingLastPathComponent().appendingPathComponent("poe.sh").path, String(action.dropFirst(4))] + arguments
        } else { p.arguments = [backend.path, action] + arguments }
        var env = ProcessInfo.processInfo.environment
        env["EITNY_GAMEHUB_DATA"] = dataURL.path
        p.environment = env
        return p
    }

    func refresh() {
        guard !busy else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = self.process("doctor"), pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            do {
                try p.run()
                var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
                let poe = self.process("poe-doctor"), poePipe = Pipe()
                poe.standardOutput = poePipe; poe.standardError = poePipe
                try poe.run()
                output += String(data: poePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                poe.waitUntilExit()
                var values: [String: String] = [:]
                for line in output.split(separator: "\n") {
                    let fields = line.split(separator: "|", maxSplits: 2).map(String.init)
                    if fields.count == 3 && fields[0] == "GB_CHECK" { values[fields[1]] = fields[2] }
                }
                DispatchQueue.main.async {
                    self.checks = values
                    if let preset = values["poe_preset"], ["balanced", "performance", "quality"].contains(preset) { self.poePreset = preset }
                    if p.terminationStatus != 0 {
                        self.error = output.replacingOccurrences(of: "GB_ERROR|", with: "")
                        self.status = "Не удалось проверить окружение"
                    } else if self.status == "Проверяю готовность…" {
                        self.status = self.ready ? "Можно открыть Steam" : "Подготовим Steam перед первым запуском"
                    }
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription; self.status = "Не удалось запустить проверку" }
            }
        }
    }

    func run(_ action: String, arguments: [String] = []) {
        guard !busy else { return }
        busy = true; error = nil; currentAction = action
        status = action == "setup" ? "Подготавливаю компоненты…" : "Выполняю…"
        journal += "\n— \(Date().formatted(date: .abbreviated, time: .standard)) · \(action) —\n"
        let p = process(action, arguments: arguments), pipe = Pipe()
        currentProcess = p
        p.standardOutput = pipe; p.standardError = pipe
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try p.run()
                var pending = Data()
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    pending.append(data)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending[..<newline], as: UTF8.self)
                        pending.removeSubrange(...newline)
                        DispatchQueue.main.async { self.receive(line) }
                    }
                }
                if !pending.isEmpty {
                    let tail = String(decoding: pending, as: UTF8.self)
                    DispatchQueue.main.async { self.receive(tail) }
                }
                p.waitUntilExit()
                DispatchQueue.main.async {
                    self.busy = false; self.currentProcess = nil
                    if p.terminationStatus != 0 {
                        if self.error == nil { self.error = "Операция прервалась (код \(p.terminationStatus)). Подробности — в журнале." }
                        self.status = "Нужна проверка"
                    }
                    self.refresh()
                    self.reloadLibrary()
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false; self.currentProcess = nil
                    self.error = error.localizedDescription; self.status = "Не удалось выполнить действие"
                }
            }
        }
    }

    func recoverPoE() {
        let alert = NSAlert()
        alert.messageText = "Закрыть PoE и вернуть оконный режим?"
        alert.informativeText = "Текущий сеанс PoE завершится. Разрешение, FSR и управление сохранятся. Steam и GWENT останутся открыты."
        alert.addButton(withTitle: "Закрыть PoE и восстановить")
        alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn { run("poe-recover") }
    }

    private func receive(_ line: String) {
        journal += line + "\n"
        if journal.count > 50_000 { journal = String(journal.suffix(40_000)) }
        if line.hasPrefix("GB_STATUS|") { status = String(line.dropFirst(10)) }
        if line.hasPrefix("GB_ERROR|") { error = String(line.dropFirst(9)) }
    }

    func reloadLibrary() {
        guard !syncing else { return }
        syncing = true
        let location = dataURL
        Task {
            let snapshot = await Task.detached(priority: .utility) { SteamLibrary(dataURL: location).read() }.value
            await MainActor.run {
                self.profile = snapshot.profile
                self.games = snapshot.games
                self.libraryNote = snapshot.note
                self.syncedAt = Date()
            }
            if let local = snapshot.profile, let remote = await SteamProfileXML.fetch(local) {
                await MainActor.run { if self.profile?.id == remote.id { self.profile = remote } }
            }
            await MainActor.run { self.syncing = false }
        }
    }

    var visibleGames: [SteamGame] {
        let selected = games.filter {
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) &&
            (filter != "Установлены" || $0.installed || $0.installedOnMac) &&
            (filter != "Проверены" || $0.supported)
        }
        return selected.sorted {
            if sorting == "Время в игре", $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func openGame(_ game: SteamGame) {
        if game.id == 238960 { selectedTab = 3 }
        else if game.supported && game.installed { run("gwent") }
        else { run("game-library", arguments: [String(game.id)]) }
    }

    func revealData() { NSWorkspace.shared.open(dataURL) }
    func authorizeDataFolder() {
        let picker = NSOpenPanel()
        picker.title = "Доступ к папке EitnyGameHub"
        picker.message = "Подтверди эту папку, чтобы приложение могло читать библиотеку Steam после обновления."
        picker.prompt = "Выбрать папку"
        picker.directoryURL = dataURL
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard url.standardizedFileURL == dataURL.standardizedFileURL else {
            error = "Выбери текущую папку данных: \(dataURL.lastPathComponent)."
            return
        }
        authorizedDataURL?.stopAccessingSecurityScopedResource()
        authorizedDataURL = url.startAccessingSecurityScopedResource() ? url : nil
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "dataFolderBookmark")
        }
        error = nil
        refresh()
        reloadLibrary()
    }
    func revealLogs() {
        let logs = dataURL.appendingPathComponent("Logs")
        if FileManager.default.fileExists(atPath: logs.path) { NSWorkspace.shared.open(logs) }
    }
}

struct HubButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(primary ? Color.white : Color.white.opacity(0.8))
            .background(primary ? mint.opacity(configuration.isPressed ? 0.55 : 0.8) : Color.white.opacity(configuration.isPressed ? 0.10 : 0.045), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.09)))
    }
}

struct HubImage: View {
    let url: URL?
    var body: some View {
        if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                else { Rectangle().fill(panel).overlay(Image(systemName: "gamecontroller").font(.system(size: 26)).foregroundStyle(.white.opacity(0.20))) }
            }
        }
    }
}

struct ContentView: View {
    @StateObject var model = BridgeModel()
    private let columns = [GridItem(.adaptive(minimum: 205, maximum: 340), spacing: 20, alignment: .top)]
    var appIcon: NSImage? { Bundle.main.url(forResource: "AppIconDisplay", withExtension: "png").flatMap(NSImage.init(contentsOf:)) }
    var installedCount: Int { model.games.filter { $0.installed || $0.installedOnMac }.count }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.selectedTab == 0 ? (model.filter == "Установлены" ? "Установленные игры" : "Библиотека") : model.selectedTab == 1 ? "Настройки" : model.selectedTab == 3 ? "Path of Exile" : "Помощь")
                            .font(.system(size: 29, weight: .bold)).tracking(-0.6)
                        Text(model.selectedTab == 0 ? "Твои игры. Одно место для запуска." : model.selectedTab == 1 ? "Всё для комфортной игры на Mac." : model.selectedTab == 3 ? "Первое путешествие в Рэкласт на Mac." : "От первого запуска до любимой игры.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.42))
                    }
                    Spacer()
                    if let profile = model.profile {
                        HStack(spacing: 10) {
                            HubImage(url: profile.avatar).frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name).font(.system(size: 12, weight: .semibold))
                                Text("Профиль Steam").font(.system(size: 10)).foregroundStyle(.white.opacity(0.38))
                            }
                        }.padding(.horizontal, 14).padding(.vertical, 9).background(panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                if model.selectedTab == 0 { library }
                else if model.selectedTab == 1 { environment }
                else if model.selectedTab == 3 { poePage }
                else { help }
                statusBar
            }.padding(.horizontal, 30).padding(.top, 36).padding(.bottom, 18)
        }
        .frame(minWidth: 1030, minHeight: 680)
        .background(canvasBackground).preferredColorScheme(.dark)
        .sheet(isPresented: $model.showLog) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Журнал запуска").font(.title2.bold()); Spacer(); Button("Закрыть") { model.showLog = false } }
                ScrollView { Text(model.journal.isEmpty ? "Пока нет записей" : model.journal).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(24).frame(width: 720, height: 450)
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                if let icon = appIcon { Image(nsImage: icon).resizable().frame(width: 39, height: 39) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("EitnyGameHub").font(.system(size: 13, weight: .semibold))
                    Text("Играй на своём Mac").font(.system(size: 9)).foregroundStyle(.white.opacity(0.38))
                }
            }.padding(.bottom, 39)
            Text("КОЛЛЕКЦИЯ").font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(.white.opacity(0.3)).padding(.horizontal, 12).padding(.bottom, 8)
            navRow("Библиотека", "square.grid.2x2", count: model.games.count, selected: model.selectedTab == 0 && model.filter != "Установлены") { model.selectedTab = 0; model.filter = "Все игры" }
            navRow("Установлены", "arrow.down.circle", count: installedCount, selected: model.selectedTab == 0 && model.filter == "Установлены") { model.selectedTab = 0; model.filter = "Установлены" }
            Text("ТЕСТОВЫЕ ИГРЫ").font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(.white.opacity(0.3)).padding(.horizontal, 12).padding(.top, 26).padding(.bottom, 8)
            navRow("Path of Exile", "flame", selected: model.selectedTab == 3) { model.selectedTab = 3; model.refresh() }
            Spacer()
            navRow("Настройки", "slider.horizontal.3", selected: model.selectedTab == 1) { model.selectedTab = 1 }
            navRow("Помощь", "questionmark.circle", selected: model.selectedTab == 2) { model.selectedTab = 2 }
            Divider().padding(.vertical, 12)
            HStack { Text("EitnyGameHub"); Spacer(); Text("0.4.1") }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.27)).padding(.horizontal, 12)
        }.padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 23).frame(width: 216)
            .background(Color(red: 0.09, green: 0.094, blue: 0.103))
    }
    func navRow(_ title: String, _ symbol: String, count: Int? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 2)
                if let count { Text("\(count)").font(.system(size: 10, weight: .medium)).foregroundStyle(selected ? mint : .white.opacity(0.3)).fixedSize() }
            }.foregroundStyle(selected ? mint : .white.opacity(0.52)).padding(.horizontal, 12).padding(.vertical, 13)
                .background(selected ? mint.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    var library: some View {
        VStack(alignment: .leading, spacing: 22) {
            steamStrip
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.35))
                    TextField("Поиск по библиотеке", text: $model.search).textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("Поиск игр")
                }.padding(12).frame(maxWidth: 330).background(panel, in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 4)
                Menu { ForEach(["Все игры", "Установлены", "Проверены"], id: \.self) { value in Button(value) { model.filter = value } } } label: {
                    Label(model.filter, systemImage: "line.3.horizontal.decrease")
                }.menuStyle(.borderlessButton).fixedSize().padding(11).background(panel, in: RoundedRectangle(cornerRadius: 10))
                Menu { ForEach(["Название", "Время в игре"], id: \.self) { value in Button(value) { model.sorting = value } } } label: {
                    Label(model.sorting, systemImage: "arrow.up.arrow.down")
                }.menuStyle(.borderlessButton).fixedSize().padding(11).background(panel, in: RoundedRectangle(cornerRadius: 10))
            }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            if model.games.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(mint)
                    Text(model.profile == nil ? "Твоя библиотека начинается здесь" : "Обновим твою библиотеку").font(.system(size: 20, weight: .semibold))
                    Text("Открой Steam, войди в свой аккаунт и перейди в библиотеку.\nЗатем обнови список игр здесь.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center)
                    Button(model.ready ? "Подключить Steam" : "Подготовить Steam") { model.run(model.ready ? "steam" : "setup") }.buttonStyle(HubButton(primary: true)).disabled(model.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleGames.isEmpty {
                VStack(spacing: 10) { Image(systemName: "magnifyingglass").font(.title); Text("Ничего не найдено"); Text("Попробуй другое название или фильтр.").font(.system(size: 12)) }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 29) {
                        gameSection("Установлены", games: model.visibleGames.filter { $0.installed || $0.installedOnMac })
                        gameSection("Все остальные игры", games: model.visibleGames.filter { !$0.installed && !$0.installedOnMac })
                    }.padding(.bottom, 12).padding(.trailing, 5)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    var steamStrip: some View {
        HStack(spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 19)).foregroundStyle(.white.opacity(0.85))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Steam").font(.system(size: 14, weight: .semibold))
                    Text(model.profile == nil ? "Подключи свой аккаунт" : "Библиотека подключена").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
            }
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 28)
            statistic("Игр", "\(model.games.count)")
            statistic("Установлено", "\(installedCount)")
            statistic("Часов в игре", String(format: "%.0f", Double(model.games.reduce(0) { $0 + $1.minutes }) / 60))
            Spacer(minLength: 4)
            Button { model.reloadLibrary(); model.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 14)).frame(width: 31, height: 31)
            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).disabled(model.syncing).help("Обновить библиотеку").accessibilityLabel("Обновить библиотеку")
            Button { model.run(model.ready ? "steam" : "setup") } label: {
                Label(model.ready ? "Открыть Steam" : "Подготовить Steam", systemImage: "arrow.up.right")
            }.buttonStyle(HubButton(primary: true)).disabled(model.busy || model.checks["rosetta"] == "missing")
        }.padding(18).background(panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.055)))
    }
    func statistic(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.white.opacity(0.36))
        }
    }
    @ViewBuilder func gameSection(_ title: String, games: [SteamGame]) -> some View {
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text("\(games.count)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.045), in: Capsule())
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(games) { game in
                        Button { model.openGame(game) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                GeometryReader { geometry in
                                    HubImage(url: game.artwork).frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                        .overlay(alignment: .bottomTrailing) {
                                            if game.supported {
                                                Label("Проверена", systemImage: "checkmark.seal.fill").font(.system(size: 8, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5).background(.black.opacity(0.75), in: Capsule()).padding(8)
                                            }
                                        }
                                }.aspectRatio(460.0 / 215.0, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(game.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.86)).lineLimit(1)
                                HStack {
                                    Label(game.id == 238960 ? "Тестовый запуск" : game.supported && game.installed ? "Играть" : "Открыть в Steam", systemImage: game.supported && game.installed ? "play.fill" : "arrow.up.right")
                                        .foregroundStyle(game.supported && game.installed ? mint : .white.opacity(0.37))
                                    Spacer(minLength: 0)
                                    if game.installedOnMac { Text("macOS").foregroundStyle(.white.opacity(0.32)) }
                                    else if game.minutes > 0 { Text(String(format: "%.1f ч", Double(game.minutes) / 60)).foregroundStyle(.white.opacity(0.32)) }
                                }.font(.system(size: 10))
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.busy || !model.ready).help(game.supported && game.installed ? "Запустить в оконном режиме" : "Открыть \(game.name) в Steam")
                    }
                }
            }
        }
    }
    var statusBar: some View {
        HStack(spacing: 7) {
            if model.busy || model.syncing { ProgressView().controlSize(.small).scaleEffect(0.7) }
            else { Circle().fill(model.error == nil ? mint.opacity(0.6) : .orange).frame(width: 4, height: 4) }
            Text(model.error ?? (model.busy ? model.status : model.syncedAt.map { "Синхронизировано в \($0.formatted(date: .omitted, time: .shortened))" } ?? model.status))
                .font(.system(size: 9)).foregroundStyle(model.error == nil ? .white.opacity(0.32) : .orange).lineLimit(2)
            Spacer()
            Button("Журнал запуска") { model.showLog = true }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
        }
    }
    var poePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    HubImage(url: URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/238960/header.jpg"))
                        .frame(width: 270, height: 126).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PATH OF EXILE • ПЕРВАЯ ЧАСТЬ").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(mint)
                        Text("Добро пожаловать в Рэкласт").font(.system(size: 22, weight: .semibold))
                        Text("DirectX 12 · D3DMetal · оконный режим. Проверено владельцем на M3 Pro; производительность зависит от сцены и настроек.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(model.poeInstalled ? "Игра установлена" : model.poeReady ? "Войди в Steam и установи игру" : "Подготовь Path of Exile").font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(model.busy).help("Проверить установку PoE").accessibilityLabel("Проверить установку PoE")
                    }
                    Text(model.poeGraphicsReady ? "Игра запускается в окне. Твоё разрешение, FSR и остальные настройки сохраняются между запусками." : "У PoE собственное окружение и Steam. Для DirectX 12 нужна macOS 15 или новее. Перед обновлением графики закрой Steam для PoE.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if !model.poeReady {
                            Button("Подготовить PoE") { model.run("poe-setup") }.buttonStyle(HubButton(primary: true)).disabled(model.busy)
                        } else {
                            Button("Открыть Steam для PoE") { model.run("poe-steam") }.buttonStyle(HubButton()).disabled(model.busy)
                            Button(model.poeInstalled ? "Играть в PoE" : "Установить PoE") { model.run(model.poeInstalled ? "poe-launch" : "poe-install") }.buttonStyle(HubButton(primary: true)).disabled(model.busy)
                        }
                    }
                }.padding(22).background(panel, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 17) {
                    Text("Начальные настройки").font(.system(size: 16, weight: .semibold))
                    Picker("Режим", selection: $model.poePreset) {
                        Text("Баланс").tag("balanced")
                        Text("Больше FPS").tag("performance")
                        Text("Выше разрешение").tag("quality")
                    }.pickerStyle(.segmented).labelsHidden().disabled(model.busy)
                    Text(model.poePreset == "performance" ? "1600 × 1000 · низкое качество текстур · динамическое разрешение" : model.poePreset == "quality" ? "2560 × 1600 · низкое качество текстур · фиксированное разрешение" : "1920 × 1200 · низкое качество текстур · динамическое разрешение")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Оконный режим, лимит 60 кадров/с. Это верхний предел, а не гарантированная частота. Вариант «Больше FPS» уменьшает нагрузку за счёт детализации изображения.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Применить к PoE") { model.run("poe-preset", arguments: [model.poePreset]) }.buttonStyle(HubButton()).disabled(model.busy || !model.poeReady)
                        Text("Перед изменением закрой игру.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.padding(22).background(panel, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Как сравнить плавность").font(.system(size: 15, weight: .semibold))
                    Text("Проверь одну и ту же локацию сначала в покое, затем в бою. При повторном проходе часть шейдеров уже будет подготовлена. Сравнивай режимы при одинаковой нагрузке; результат меню не показывает скорость в бою.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Журнал PoE") { NSWorkspace.shared.open(model.dataURL.appendingPathComponent("Profiles/PathOfExile/Logs")) }.buttonStyle(HubButton()).disabled(!model.poeReady)
                        Button("Закрыть Steam для PoE") { model.run("poe-stop") }.buttonStyle(HubButton()).disabled(model.busy || !model.poeReady)
                    }
                    Divider().padding(.vertical, 6)
                    Text("Если появился чёрный экран").font(.system(size: 15, weight: .semibold))
                    Text("Полноэкранный режим пока нестабилен. Используй обычное окно и увеличивай его размер. Переключись сюда через ⌘Tab и восстанови оконный режим. Текущий сеанс PoE завершится.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    Button("Восстановить оконный режим…") { model.recoverPoE() }.buttonStyle(HubButton()).disabled(model.busy || !model.poeReady)
                }
            }.frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: .infinity)
    }
    var environment: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Подключение Steam").font(.title3.bold())
                ForEach([("Rosetta 2", "rosetta"), ("Среда запуска", "runtime"), ("Windows Steam", "steam")], id: \.0) { name, key in
                    HStack { Image(systemName: model.checks[key] == "ready" ? "checkmark.circle.fill" : "circle").foregroundStyle(mint); Text(name); Spacer(); Text(model.checks[key] == "ready" ? "Готово" : "Не установлено").foregroundStyle(.secondary) }.font(.system(size: 13)).padding(18).background(panel, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Button("Подготовить Steam") { model.run("setup") }.buttonStyle(HubButton(primary: true)).disabled(model.busy)
                    Button("Обновить библиотеку") { model.refresh(); model.reloadLibrary() }.buttonStyle(HubButton()).disabled(model.busy || model.syncing)
                }
                Text("Библиотека").font(.system(size: 15, weight: .semibold))
                Text(model.libraryNote).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                Text("Папка данных").font(.system(size: 15, weight: .semibold))
                Text(model.dataURL.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Открыть папку") { model.revealData() }.buttonStyle(HubButton())
                    Button("Разрешить доступ к папке") { model.authorizeDataFolder() }.buttonStyle(HubButton()).disabled(model.busy)
                    Button("Завершить Windows Steam") { model.run("stop") }.buttonStyle(HubButton()).disabled(model.busy || !model.ready)
                }
                Text("Игры и аккаунты хранятся отдельно от приложения. Для передачи другу достаточно самого приложения — он войдёт в свой Steam.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: .infinity)
    }
    var help: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                helpRow("01", "Подключи Steam", "Нажми «Подготовить Steam» и дождись установки. Затем открой Steam и войди в свой аккаунт.")
                helpRow("02", "Добавь свою библиотеку", "Открой библиотеку в Steam и нажми «Обновить библиотеку» в EitnyGameHub. Появятся обложки, установленные игры и время в игре.")
                helpRow("03", "Выбери игру", "Нажми на карточку, чтобы открыть игру в Steam. У проверенных игр появится отметка совместимости и быстрый запуск после установки.")
                helpRow("04", "Передай приложение другу", "Отправь архив EitnyGameHub.zip. Друг установит компоненты при первом запуске и войдёт в свой аккаунт. Твои игры и данные передавать не нужно.")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Совместимость игр").font(.system(size: 15, weight: .semibold))
                    Text("Сейчас проверен GWENT на MacBook Pro M3 Pro: он автоматически открывается в окне. При первом запуске потребуется вход в GOG. Если после входа возникла ошибка соединения, повтори запуск игры. Остальные игры отображаются в библиотеке, но их совместимость пока не проверена.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }.padding(20).background(panel, in: RoundedRectangle(cornerRadius: 14))
            }.frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: .infinity)
    }
    func helpRow(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(number).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(mint).frame(width: 38, height: 38).background(mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 16, weight: .semibold)); Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).lineSpacing(4).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

final class HubAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the running Dock icon explicitly when upgrading an existing app
        // whose old icon may still be cached by Launch Services.
        if let url = Bundle.main.url(forResource: "EitnyDockIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}

@main struct EitnyGameHubApp: App {
    @NSApplicationDelegateAdaptor(HubAppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("EitnyGameHub") { ContentView() }
            .windowStyle(.hiddenTitleBar).defaultSize(width: 1320, height: 820)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
