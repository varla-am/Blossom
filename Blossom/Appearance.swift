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
