import AppKit
import SwiftUI

/// Where the launcher's look is kept, shared by Settings and the panel.
enum Prefs {
    static let showHints = "showHints"
    static let inputStyle = "inputStyle"
    static let inputFont = "inputFont"
    static let commandsFormat = "commandsFormat"
    static let theme = "theme"
    static let accent = "accent"
    static let searchEngine = "searchEngine"
    static let customSearchURL = "customSearchURL"
    static let latinLayout = "latinLayout"
}

enum InputStyle: String, CaseIterable, Identifiable {
    // The raw values are what earlier versions saved
    case graphic = "pretty"
    case terminal = "hacker"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphic: "Graphic"
        case .terminal: "Terminal"
        }
    }

    /// Terminal is always green; Graphic takes the colour picked in Settings.
    func accent(_ hex: String) -> Color {
        switch self {
        case .graphic: Accent.color(hex)
        case .terminal: Color(red: 0.22, green: 1, blue: 0.45)
        }
    }

    var cornerRadius: CGFloat {
        self == .terminal ? 6 : 20
    }

    var placeholder: String {
        self == .terminal ? "Type a command_" : "Type a command…"
    }

    /// The input's font: the family picked in Settings, or the style's own when none is.
    func font(family: String, size: CGFloat) -> Font {
        if !family.isEmpty { return .custom(family, size: size) }
        return .system(size: size, design: self == .terminal ? .monospaced : .default)
    }

    /// How far to move the font's text down so its capitals sit in the middle of the line.
    ///
    /// SwiftUI centres the line box, ascender to descender; a font with a tall ascender or a deep
    /// descender, like many Arabic or display faces, then draws its letters well off centre.
    func centring(family: String, size: CGFloat) -> CGFloat {
        let font = family.isEmpty
            ? NSFont.systemFont(ofSize: size)
            : NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) ?? NSFont.systemFont(ofSize: size)
        let boxMiddle = (font.ascender + font.descender) / 2
        return (boxMiddle - font.capHeight / 2).rounded()
    }
}

enum CommandsFormat: String, CaseIterable, Identifiable {
    case friendly, json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friendly: "User Friendly"
        case .json: "JSON"
        }
    }
}

enum Fonts {
    /// Every font family installed on this Mac, for the picker in Settings.
    static let families = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// Where Web Search sends the words: one of these, or an address of your own.
enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, brave, ecosia, startpage, yandex, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        case .yandex: "Yandex"
        case .custom: "Custom…"
        }
    }

    /// The search address, with {query} where the words go.
    var template: String {
        switch self {
        case .google: "https://www.google.com/search?q={query}"
        case .duckDuckGo: "https://duckduckgo.com/?q={query}"
        case .bing: "https://www.bing.com/search?q={query}"
        case .brave: "https://search.brave.com/search?q={query}"
        case .ecosia: "https://www.ecosia.org/search?q={query}"
        case .startpage: "https://www.startpage.com/do/search?q={query}"
        case .yandex: "https://yandex.com/search/?text={query}"
        case .custom: UserDefaults.standard.string(forKey: Prefs.customSearchURL) ?? ""
        }
    }

    static var current: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: Prefs.searchEngine) ?? "") ?? .google
    }

    /// Whether this engine's address can take a search: a custom one has to say where the words go.
    var isUsable: Bool { template.contains("{query}") && Self.address(template, query: "x") != nil }

    /// The page to open for these words with the engine picked in Settings; nil when the address is no good.
    static func url(for query: String) -> URL? {
        address(current.template, query: query)
    }

    private static func address(_ template: String, query: String) -> URL? {
        // Everything that means something in an address is escaped, so "a&b=c" stays one search
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?/:;@$,")
        guard template.contains("{query}"), let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: template.replacingOccurrences(of: "{query}", with: encoded)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return url
    }
}
