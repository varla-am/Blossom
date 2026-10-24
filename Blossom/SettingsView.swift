import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CommandStore
    @ObservedObject var hotKey: HotKey
    @AppStorage(Prefs.showHints) private var showHints = true
    @AppStorage(Prefs.inputStyle) private var styleRaw = InputStyle.graphic.rawValue
    @AppStorage(Prefs.inputFont) private var fontFamily = ""
    @AppStorage(Prefs.commandsFormat) private var formatRaw = CommandsFormat.friendly.rawValue
    @AppStorage(Prefs.theme) private var themeRaw = Theme.standard.rawValue
    @AppStorage(Prefs.accent) private var accentHex = Accent.defaultHex
    @AppStorage(Prefs.searchEngine) private var searchEngineRaw = SearchEngine.google.rawValue
    @AppStorage(Prefs.customSearchURL) private var customSearchURL = ""
    @AppStorage(Prefs.latinLayout) private var latinLayout = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmsRestore = false

    private var style: InputStyle { InputStyle(rawValue: styleRaw) ?? .graphic }
    private var format: CommandsFormat { CommandsFormat(rawValue: formatRaw) ?? .friendly }
    private var theme: Theme { Theme(rawValue: themeRaw) ?? .standard }

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .tint(Accent.color(accentHex))
        .frame(minWidth: 720, minHeight: 560)
    }

    private var general: some View {
        Form {
            Section("Open Blossom") {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(hotKey: hotKey)
                }
                if hotKey.needsAccessibility {
                    HStack {
                        Label("⇧⌥-style shortcuts need Accessibility, to see modifier keys in every app.", systemImage: "hand.raised.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                } else if !hotKey.isRegistered {
                    Label("Another app already uses this shortcut. Pick a different one.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Toggle("Open at Login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, isOn in
                        do {
                            if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).foregroundStyle(.red)
                }
                Toggle(isOn: $latinLayout) {
                    Text("Type in Latin letters")
                    Text("Switches to your last Latin keyboard layout while Blossom is open, and back when it closes. For when the keyboard is on Russian and you want to type “open”.")
                }
            }

            Section {
                Picker("Search engine", selection: $searchEngineRaw) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.title).tag(engine.rawValue)
                    }
                }
                if searchEngineRaw == SearchEngine.custom.rawValue {
                    TextField("Address", text: $customSearchURL, prompt: Text("https://example.com/search?q={query}"))
                        .textFieldStyle(.roundedBorder)
                    if !SearchEngine.custom.isUsable {
                        Label("The address must start with https:// and have {query} where the words go.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Web Search")
            } footer: {
                Text("“search cats” opens the results in your browser. The Web Search command picks the engine from here.")
                    .foregroundStyle(.secondary)
            }

            Section("Look") {
                Toggle(isOn: $showHints) {
                    Text("Hints")
                    Text("The list of commands under the field. Off, Blossom is one field, and Return runs the best match.")
                }
                Picker("Style", selection: $styleRaw) {
                    ForEach(InputStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Font", selection: $fontFamily) {
                    Text(style == .terminal ? "System Mono" : "System").tag("")
                    Divider()
                    ForEach(Fonts.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                if style == .graphic {
                    Picker("Theme", selection: $themeRaw) {
                        ForEach(Theme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Accent") {
                        AccentPicker(hex: $accentHex)
                    }
                }
                Preview(style: style, theme: theme, accent: style.accent(accentHex), fontFamily: fontFamily)
            }

            Section {
                Picker("Edit as", selection: $formatRaw) {
                    ForEach(CommandsFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                switch format {
                case .friendly:
                    CommandColumns {
                        Color.clear.frame(width: 20, height: 1)
                        Text("Keyword").frame(width: 120, alignment: .leading)
                        Text("Action").frame(width: 180, alignment: .leading)
                        Text("Value").frame(width: 130, alignment: .leading)
                        Text("Value 2").frame(width: 110, alignment: .leading)
                        Color.clear.frame(width: 20, height: 1)
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach($store.commands) { $command in
                        CommandRow(command: $command) {
                            store.commands.removeAll { $0.id == command.id }
                        }
                    }
                    .onMove { store.commands.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        Button("Add Command", systemImage: "plus") {
                            store.commands.append(BlossomCommand(keyword: "new", kind: .openApp))
                        }
                        Spacer()
                        Button("Restore Defaults") { confirmsRestore = true }
                    }
                case .json:
                    JSONEditor(store: store)
                }
            } header: {
                Text("Commands")
            } footer: {
                Text(format == .json
                     ? "Each command is {\"keyword\", \"action\", \"value\"}; value and value2 are optional. Web Search is \"webSearch\". Changes apply as soon as the JSON is valid."
                     : "Leave the value empty on Set volume, Open app, Open website, Web Search or Run shell command, and Blossom takes it from what you type: “volume 30”. On Run shell command with a Value, what you type goes after it: Value “claude -p” makes “claude hello” run claude -p 'hello'. Value 2 adds fixed text instead.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore the default commands?", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("Restore Defaults", role: .destructive) { store.restoreDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The commands you added or changed will be replaced by the ones Blossom came with.")
        }
    }
}

/// What this is, which version, and where to find it.
private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Blossom").font(.system(size: 28, weight: .semibold))
            Text(version).foregroundStyle(.secondary)
            Text("A launcher for your Mac, opened by a shortcut and run with a few words.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 4)
            Text("Blossom runs on your Mac and doesn't connect to the internet. Web Search only hands your words to your browser.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 18) {
                Link("GitHub", destination: URL(string: "https://github.com/varla-am/Blossom")!)
                Link("Releases", destination: URL(string: "https://github.com/varla-am/Blossom/releases")!)
                Link("MIT License", destination: URL(string: "https://github.com/varla-am/Blossom/blob/main/LICENSE")!)
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// The system's colour palette, and a way back to sakura pink.
private struct AccentPicker: View {
    @Binding var hex: String

    var body: some View {
        HStack(spacing: 8) {
            if hex.uppercased() != Accent.defaultHex {
                Button("Reset") { hex = Accent.defaultHex }
                    .buttonStyle(.borderless)
            }
            ColorPicker("", selection: Binding(
                get: { Accent.color(hex) },
                set: { hex = Accent.hex($0) }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}

/// The input field as the launcher will draw it.
private struct Preview: View {
    let style: InputStyle
    let theme: Theme
    let accent: Color
    let fontFamily: String

    var body: some View {
        let radius = style == .terminal ? style.cornerRadius : theme.panelRadius * 0.75
        let ink = style == .terminal ? Color.black : Accent.ink(on: accent)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if style == .terminal {
                    Text("❯").font(.system(size: 18, weight: .bold, design: .monospaced))
                } else {
                    SakuraMark(accent: accent, size: 20)
                }
                Text("volume 30")
                    .font(style.font(family: fontFamily, size: 18))
                    .offset(y: style.centring(family: fontFamily, size: 18))
                    .foregroundStyle(style == .terminal ? accent : .primary)
                Spacer()
            }
            .foregroundStyle(accent)
            .frame(height: 34)
            .padding(.horizontal, 8)

            // A selected row, to show off the theme
            HStack(spacing: 10) {
                Image(systemName: ActionKind.volume.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IconTile.ink(style: style, theme: theme, accent: accent, isSelected: true))
                    .frame(width: 26, height: 26)
                    .background(IconTile(style: style, theme: theme, accent: accent, isSelected: true))
                Text("Set Volume · 30")
                    .font(style.font(family: fontFamily, size: 13).weight(.medium))
                    .foregroundStyle(ink)
                Spacer()
                Image(systemName: "return").foregroundStyle(ink.opacity(0.75))
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(SelectionSurface(style: style, theme: theme, accent: accent))
        }
        .padding(10)
        .background(PanelSurface(style: style, theme: theme, accent: accent, radius: radius))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .padding(.vertical, 4)
    }
}

/// All the commands as JSON text, applied whenever it parses.
private struct JSONEditor: View {
    @ObservedObject var store: CommandStore
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 320)
                .onChange(of: text) { _, new in
                    // Smart quotes, if macOS put them in, aren't JSON
                    let plain = new.replacingOccurrences(of: "[“”„]", with: "\"", options: .regularExpression)
                    guard plain == new else {
                        text = plain
                        return
                    }
                    error = store.apply(json: new)
                }
            HStack {
                if let error {
                    Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                } else {
                    Label("Applied", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("Format") { text = store.json }
                    .disabled(error != nil)
            }
            .font(.callout)
        }
        .onAppear { text = store.json }
    }
}

/// The columns every command row and their header share, so the fields line up under their titles.
private struct CommandColumns<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10) {
            GridRow { content }
        }
    }
}

private struct CommandRow: View {
    @Binding var command: BlossomCommand
    let remove: () -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10) {
            GridRow {
                Image(systemName: command.kind.symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                TextField("", text: $command.keyword, prompt: Text("Keyword"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 120)
                Picker("", selection: $command.kind) {
                    ForEach(ActionKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 180, alignment: .leading)
                TextField("", text: $command.argument, prompt: Text(command.kind.takesArgument ? "Typed, or \(command.kind.argumentHint)" : "None"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 130)
                    .disabled(!command.kind.takesArgument)
                TextField("", text: $command.extra, prompt: Text(command.kind == .shell ? "Typed" : "None"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 110)
                    .disabled(command.kind != .shell)
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .frame(width: 20)
            }
        }
    }
}

/// Click, then press the keys: any combination with a modifier, or an F key on its own.
private struct ShortcutRecorder: View {
    @ObservedObject var hotKey: HotKey
    @State private var isRecording = false
    @State private var monitors: [Any] = []
    /// The most modifiers held at once since the last key, for a ⇧⌥-style shortcut.
    @State private var peak: NSEvent.ModifierFlags = []

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Press Keys…" : hotKey.shortcut.title)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            if isRecording {
                Text("Esc to cancel").foregroundStyle(.secondary).font(.callout)
            } else if hotKey.shortcut != .optionSpace {
                Button("Reset") { hotKey.shortcut = .optionSpace }
                    .buttonStyle(.borderless)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        // Without letting go, pressing the current shortcut would open Blossom instead of reaching here
        hotKey.unregister()
        isRecording = true
        peak = []
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            peak = []
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stop()
            } else if let shortcut = Shortcut(event: event) {
                hotKey.shortcut = shortcut
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
        // Modifiers pressed together and let go, with no key between
        let modifiers = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if flags.isEmpty {
                if let shortcut = Shortcut(modifiers: peak) {
                    hotKey.shortcut = shortcut
                    stop()
                }
                peak = []
            } else {
                peak.formUnion(flags)
            }
            return event
        }
        monitors = [keys, modifiers].compactMap { $0 }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if isRecording { hotKey.register() }
        isRecording = false
    }
}
