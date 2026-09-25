import Foundation

@main struct GameSettingsMain {
    static func main() {
        do {
            let args = CommandLine.arguments
            guard (args.count == 3 && args[1] == "windowed") || (args.count == 4 && ["create", "apply"].contains(args[1])) else {
                throw NSError(domain: "EitnyGameHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверные параметры настроек PoE"])
            }
            guard args[2].hasPrefix("/") else { throw NSError(domain: "EitnyGameHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "Нужен абсолютный путь настроек PoE"]) }
            if args[1] == "windowed" { try PoEGraphics.prepareLaunch(at: URL(fileURLWithPath: args[2])) }
            else { try PoEGraphics.apply(to: URL(fileURLWithPath: args[2]), preset: args[3], createOnly: args[1] == "create") }
        } catch {
            fputs("GB_ERROR|\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
