import Foundation
import Combine

/// What a command does when you run it.
enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case screensaver, lockScreen, logout, sleep, displaySleep
    case volume, mute, darkMode, lightMode, darkModeOn
    case openApp, openURL, webSearch, shell
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
        case .webSearch: "Web Search"
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
        case .webSearch: "magnifyingglass"
        case .shell: "terminal.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// Whether the action needs something more: a number, an app, a link, a command.
    var takesArgument: Bool {
        switch self {
        case .volume, .openApp, .openURL, .webSearch, .shell: true
        default: false
        }
    }

    var argumentHint: String {
        switch self {
        case .volume: "0–100"
        case .openApp: "Safari"
        case .openURL: "youtube.com"
        case .webSearch: "cats"
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
    /// A second value, for Run Shell Command: text added after the first, or the word Typed for what you type after the keyword.
    var extra = ""

    init(id: UUID = UUID(), keyword: String, kind: ActionKind, argument: String = "", extra: String = "") {
        self.id = id
        self.keyword = keyword
        self.kind = kind
        self.argument = argument
        self.extra = extra
    }

    // Commands saved by earlier versions have no `extra`; without this they would all be dropped
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        keyword = try c.decode(String.self, forKey: .keyword)
        kind = try c.decode(ActionKind.self, forKey: .kind)
        argument = try c.decode(String.self, forKey: .argument)
        extra = try c.decodeIfPresent(String.self, forKey: .extra) ?? ""
    }

    /// Whether what you type after the keyword goes to the end of the shell command, as one quoted word: `claude -p 'what you typed'`.
    /// Value 2 left empty means Typed, as long as there is a Value to put it after.
    var usesTyped: Bool {
        let second = extra.trimmingCharacters(in: .whitespaces).lowercased()
        return kind == .shell && (second == "typed" || (second.isEmpty && !argument.trimmingCharacters(in: .whitespaces).isEmpty))
    }

    /// Typed was asked for by name, so nothing typed is a mistake; left empty it is optional, and the command runs as it is.
    var typedRequired: Bool {
        usesTyped && !extra.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The value as Settings holds it, without anything typed: the two values side by side on a shell command.
    var fixedArgument: String {
        guard kind == .shell, !usesTyped else { return argument }
        return [argument, extra].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// A command that fits what was typed, with the argument it will run with.
struct Match: Identifiable {
    let command: BlossomCommand
    let argument: String
    /// The command waits for text after its keyword, and none was typed.
    var needsTyped = false
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
        BlossomCommand(keyword: "search", kind: .webSearch),
        BlossomCommand(keyword: "settings", kind: .settings),
    ]

    @Published var commands: [BlossomCommand] {
        didSet { save() }
    }

    /// Commands added by an update, offered once to people who already have their own list.
    private static let webSearchOfferedKey = "webSearchOffered"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           var saved = try? JSONDecoder().decode([BlossomCommand].self, from: data) {
            // Version 1.2 brings Web Search: add "search" once, unless the list has a Web Search or the word is taken
            if !UserDefaults.standard.bool(forKey: Self.webSearchOfferedKey) {
                UserDefaults.standard.set(true, forKey: Self.webSearchOfferedKey)
                if !saved.contains(where: { $0.kind == .webSearch || $0.keyword.lowercased() == "search" }) {
                    saved.append(BlossomCommand(keyword: "search", kind: .webSearch))
                }
            }
            commands = saved
        } else {
            UserDefaults.standard.set(true, forKey: Self.webSearchOfferedKey)
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
        var value2: String?
    }

    var json: String {
        let items = commands.map { JSONCommand(keyword: $0.keyword, action: $0.kind, value: $0.argument.isEmpty ? nil : $0.argument, value2: $0.extra.isEmpty ? nil : $0.extra) }
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
                argument: item.value ?? "",
                extra: item.value2 ?? ""
            )
        }
        return nil
    }

    /// A command with the text typed after its keyword worked in.
    private func match(_ command: BlossomCommand, typed: String) -> Match {
        if command.usesTyped {
            guard !typed.isEmpty else { return Match(command: command, argument: command.fixedArgument, needsTyped: command.typedRequired) }
            // One word for the shell, whatever was typed: spaces, quotes and $ stay as they are
            let quoted = "'" + typed.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return Match(command: command, argument: [command.fixedArgument, quoted].filter { !$0.isEmpty }.joined(separator: " "))
        }
        let fixed = command.fixedArgument
        return Match(command: command, argument: fixed.isEmpty ? typed : fixed)
    }

    /// The commands that fit the query: "volume 30" fills in the argument, "vol" and "lume" find "volume".
    func matches(for query: String) -> [Match] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        let q = typed.lowercased()
        guard !q.isEmpty else {
            return commands.map { match($0, typed: "") }
        }

        var scored: [(score: Int, match: Match)] = []
        for command in commands {
            let keyword = command.keyword.lowercased()
            guard !keyword.isEmpty else { continue }

            if command.kind.takesArgument, command.fixedArgument.isEmpty || command.usesTyped, q.hasPrefix(keyword + " ") {
                let argument = typed.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
                scored.append((0, match(command, typed: argument)))
            } else if keyword == q {
                scored.append((0, match(command, typed: "")))
            } else if keyword.hasPrefix(q) {
                scored.append((1, match(command, typed: "")))
            } else if keyword.contains(q) || command.kind.title.lowercased().contains(q) {
                scored.append((2, match(command, typed: "")))
            }
        }
        // Sorting by score alone keeps the order from Settings within each group
        return scored.enumerated()
            .sorted { ($0.element.score, $0.offset) < ($1.element.score, $1.offset) }
            .map(\.element.match)
    }
}
