import Foundation
@main struct GameSettingsTests {
    static func main() throws {
        let original = "; untouched\r\n[DISPLAY]\r\nrenderer_type=Vulkan\r\nrenderer_type=DirectX12\r\nresolution_width=800\r\ncustom_future_setting=keep\r\n[SOUND]\r\nmaster_volume=25\r\n[ACTION_KEYS]\r\nattack_in_place=16\r\n[GENERAL]\r\nenable_profanity_filter=false\r\n"
        let result = try PoEGraphics.merging(original, preset: "balanced")
        precondition(result.contains("renderer_type=DirectX12"))
        precondition(result.components(separatedBy: "renderer_type=").count == 2)
        precondition(result.contains("resolution_width=1920"))
        precondition(result.contains("custom_future_setting=keep"))
        precondition(result.contains("master_volume=25") && result.contains("attack_in_place=16"))
        precondition(result.contains("enable_profanity_filter=false"))
        let again = try PoEGraphics.merging(result, preset: "balanced")
        precondition(again == result)
        let withBOM = try PoEGraphics.merging("\u{feff}" + original, preset: "balanced")
        precondition(withBOM.hasPrefix("\u{feff}"))
        precondition(withBOM.components(separatedBy: "[DISPLAY]").count == 2)
        precondition(withBOM.contains("renderer_type=DirectX12") && !withBOM.contains("renderer_type=Vulkan"))
        let playerSettings = "\u{feff}[DISPLAY]\nfullscreen=true\nborderless_windowed_fullscreen=true\nmaximize_window=true\nrenderer_type=DirectX11\ndevice_type=Vulkan\nresolution_width=2704\nresolution_height=1690\nupscale=FSR\nupscale_quality=Performance\nframerate_limit_enabled=false\n[SOUND]\nmaster_volume=25\n"
        let recovered = PoEGraphics.merging(playerSettings, values: PoEGraphics.launchValues)
        precondition(recovered.contains("fullscreen=false") && recovered.contains("borderless_windowed_fullscreen=false"))
        precondition(recovered.contains("renderer_type=DirectX12") && recovered.contains("device_type=DirectX12"))
        for preserved in ["resolution_width=2704", "resolution_height=1690", "upscale=FSR", "upscale_quality=Performance", "framerate_limit_enabled=false", "master_volume=25"] {
            precondition(recovered.contains(preserved))
        }
        precondition(PoEGraphics.merging(recovered, values: PoEGraphics.launchValues) == recovered)
        let performance = try PoEGraphics.merging(result, preset: "performance")
        precondition(performance.contains("resolution_width=1600"))
        let quality = try PoEGraphics.merging(result, preset: "quality")
        precondition(quality.contains("use_dynamic_resolution=false"))
        do { _ = try PoEGraphics.merging(original, preset: "invalid"); fatalError("invalid preset") } catch {}
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appendingPathComponent("production_Config.ini")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try original.write(to: file, atomically: true, encoding: .utf8)
        try PoEGraphics.apply(to: file, preset: "balanced", createOnly: true)
        let untouched = try String(contentsOf: file, encoding: .utf8)
        precondition(untouched == original)
        try PoEGraphics.apply(to: file, preset: "balanced", createOnly: false)
        let backup = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("before-Eitny") }!
        let saved = try String(contentsOf: backup, encoding: .utf8)
        precondition(saved == original)
        print("PASS: PoE config preserves bindings, audio and unknown keys; presets, backup and idempotence.")
    }
}
