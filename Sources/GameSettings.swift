import Foundation

// Keep unknown settings (including bindings and account preferences) verbatim.
enum PoEGraphics {
    // Launch recovery changes only the renderer/window state, never resolution,
    // FSR, frame caps, bindings, audio or other player choices.
    static let launchValues = ["DISPLAY": [
        "renderer_type": "DirectX12", "device_type": "DirectX12",
        "fullscreen": "false", "borderless_windowed_fullscreen": "false", "maximize_window": "false"
    ]]
    static func values(_ preset: String) throws -> [String: [String: String]] {
        let sizes: [String: (Int, Int)] = ["balanced": (1920, 1200), "performance": (1600, 1000), "quality": (2560, 1600)]
        guard let size = sizes[preset] else { throw NSError(domain: "EitnyGameHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неизвестный профиль графики"] ) }
        return ["DISPLAY": [
            "renderer_type": "DirectX12", "device_type": "DirectX12", "fullscreen": "false", "borderless_windowed_fullscreen": "false", "maximize_window": "false",
            "resolution_width": String(size.0), "resolution_height": String(size.1),
            "framerate_limit": "60", "framerate_limit_enabled": "true", "background_framerate_limit": "30", "background_framerate_limit_enabled": "true",
            "use_dynamic_resolution": preset == "quality" ? "false" : "true", "dynamic_resolution_fps": "60",
            "shadow_type": "Low", "global_illumination_detail": "0", "water_detail": "0",
            "texture_quality": "TextureQualityLow", "vsync": "Off"
        ], "GENERAL": ["engine_multithreading_mode": "enabled"]]
    }
    static func merging(_ original: String, preset: String) throws -> String {
        try merging(original, values: values(preset))
    }
    static func merging(_ original: String, values: [String: [String: String]]) -> String {
        var section = "", output: [String] = [], seen: [String: Set<String>] = [:]
        func finishSection() {
            guard let desired = values[section] else { return }
            for key in desired.keys.sorted() where !(seen[section] ?? []).contains(key) {
                output.append("\(key)=\(desired[key]!)")
                seen[section, default: []].insert(key)
            }
        }
        let text = original.hasPrefix("\u{feff}") ? String(original.dropFirst()) : original
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                finishSection()
                section = String(trimmed.dropFirst().dropLast()).uppercased()
                output.append(line)
            } else if !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#"), let index = line.firstIndex(of: "=") {
                let key = line[..<index].trimmingCharacters(in: .whitespaces).lowercased()
                if let value = values[section]?[key] {
                    // Collapse duplicate managed keys so the game cannot select a stale value.
                    if !(seen[section] ?? []).contains(key) { output.append("\(key)=\(value)") }
                    seen[section, default: []].insert(key)
                } else { output.append(line) }
            } else { output.append(line) }
        }
        finishSection()
        for missing in values.keys.sorted() where seen[missing] == nil {
            output.append("[\(missing)]")
            for key in values[missing]!.keys.sorted() { output.append("\(key)=\(values[missing]![key]!)") }
        }
        return (original.hasPrefix("\u{feff}") ? "\u{feff}" : "") + output.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
    static func apply(to url: URL, preset: String, createOnly: Bool) throws {
        try write(to: url, values: values(preset), createOnly: createOnly)
    }
    static func prepareLaunch(at url: URL) throws {
        try write(to: url, values: launchValues, createOnly: false)
    }
    private static func write(to url: URL, values: [String: [String: String]], createOnly: Bool) throws {
        let fm = FileManager.default
        if createOnly && fm.fileExists(atPath: url.path) { return }
        let original = fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
        guard original.utf8.count < 2_000_000 else { throw NSError(domain: "EitnyGameHub", code: 2, userInfo: [NSLocalizedDescriptionKey: "Файл настроек слишком большой"]) }
        let next = merging(original, values: values)
        guard next != original else { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent().appendingPathComponent("production_Config.before-Eitny-\(UUID().uuidString).ini")
            try fm.copyItem(at: url, to: backup)
        }
        try next.write(to: url, atomically: true, encoding: .utf8)
    }
}
