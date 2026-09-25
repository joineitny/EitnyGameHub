import Foundation

@main struct LibraryTests {
    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--snapshot" {
            let result = SteamLibrary(dataURL: URL(fileURLWithPath: CommandLine.arguments[2])).read()
            print("Profile: \(result.profile?.name ?? "none"); games: \(result.games.count); installed: \(result.games.filter(\.installed).count)")
            for game in result.games { print("\(game.id) · \(game.name)") }
            return
        }
        let text = #"""
        // comment
        "Root" { "Name" "Тест \"игры\"" "Path" "C:\\Program Files (x86)\\Steam" "Nested" { "N" "42" } }
        "lowercase" "yes"
        """#
        let parsed = KeyValues.parse(text)
        precondition(parsed.dict("root").string("name") == "Тест \"игры\"")
        precondition(parsed.dict("root").dict("nested").string("n") == "42")
        precondition(parsed.dict("Root").string("Path") == "C:\\Program Files (x86)\\Steam")
        for bytes in [Data(), Data([0x29, 0x44, 0x56, 7]), Data(repeating: 255, count: 16)] {
            do { _ = try SteamBinary(bytes).applications(); fatalError("Accepted broken appinfo") } catch {}
        }
        let xml = XMLParser(data: Data("<profile><steamID64>123</steamID64><avatarFull><![CDATA[https://avatars.steamstatic.com/user.jpg]]></avatarFull><groups><group><avatarFull>group.jpg</avatarFull></group></groups></profile>".utf8))
        let delegate = SteamProfileXML(); xml.delegate = delegate
        precondition(xml.parse())
        precondition(delegate.values["avatarFull"] == "https://avatars.steamstatic.com/user.jpg")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("Bottle/drive_c/Program Files (x86)/Steam")
        let config = root.appendingPathComponent("config")
        let apps = root.appendingPathComponent("steamapps")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try #"""
        "users" { "76561197960265730" { "PersonaName" "Older" "Timestamp" "1" } "76561197960265731" { "PersonaName" "Current" "Timestamp" "2" } }
        """#.write(to: config.appendingPathComponent("loginusers.vdf"), atomically: true, encoding: .utf8)
        try #"""
        "AppState" { "appid" "1284410" "name" "GWENT" "StateFlags" "4" }
        """#.write(to: apps.appendingPathComponent("appmanifest_1284410.acf"), atomically: true, encoding: .utf8)
        try #"""
        "AppState" { "appid" "10" "name" "Not downloaded" "StateFlags" "2" }
        """#.write(to: apps.appendingPathComponent("appmanifest_10.acf"), atomically: true, encoding: .utf8)
        let snapshot = SteamLibrary(dataURL: temp, home: temp).read()
        precondition(snapshot.profile?.name == "Current")
        precondition(snapshot.games.count == 1 && snapshot.games[0].id == 1284410)
        precondition(snapshot.games[0].installed && snapshot.games[0].supported)
        precondition(snapshot.note.contains("несколько аккаунтов"))
        let missing = SteamLibrary(dataURL: temp.appendingPathComponent("missing"), home: temp).read()
        precondition(missing.profile == nil && missing.games.isEmpty)
        print("PASS: Unicode VDF, escaped paths, truncated caches, account selection, installed vs unfinished games, missing Steam.")
    }
}
