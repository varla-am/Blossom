import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

/// A key with its modifiers, as recorded in Settings.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon's modifier bits: cmdKey, shiftKey, optionKey, controlKey.
    var modifiers: UInt32
    /// The key's own name, like "Space" or "B".
    var key: String

    static let optionSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space")

    /// The key code of a shortcut made of modifiers alone, like ⇧⌥: pressed together and let go.
    static let modifiersOnly = UInt32.max

    var isModifiersOnly: Bool { keyCode == Self.modifiersOnly }

    /// The modifiers as AppKit names them.
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    /// Two or more modifiers, pressed together and let go with no key between.
    init?(modifiers flags: NSEvent.ModifierFlags) {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        // One alone would fire on every tap of Shift
        guard modifiers.nonzeroBitCount >= 2 else { return nil }
        self.init(keyCode: Self.modifiersOnly, modifiers: modifiers, key: "")
    }

    /// "⌃⌥⇧⌘ Space", in Apple's order.
    var title: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        if isModifiersOnly { return symbols }
        return symbols.isEmpty ? key : "\(symbols) \(key)"
    }

    /// The shortcut a key press makes, or nil when it can't be one: no modifier on a key that types.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        let code = Int(event.keyCode)
        let name = Self.names[code] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        // F-key codes aren't in order (F1 is 122, F20 is 90), so this is a list, not a range
        let isFunctionKey = Self.functionKeys.contains(code)
        // Shift alone would steal a capital letter from every app
        guard isFunctionKey || modifiers & ~UInt32(shiftKey) != 0 else { return nil }
        self.init(keyCode: UInt32(code), modifiers: modifiers, key: name)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    /// Keys whose character doesn't say what they are.
    private static let names: [Int: String] = {
        var names = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
            kVK_ForwardDelete: "⌦", kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "Home", kVK_End: "End",
            kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        ]
        for (n, code) in functionKeys.enumerated() { names[code] = "F\(n + 1)" }
        return names
    }()
}

/// A system-wide shortcut through Carbon: it needs no Accessibility permission.
@MainActor
final class HotKey: ObservableObject {
    private static let key = "shortcut"

    @Published private(set) var isRegistered = false
    /// A modifiers-only shortcut listens to the whole keyboard, which macOS allows only with Accessibility.
    @Published private(set) var needsAccessibility = false
    @Published var shortcut: Shortcut {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: Self.key)
            register()
        }
    }

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private var monitors: [Any] = []
    private var trustCheck: Timer?
    /// The shortcut's modifiers are all down and no key has been pressed since.
    private var armed = false

    init(action: @escaping () -> Void) {
        self.action = action
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .optionSpace
        }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register() {
        unregister()
        if shortcut.isModifiersOnly {
            watchModifiers()
            return
        }
        // "BLSM"
        let id = EventHotKeyID(signature: OSType(0x424C_534D), id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        isRegistered = status == noErr
    }

    /// Lets go of the shortcut, so Settings can record it, or another, as a plain key press.
    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        trustCheck?.invalidate()
        trustCheck = nil
        armed = false
        needsAccessibility = false
    }

    private func watchModifiers() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else {
            needsAccessibility = true
            isRegistered = false
            // Starts listening once the person turns Blossom on in Privacy & Security
            trustCheck = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if AXIsProcessTrusted() { self?.register() }
                }
            }
            return
        }

        let target = shortcut.modifierFlags
        let handle = { [weak self] (event: NSEvent) in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .keyDown {
                    self.armed = false
                    return
                }
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if flags == target {
                    self.armed = true
                } else if flags.isEmpty {
                    if self.armed { self.action() }
                    self.armed = false
                } else if !target.isSuperset(of: flags) {
                    // Another modifier joined in: not this shortcut
                    self.armed = false
                }
            }
        }
        // Global for other apps, local for Blossom's own windows
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handle) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { handle($0); return $0 }) {
            monitors.append(local)
        }
        isRegistered = true
    }
}
