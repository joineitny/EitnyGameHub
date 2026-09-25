import Foundation


struct SteamProfile {
    var id: String
    var name: String
    var avatar: URL?
    var memberSince: String?
    var state: String?
}

struct SteamGame: Identifiable {
    let id: Int
    var name: String
    var minutes: Int
    var installed: Bool
    var installedOnMac: Bool
    var artwork: URL?
    var supported: Bool { id == 1284410 }
}

struct SteamSnapshot {
    var profile: SteamProfile?
    var games: [SteamGame]
    var note: String
}

// Valve KeyValues text parser. Only allowlisted display fields leave this reader.
// Authentication tokens, passwords and client cookies are neither used nor copied.
enum KeyValues {
    static func read(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url), data.count < 32_000_000,
              let text = String(data: data, encoding: .utf8) else { return [:] }
        return parse(text)
    }
    static func parse(_ text: String) -> [String: Any] {
        let bytes = Array(text.utf8)
        var index = 0
        func token() -> String? {
            while index < bytes.count {
                if bytes[index] <= 32 { index += 1; continue }
                if bytes[index] == 47 && index + 1 < bytes.count && bytes[index + 1] == 47 {
                    while index < bytes.count && bytes[index] != 10 { index += 1 }; continue
                }
                break
            }
            guard index < bytes.count else { return nil }
            let c = bytes[index]; index += 1
            if c == 123 { return "{" }; if c == 125 { return "}" }
            var result: [UInt8] = []
            if c == 34 {
                while index < bytes.count {
                    let value = bytes[index]; index += 1
                    if value == 34 { break }
                    if value == 92 && index < bytes.count && (bytes[index] == 92 || bytes[index] == 34) {
                        result.append(bytes[index]); index += 1
                    } else { result.append(value) }
                }
            } else {
                result.append(c)
                while index < bytes.count && bytes[index] > 32 && bytes[index] != 123 && bytes[index] != 125 {
                    result.append(bytes[index]); index += 1
                }
            }
            return String(decoding: result, as: UTF8.self)
        }
        func object(_ depth: Int) -> [String: Any] {
            guard depth < 64 else { return [:] }
            var result: [String: Any] = [:]
            while let key = token(), key != "}" {
                guard let value = token() else { break }
                result[key] = value == "{" ? object(depth + 1) : value
            }
            return result
        }
        return object(0)
    }
}

extension Dictionary where Key == String, Value == Any {
    func value(_ key: String) -> Any? { self.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value }
    func dict(_ key: String) -> [String: Any] { value(key) as? [String: Any] ?? [:] }
    func string(_ key: String) -> String { value(key) as? String ?? "" }
}

// Bounded parser for Valve's appinfo v39–41 and packageinfo v27–28 caches.
// Format reference: github.com/ValveResourceFormat/SteamAppInfo.
final class SteamBinary {
    enum Failure: Error { case invalid }
    let bytes: [UInt8]
    var offset = 0
    var strings: [String] = []
    var headers: [Int: String] = [:]
    init(_ data: Data) throws {
        guard data.count <= 128_000_000 else { throw Failure.invalid }
        bytes = Array(data)
    }
    func number(_ count: Int) throws -> UInt64 {
        guard count > 0, count <= 8, offset >= 0, offset <= bytes.count - count else { throw Failure.invalid }
        var value: UInt64 = 0
        for i in 0..<count { value |= UInt64(bytes[offset + i]) << (8 * i) }
        offset += count; return value
    }
    func skip(_ count: Int) throws {
        guard count >= 0, offset <= bytes.count - count else { throw Failure.invalid }
        offset += count
    }
    func cstring() throws -> String {
        let start = offset
        while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
        guard offset < bytes.count else { throw Failure.invalid }
        let result = String(decoding: bytes[start..<offset], as: UTF8.self)
        offset += 1; return result
    }
    func object(_ depth: Int = 0) throws -> [String: Any] {
        guard depth < 64 else { throw Failure.invalid }
        var result: [String: Any] = [:]
        while true {
            let type = try number(1)
            if type == 8 || type == 11 { return result }
            let key: String
            if strings.isEmpty { key = try cstring() }
            else {
                let index = Int(try number(4))
                guard strings.indices.contains(index) else { throw Failure.invalid }
                key = strings[index]
            }
            switch type {
            case 0: result[key] = try object(depth + 1)
            case 1: result[key] = try cstring()
            case 2, 3, 4, 6: result[key] = try number(4)
            case 7, 10: result[key] = try number(8)
            default: throw Failure.invalid
            }
        }
    }
    func applications() throws -> [Int: String] {
        let magic = try number(4), version = Int(magic & 255)
        guard magic >> 8 == 0x075644, (39...41).contains(version) else { throw Failure.invalid }
        try skip(4)
        if version == 41 {
            let table = Int(try number(8)), saved = offset
            guard table >= offset, table <= bytes.count - 4 else { throw Failure.invalid }
            offset = table
            let count = Int(try number(4))
            guard count > 0, count <= 100_000 else { throw Failure.invalid }
            for _ in 0..<count { strings.append(try cstring()) }
            offset = saved
        }
        var result: [Int: String] = [:]
        while true {
            let id = Int(try number(4)); if id == 0 { return result }
            let size = Int(try number(4)), start = offset
            guard size >= (version >= 40 ? 60 : 40), start <= bytes.count - size else { throw Failure.invalid }
            try skip(version >= 40 ? 60 : 40)
            let data = try object().dict("appinfo").dict("common")
            guard offset <= start + size else { throw Failure.invalid }
            if data.string("type").lowercased() == "game", !data.string("name").isEmpty {
                result[id] = data.string("name")
                let library = data.dict("library_assets_full").dict("library_header").dict("image").string("english")
                let header = library.isEmpty ? data.dict("header_image").string("english") : library
                if !header.isEmpty, !header.contains(".."), header.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil { headers[id] = header }
            }
            offset = start + size
        }
    }
    func packageApplications() throws -> Set<Int> {
        let magic = try number(4)
        guard magic == 0x06565528 || magic == 0x06565527 else { throw Failure.invalid }
        try skip(4)
        var result = Set<Int>()
        while true {
            let id = try number(4); if id == 0xffffffff { return result }
            try skip(magic == 0x06565528 ? 32 : 24)
            let data = try object().dict(String(id)).dict("appids")
            // Package 0 is a global collection of free tools, not this user's library.
            if id != 0 {
                for value in data.values { if let value = value as? UInt64, value <= UInt64(Int.max) { result.insert(Int(value)) } }
            }
        }
    }
}

struct SteamLibrary {
    let root: URL
    let home: URL
    init(dataURL: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        root = dataURL.appendingPathComponent("Bottle/drive_c/Program Files (x86)/Steam")
        self.home = home
    }
    func read() -> SteamSnapshot {
        let accounts = KeyValues.read(root.appendingPathComponent("config/loginusers.vdf")).dict("users")
        let selected = accounts.compactMap { key, value -> (String, [String: Any])? in
            guard UInt64(key) != nil, let values = value as? [String: Any] else { return nil }
            return (key, values)
        }.sorted {
            let a = $0.1.string("MostRecent") == "1", b = $1.1.string("MostRecent") == "1"
            return a != b ? a : (Int($0.1.string("Timestamp")) ?? 0) > (Int($1.1.string("Timestamp")) ?? 0)
        }.first
        var profile: SteamProfile?
        var played: [String: Any] = [:]
        if let (id, values) = selected, let steamID = UInt64(id), steamID >= 76561197960265728 {
            profile = SteamProfile(id: id, name: values.string("PersonaName").isEmpty ? "Steam" : values.string("PersonaName"))
            let account = steamID - 76561197960265728
            played = KeyValues.read(root.appendingPathComponent("userdata/\(account)/config/localconfig.vdf"))
                .dict("UserLocalConfigStore").dict("Software").dict("Valve").dict("Steam").dict("apps")
        }
        var names: [Int: String] = [:], headers: [Int: String] = [:], ids = Set<Int>()
        if profile != nil {
            if let data = try? Data(contentsOf: root.appendingPathComponent("appcache/appinfo.vdf")), let reader = try? SteamBinary(data), let value = try? reader.applications() { names = value; headers = reader.headers }
            if accounts.count == 1, let data = try? Data(contentsOf: root.appendingPathComponent("appcache/packageinfo.vdf")), let value = try? SteamBinary(data).packageApplications() { ids.formUnion(value) }
            ids.formUnion(played.keys.compactMap(Int.init))
        }
        let installed = manifests(root: root, windows: true)
        let native = manifests(root: home.appendingPathComponent("Library/Application Support/Steam"), windows: false)
        ids.formUnion(installed.keys)
        for (id, name) in installed { names[id] = name }
        var games = ids.compactMap { id -> SteamGame? in
            guard let name = names[id] else { return nil }
            let cache = root.appendingPathComponent("appcache/librarycache")
            let header = headers[id] ?? "header.jpg"
            let choices = [cache.appendingPathComponent("\(id)/\(header)"), cache.appendingPathComponent("\(id)/header.jpg"), cache.appendingPathComponent("\(id)_header.jpg")]
            let artwork = choices.first { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                ?? URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(id)/\(header)")
            return SteamGame(id: id, name: name, minutes: Int(played.dict(String(id)).string("Playtime")) ?? 0,
                             installed: installed[id] != nil, installedOnMac: native[id] != nil, artwork: artwork)
        }
        games.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let note = accounts.count > 1
            ? "В Steam несколько аккаунтов: показаны установленные и ранее запущенные игры выбранного профиля."
            : "Библиотека из локальных данных Steam. Открой Steam и обнови список после покупки или установки игры."
        return SteamSnapshot(profile: profile, games: games, note: note)
    }
    private func manifests(root: URL, windows: Bool) -> [Int: String] {
        var libraries = [root]
        for (_, value) in KeyValues.read(root.appendingPathComponent("steamapps/libraryfolders.vdf")).dict("libraryfolders") {
            guard let d = value as? [String: Any] else { continue }
            let path = d.string("path")
            if windows && path.lowercased().hasPrefix("c:\\") {
                let bottle = self.root.deletingLastPathComponent().deletingLastPathComponent()
                libraries.append(bottle.appendingPathComponent(String(path.dropFirst(3)).replacingOccurrences(of: "\\", with: "/")))
            } else if path.hasPrefix("/") { libraries.append(URL(fileURLWithPath: path)) }
        }
        var result: [Int: String] = [:]
        for library in Set(libraries) {
            for file in (try? FileManager.default.contentsOfDirectory(at: library.appendingPathComponent("steamapps"), includingPropertiesForKeys: nil)) ?? [] where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                let info = KeyValues.read(file).dict("AppState")
                guard let id = Int(info.string("appid")), let flags = Int(info.string("StateFlags")), flags & 4 != 0, !info.string("name").isEmpty else { continue }
                result[id] = info.string("name")
            }
        }
        return result
    }
}

final class SteamProfileXML: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private var element = ""
    private var depth = 0
    private let allowed: Set<String> = ["steamID64", "steamID", "avatarFull", "onlineState", "memberSince"]
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        element = depth == 2 ? name : ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if allowed.contains(element) { values[element, default: ""] += string } }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { if let string = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: string) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { element = ""; depth -= 1 }
    static func fetch(_ profile: SteamProfile) async -> SteamProfile? {
        guard let url = URL(string: "https://steamcommunity.com/profiles/\(profile.id)/?xml=1") else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { return nil }
        let delegate = SteamProfileXML(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), delegate.values["steamID64"] == profile.id else { return nil }
        var result = profile
        if let name = delegate.values["steamID"], !name.isEmpty { result.name = name }
        if let raw = delegate.values["avatarFull"], let avatar = URL(string: raw), avatar.scheme == "https",
           let host = avatar.host, host == "steamstatic.com" || host.hasSuffix(".steamstatic.com") { result.avatar = avatar }
        result.memberSince = delegate.values["memberSince"]
        result.state = delegate.values["onlineState"]
        return result
    }
}
