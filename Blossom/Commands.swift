import Foundation
import Combine

/// What a command does when you run it.
enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case screensaver, lockScreen, logout, sleep, displaySleep
    case volume, mute, darkMode, lightMode, darkModeOn
    case openApp, openURL, shell
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screensaver: "Start Screen Saver"
        case .lockScreen: "Lock Screen"
        case .logout: "Log Out"
        case .sleep: "Sleep"
        case .displaySleep: "Turn Display Off"
        case .volume: "Set Volume"
        case .mute: "Mute / Unmute"
        case .darkMode: "Toggle Light / Dark Mode"
        case .lightMode: "Light Mode"
        case .darkModeOn: "Dark Mode"
        case .openApp: "Open App"
        case .openURL: "Open Website"
        case .shell: "Run Shell Command"
        case .settings: "Blossom Settings"
        }
    }

    var symbol: String {
        switch self {
        case .screensaver: "sparkles.tv"
        case .lockScreen: "lock.fill"
        case .logout: "rectangle.portrait.and.arrow.right"
        case .sleep: "moon.zzz.fill"
        case .displaySleep: "display"
        case .volume: "speaker.wave.2.fill"
        case .mute: "speaker.slash.fill"
        case .darkMode: "circle.lefthalf.filled"
        case .lightMode: "sun.max.fill"
        case .darkModeOn: "moon.fill"
        case .openApp: "app.badge"
        case .openURL: "globe"
        case .shell: "terminal.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// Whether the action needs something more: a number, an app, a link, a command.
    var takesArgument: Bool {
        switch self {
        case .volume, .openApp, .openURL, .shell: true
        default: false
        }
    }

    var argumentHint: String {
        switch self {
        case .volume: "0–100"
        case .openApp: "Safari"
        case .openURL: "youtube.com"
        case .shell: "say Hello"
        default: ""
        }
    }
}

/// A word you type, and the action it runs.
struct BlossomCommand: Codable, Identifiable, Hashable {
    var id = UUID()
    var keyword: String
    var kind: ActionKind
    /// Left empty on an action that takes one, it comes from what you type after the keyword: "volume 30".
    var argument = ""
}

/// A command that fits what was typed, with the argument it will run with.
struct Match: Identifiable {
    let command: BlossomCommand
    let argument: String
    var id: UUID { command.id }
}

@MainActor
final class CommandStore: ObservableObject {
    static let shared = CommandStore()

    private static let key = "commands"

    static let defaults: [BlossomCommand] = [
        BlossomCommand(keyword: "screensaver", kind: .screensaver),
        BlossomCommand(keyword: "lock", kind: .lockScreen),
        BlossomCommand(keyword: "logout", kind: .logout),
        BlossomCommand(keyword: "sleep", kind: .sleep),
        BlossomCommand(keyword: "display off", kind: .displaySleep),
        BlossomCommand(keyword: "volume", kind: .volume),
        BlossomCommand(keyword: "mute", kind: .mute),
        BlossomCommand(keyword: "dark", kind: .darkMode),
        BlossomCommand(keyword: "light", kind: .lightMode),
        BlossomCommand(keyword: "open", kind: .openApp),
        BlossomCommand(keyword: "youtube", kind: .openURL, argument: "youtube.com"),
        BlossomCommand(keyword: "settings", kind: .settings),
    ]

    @Published var commands: [BlossomCommand] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([BlossomCommand].self, from: data) {
            commands = saved
        } else {
            commands = Self.defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(commands) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func restoreDefaults() {
        commands = Self.defaults
    }

    /// One command as Settings shows it in JSON: no id, and value left out when empty.
    private struct JSONCommand: Codable {
        var keyword: String
        var action: ActionKind
        var value: String?
    }

    var json: String {
        let items = commands.map { JSONCommand(keyword: $0.keyword, action: $0.kind, value: $0.argument.isEmpty ? nil : $0.argument) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(items) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Replaces the commands with the ones in the JSON. Returns what's wrong with it, or nil when it was applied.
    func apply(json text: String) -> String? {
        let items: [JSONCommand]
        do {
            items = try JSONDecoder().decode([JSONCommand].self, from: Data(text.utf8))
        } catch let DecodingError.dataCorrupted(context) where context.codingPath.last?.stringValue == "action" {
            let item = (context.codingPath.first?.intValue ?? 0) + 1
            return "Command \(item): action must be one of \(ActionKind.allCases.map(\.rawValue).joined(separator: ", "))"
        } catch let DecodingError.keyNotFound(key, context) {
            let item = (context.codingPath.first?.intValue ?? 0) + 1
            return "Command \(item) has no \"\(key.stringValue)\""
        } catch let DecodingError.typeMismatch(_, context) {
            guard let index = context.codingPath.first?.intValue else { return "The commands must be a list: [ … ]" }
            return "Command \(index + 1): \"\(context.codingPath.last?.stringValue ?? "")\" must be text"
        } catch {
            return "That isn't valid JSON yet"
        }

        // Keeps each command's id where it was, so the list doesn't jump
        commands = items.enumerated().map { index, item in
            BlossomCommand(
                id: commands.indices.contains(index) ? commands[index].id : UUID(),
                keyword: item.keyword,
                kind: item.action,
                argument: item.value ?? ""
            )
        }
        return nil
    }

    /// The commands that fit the query: "volume 30" fills in the argument, "vol" and "lume" find "volume".
    func matches(for query: String) -> [Match] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        let q = typed.lowercased()
        guard !q.isEmpty else {
            return commands.map { Match(command: $0, argument: $0.argument) }
        }

        var scored: [(score: Int, match: Match)] = []
        for command in commands {
            let keyword = command.keyword.lowercased()
            guard !keyword.isEmpty else { continue }

            if command.kind.takesArgument, command.argument.isEmpty, q.hasPrefix(keyword + " ") {
                let argument = typed.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
                scored.append((0, Match(command: command, argument: argument)))
            } else if keyword == q {
                scored.append((0, Match(command: command, argument: command.argument)))
            } else if keyword.hasPrefix(q) {
                scored.append((1, Match(command: command, argument: command.argument)))
            } else if keyword.contains(q) || command.kind.title.lowercased().contains(q) {
                scored.append((2, Match(command: command, argument: command.argument)))
            }
        }
        // Sorting by score alone keeps the order from Settings within each group
        return scored.enumerated()
            .sorted { ($0.element.score, $0.offset) < ($1.element.score, $1.offset) }
            .map(\.element.match)
    }
}
