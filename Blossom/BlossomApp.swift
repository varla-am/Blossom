import AppKit
import SwiftUI

@main
struct BlossomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button("About Blossom") {
                // A menu bar app isn't in front, so the panel would open behind everything
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            Button("Open Blossom") { delegate.launcher.show() }
            Button("Settings…") { delegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Blossom") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: SakuraShape.menuBarImage)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = CommandStore.shared
    private var settingsWindow: NSWindow?

    lazy var launcher = LauncherController(store: store) { [weak self] in
        self?.showSettings()
    }

    lazy var hotKey = HotKey { [weak self] in
        self?.launcher.toggle()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey.register()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, hotKey: hotKey)))
            window.title = "Blossom Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            settingsWindow = window
            letGoOfFields(in: window)
        }
        // A menu bar app has no menus of its own, so while it's in front the menu bar would sit empty.
        // While Settings is open Blossom is an ordinary app: its menus, and a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// A field in Settings lets go of the cursor on a click anywhere else, on Escape, and on Return in a one-line field.
    private func letGoOfFields(in window: NSWindow) {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak window] event in
            guard let window, event.window === window else { return event }
            let editing = window.firstResponder as? NSTextView

            switch event.type {
            case .leftMouseDown:
                guard editing != nil else { return event }
                // Still typing when the click lands in a field or the JSON editor
                let hit = window.contentView?.hitTest(event.locationInWindow)
                var view = hit
                while let current = view {
                    if current is NSTextField || current is NSTextView { return event }
                    view = current.superview
                }
                window.makeFirstResponder(nil)
            case .keyDown where editing != nil && event.keyCode == 53: // Escape
                window.makeFirstResponder(nil)
                return nil
            case .keyDown where editing?.isFieldEditor == true && (event.keyCode == 36 || event.keyCode == 76): // Return
                // The field takes the Return first, then lets go
                DispatchQueue.main.async { window.makeFirstResponder(nil) }
            default:
                break
            }
            return event
        }
    }
}
