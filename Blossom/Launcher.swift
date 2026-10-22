import AppKit
import SwiftUI

/// A borderless panel that can still take typing, like Spotlight's.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var query = "" {
        didSet {
            selection = 0
            error = nil
            // Typing leaves the history; a recalled command doesn't
            if !isRecalling { historyIndex = nil }
        }
    }
    @Published var selection = 0
    @Published var error: String?
    /// Bumped on each show, so the field takes focus again.
    @Published var shown = 0
    /// The row being run, while it blinks; nothing else can run meanwhile.
    @Published var pressed: Int?
    /// Whether the pressed row's highlight is on, at this moment of the blink.
    @Published var isLit = true

    let store: CommandStore

    private static let historyKey = "history"
    private static let historyLimit = 50

    /// What was run, oldest first, as it was typed: "volume 30".
    private(set) var history = UserDefaults.standard.stringArray(forKey: LauncherModel.historyKey) ?? []
    /// Which entry ↑ and ↓ show now; nil while not looking back.
    private(set) var historyIndex: Int?
    private var isRecalling = false

    init(store: CommandStore) {
        self.store = store
    }

    var results: [Match] { store.matches(for: query) }

    var isBrowsingHistory: Bool { historyIndex != nil }

    func remember(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // Running the same thing twice in a row keeps one entry, like a shell
        if history.last != text { history.append(text) }
        history = Array(history.suffix(Self.historyLimit))
        UserDefaults.standard.set(history, forKey: Self.historyKey)
    }

    /// One step back (older) or forward (newer). False when there's nowhere to go.
    func recall(older: Bool) -> Bool {
        guard !history.isEmpty else { return false }
        let next: Int?
        switch (historyIndex, older) {
        case (nil, true): next = history.count - 1
        case (nil, false): return false
        case let (index?, true): next = max(index - 1, 0)
        case let (index?, false): next = index + 1 < history.count ? index + 1 : nil
        }
        isRecalling = true
        query = next.map { history[$0] } ?? ""
        isRecalling = false
        historyIndex = next
        return true
    }
}

@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 640

    /// Tall with the list of hints, just the field without, and a line more for an error.
    static func height(hints: Bool, error: Bool) -> CGFloat {
        hints ? 392 : (error ? 100 : 60)
    }

    let model: LauncherModel
    private let panel: LauncherPanel
    private var keyMonitor: Any?
    private let openSettings: () -> Void

    init(store: CommandStore, openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        model = LauncherModel(store: store)
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height(hints: true, error: false)),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LauncherView(model: model) { [weak self] index in
            self?.press(index)
        })
    }

    var isShown: Bool { panel.isVisible }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        model.query = ""
        model.shown += 1

        // On the screen with the mouse, its top a fifth of the way down
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            fit(top: frame.maxY - frame.height / 5, midX: frame.midX)
        }
        panel.makeKeyAndOrderFront(nil)
        startKeys()
    }

    /// Sizes the panel for the hints setting and any error, keeping its top where it is.
    private func fit(top: CGFloat? = nil, midX: CGFloat? = nil) {
        let hints = UserDefaults.standard.object(forKey: Prefs.showHints) as? Bool ?? true
        let height = Self.height(hints: hints, error: model.error != nil)
        let top = top ?? panel.frame.maxY
        let midX = midX ?? panel.frame.midX
        panel.setFrame(NSRect(x: midX - Self.width / 2, y: top - height, width: Self.width, height: height), display: true)
    }

    func hide() {
        stopKeys()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Blinks the row, like a menu item when it's chosen, then runs it. Aqua's gel is pushed in instead.
    private func press(_ index: Int) {
        guard model.pressed == nil, model.results.indices.contains(index) else { return }
        model.selection = index
        model.pressed = index
        Task { @MainActor in
            for lit in [false, true, false, true] {
                model.isLit = lit
                try? await Task.sleep(for: .milliseconds(60))
            }
            model.pressed = nil
            run(at: index)
        }
    }

    private func run(at index: Int) {
        let results = model.results
        guard results.indices.contains(index) else { return }
        let match = results[index]
        // What brings this back with ↑: the text as typed, or the command picked from the list
        let typed = model.query.trimmingCharacters(in: .whitespaces)
        model.remember(typed.isEmpty ? match.command.keyword : typed)

        hide()
        if match.command.kind == .settings {
            openSettings()
            return
        }
        if let error = Actions.run(match.command.kind, argument: match.argument) {
            // Back again with what went wrong, and the query as it was
            let query = model.query
            show()
            model.query = query
            model.error = error
            fit()
        }
    }

    // Arrows, Return and Escape, before the text field sees them
    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let count = self.model.results.count
            switch Int(event.keyCode) {
            case 125: // ↓: newer in the history, or down the list
                if self.model.isBrowsingHistory {
                    _ = self.model.recall(older: false)
                } else if count > 0 {
                    self.model.selection = (self.model.selection + 1) % count
                }
            case 126: // ↑: back through the history from an empty field, or up the list
                if self.model.isBrowsingHistory || self.model.query.isEmpty, self.model.recall(older: true) {
                    break
                }
                if count > 0 { self.model.selection = (self.model.selection - 1 + count) % count }
            case 36, 76: // Return, keypad Enter
                self.press(self.model.selection)
            case 53: // Escape
                self.hide()
            default:
                return event
            }
            return nil
        }
    }

    private func stopKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject private var store: CommandStore
    let run: (Int) -> Void
    @FocusState private var isFocused: Bool
    @AppStorage(Prefs.showHints) private var showHints = true
    @AppStorage(Prefs.inputStyle) private var styleRaw = InputStyle.graphic.rawValue
    @AppStorage(Prefs.inputFont) private var fontFamily = ""
    @AppStorage(Prefs.theme) private var themeRaw = Theme.standard.rawValue
    @AppStorage(Prefs.accent) private var accentHex = Accent.defaultHex

    init(model: LauncherModel, run: @escaping (Int) -> Void) {
        self.model = model
        self.store = model.store
        self.run = run
    }

    private var style: InputStyle { InputStyle(rawValue: styleRaw) ?? .graphic }
    private var theme: Theme { Theme(rawValue: themeRaw) ?? .standard }
    private var accent: Color { style.accent(accentHex) }
    private var radius: CGFloat { style == .terminal ? style.cornerRadius : theme.panelRadius }

    var body: some View {
        let results = model.results
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if style == .terminal {
                    Text("❯")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                } else {
                    SakuraMark(accent: accent)
                }
                TextField(style.placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(style.font(family: fontFamily, size: 22))
                    .offset(y: style.centring(family: fontFamily, size: 22))
                    .foregroundStyle(style == .terminal ? accent : .primary)
                    .tint(accent)
                    .focused($isFocused)
            }
            .padding(.horizontal, 18)
            .frame(height: 60)

            if let error = model.error {
                if showHints { divider }
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(style == .terminal ? .system(size: 13, design: .monospaced) : .body)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, showHints ? 10 : 0)
                    .padding(.bottom, showHints ? 0 : 14)
            }

            if showHints {
                if model.error == nil { divider }
                if results.isEmpty {
                    Text("No command called “\(model.query)”. Add one in Settings.")
                        .font(style.font(family: fontFamily, size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, match in
                                    ResultRow(
                                        match: match,
                                        isSelected: index == model.selection,
                                        pressed: model.pressed == index,
                                        isLit: model.isLit,
                                        style: style, theme: theme, accent: accent, fontFamily: fontFamily
                                    )
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture { run(index) }
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: model.selection) { _, selection in
                            proxy.scrollTo(selection)
                        }
                    }
                }
            }
        }
        .frame(width: LauncherController.width, height: LauncherController.height(hints: showHints, error: model.error != nil))
        .background(PanelSurface(style: style, theme: theme, accent: accent, radius: radius))
        .clipShape(shape)
        .onChange(of: model.shown) {
            isFocused = true
        }
        .onAppear { isFocused = true }
    }

    private var divider: some View {
        Rectangle()
            .fill(style == .terminal ? accent.opacity(0.35) : Color.primary.opacity(0.1))
            .frame(height: 1)
    }
}

private struct ResultRow: View {
    let match: Match
    let isSelected: Bool
    /// Being run: blinking, or for Aqua, pushed in.
    let pressed: Bool
    let isLit: Bool
    let style: InputStyle
    let theme: Theme
    let accent: Color
    let fontFamily: String
    @State private var isHovered = false

    private var isAqua: Bool { style == .graphic && theme == .aqua }

    /// The highlight is drawn: selected, and not in the dark half of a blink.
    private var isHighlighted: Bool { isSelected && (isAqua || !pressed || isLit) }

    /// On the highlight: black on green, or whichever of black and white reads on the accent.
    private var ink: Color { style == .terminal ? .black : Accent.ink(on: accent) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: match.command.kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IconTile.ink(style: style, theme: theme, accent: accent, isSelected: isHighlighted))
                .shadow(color: .black.opacity(isAqua ? 0.3 : 0), radius: 1, y: 1)
                .frame(width: 30, height: 30)
                .background(IconTile(style: style, theme: theme, accent: accent, isSelected: isHighlighted, isPressed: isAqua && pressed))
            VStack(alignment: .leading, spacing: 1) {
                Text(match.command.keyword)
                    .font(style.font(family: fontFamily, size: 15).weight(.medium))
                Text(subtitle)
                    .font(style.font(family: fontFamily, size: 12))
                    .foregroundStyle(isHighlighted ? ink.opacity(0.75) : .secondary)
            }
            Spacer()
            if isHighlighted {
                Image(systemName: "return")
                    .foregroundStyle(ink.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .foregroundStyle(isHighlighted ? ink : (style == .terminal ? accent : .primary))
        .background {
            if isHighlighted {
                SelectionSurface(style: style, theme: theme, accent: accent, isPressed: isAqua && pressed)
            } else if isHovered {
                HoverSurface(style: style, theme: theme, accent: accent)
            }
        }
        // Aqua's gel sinks a little when it's pushed
        .scaleEffect(isAqua && pressed ? 0.985 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.spring(duration: 0.18), value: pressed)
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        let kind = match.command.kind
        if !match.argument.isEmpty { return "\(kind.title) · \(match.argument)" }
        if kind.takesArgument { return "\(kind.title) · type \(match.command.keyword) \(kind.argumentHint)" }
        return kind.title
    }
}
