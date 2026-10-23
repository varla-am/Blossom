import AppKit
import SwiftUI

/// What a shell command has printed so far, and whether it's still going.
@MainActor
final class OutputModel: ObservableObject {
    enum State: Equatable {
        case running
        case finished(Int32)
        case failed(String)
    }

    /// Only the end is kept, so a command that never stops can't fill the memory.
    private static let limit = 400_000

    @Published private(set) var text = ""
    @Published private(set) var state = State.running

    /// The last bytes of a chunk, when they cut a character in half.
    private var pending = Data()

    func append(_ data: Data) {
        pending.append(data)
        var chunk = ""
        for cut in 0...min(3, pending.count) {
            if let decoded = String(data: pending.dropLast(cut), encoding: .utf8) {
                chunk = decoded
                pending = Data(pending.suffix(cut))
                break
            }
            if cut == min(3, pending.count) {
                chunk = String(decoding: pending, as: UTF8.self)
                pending = Data()
            }
        }
        text += Self.cleaned(chunk)
        if text.count > Self.limit {
            text = "…\n" + String(text.suffix(Self.limit))
        }
    }

    func finish(_ status: Int32) { state = .finished(status) }
    func fail(_ message: String) { state = .failed(message) }

    /// Colour codes and cursor moves mean nothing here; a lone carriage return (a progress bar) starts a new line.
    private static func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

/// A borderless window that can take keys, like the launcher's panel. Escape and ⌘W close it.
private final class OutputWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Runs a shell command and shows what it prints in a window of its own, drawn like the launcher, with no prompt to type into.
@MainActor
final class OutputRunner: NSObject, NSWindowDelegate {
    static let shared = OutputRunner()

    private static let size = NSSize(width: LauncherController.width, height: 380)

    private struct Run {
        let process: Process
        let window: NSWindow
    }

    private var runs: [ObjectIdentifier: Run] = [:]

    func run(_ command: String) {
        let model = OutputModel()
        let window = OutputWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = command
        window.contentView = NSHostingView(rootView: OutputView(model: model, command: command) { [weak window] in
            window?.close()
        })
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 320, height: 160)
        window.isReleasedWhenClosed = false
        window.delegate = self
        place(window)

        let process = Process()
        // A login shell, so aliases and PATH from ~/.zprofile work like in Terminal
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        // Nothing to type into: a command that asks a question gets the end of the input, not a hang
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { @MainActor in model.append(data) }
                return
            }
            // End of output: now the exit status is there to be read
            handle.readabilityHandler = nil
            DispatchQueue.global().async {
                process.waitUntilExit()
                let status = process.terminationStatus
                Task { @MainActor in model.finish(status) }
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            model.fail(error.localizedDescription)
        }

        runs[ObjectIdentifier(window)] = Run(process: process, window: window)
        // A menu bar app isn't in front, so the window would open behind everything
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Where the launcher opens: on the screen with the mouse, its top a fifth of the way down.
    /// Each window already open pushes the next down and to the side, so they don't hide each other.
    private func place(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { window.center(); return }
        let step = CGFloat(runs.count % 6) * 28
        window.setFrame(
            NSRect(
                x: frame.midX - Self.size.width / 2 + step,
                y: frame.maxY - frame.height / 5 - Self.size.height - step,
                width: Self.size.width,
                height: Self.size.height
            ),
            display: false
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let run = runs.removeValue(forKey: ObjectIdentifier(window)) else { return }
        if run.process.isRunning { run.process.terminate() }
    }
}

/// The red dot that closes the window: Aqua's is a gel; the others are flat.
private struct CloseDot: View {
    let style: InputStyle
    let theme: Theme
    let action: () -> Void
    @State private var isHovered = false

    private static let red = Color(red: 1, green: 0.37, blue: 0.34)

    var body: some View {
        Button(action: action) {
            ZStack {
                if style == .graphic, theme == .aqua {
                    AquaGel(color: Self.red, radius: 7)
                } else {
                    Circle().fill(Self.red)
                        .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                }
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.55))
                    .opacity(isHovered ? 1 : 0)
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Close")
    }
}

struct OutputView: View {
    @ObservedObject var model: OutputModel
    let command: String
    let close: () -> Void
    @AppStorage(Prefs.inputStyle) private var styleRaw = InputStyle.graphic.rawValue
    @AppStorage(Prefs.inputFont) private var fontFamily = ""
    @AppStorage(Prefs.theme) private var themeRaw = Theme.standard.rawValue
    @AppStorage(Prefs.accent) private var accentHex = Accent.defaultHex

    private var style: InputStyle { InputStyle(rawValue: styleRaw) ?? .graphic }
    private var theme: Theme { Theme(rawValue: themeRaw) ?? .standard }
    private var accent: Color { style.accent(accentHex) }
    private var radius: CGFloat { style == .terminal ? style.cornerRadius : theme.panelRadius }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CloseDot(style: style, theme: theme, action: close)
                if style == .terminal {
                    Text("❯")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                }
                Text(command)
                    .font(style.font(family: fontFamily, size: 15).weight(.medium))
                    .foregroundStyle(style == .terminal ? accent : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)

            divider

            ScrollViewReader { proxy in
                ScrollView {
                    Text(shown)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(model.text.isEmpty ? .secondary : (style == .terminal ? accent : .primary))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: model.text) {
                    proxy.scrollTo("end")
                }
            }

            divider

            HStack(spacing: 6) {
                switch model.state {
                case .running:
                    ProgressView().controlSize(.small)
                    Text("Running…")
                case .finished(0):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(style == .terminal ? accent : .green)
                    Text("Done")
                case .finished(let status):
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Exited with \(status)")
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(message).lineLimit(1)
                }
                Spacer()
            }
            .font(style == .terminal ? .system(size: 12, design: .monospaced) : .callout)
            .foregroundStyle(style == .terminal ? accent.opacity(0.8) : Color.secondary)
            .padding(.horizontal, 18)
            .frame(height: 32)
        }
        .frame(minWidth: 320, minHeight: 160)
        .background(PanelSurface(style: style, theme: theme, accent: accent, radius: radius))
        .clipShape(shape)
    }

    private var divider: some View {
        Rectangle()
            .fill(style == .terminal ? accent.opacity(0.35) : Color.primary.opacity(0.1))
            .frame(height: 1)
    }

    private var shown: String {
        if !model.text.isEmpty { return model.text }
        return model.state == .running ? "" : "(no output)"
    }
}
