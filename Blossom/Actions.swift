import AppKit

/// Runs an action. Returns what went wrong, or nil when it worked.
@MainActor
enum Actions {
    static func run(_ kind: ActionKind, argument: String) -> String? {
        switch kind {
        case .screensaver:
            let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            NSWorkspace.shared.openApplication(at: engine, configuration: .init())
            return nil

        case .lockScreen:
            // The same call as Control-Command-Q, from the private login framework
            typealias Lock = @convention(c) () -> Int32
            if let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
               let symbol = dlsym(login, "SACLockScreenImmediate") {
                _ = unsafeBitCast(symbol, to: Lock.self)()
                return nil
            }
            // Turning the display off locks too, when a password is asked for after sleep
            return launch("/usr/bin/pmset", ["displaysleepnow"])

        case .logout:
            // System Events asks first, like Apple menu → Log Out
            return appleScript(#"tell application "System Events" to log out"#)

        case .sleep:
            return launch("/usr/bin/pmset", ["sleepnow"])

        case .displaySleep:
            return launch("/usr/bin/pmset", ["displaysleepnow"])

        case .volume:
            guard let level = Int(argument.trimmingCharacters(in: CharacterSet(charactersIn: " %"))), (0...100).contains(level) else {
                return "Volume needs a number from 0 to 100, like “volume 30”"
            }
            return appleScript("set volume output volume \(level) without output muted")

        case .mute:
            return appleScript("set volume output muted not (output muted of (get volume settings))")

        case .darkMode:
            return appleScript(#"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#)

        case .lightMode:
            return appleScript(#"tell application "System Events" to tell appearance preferences to set dark mode to false"#)

        case .darkModeOn:
            return appleScript(#"tell application "System Events" to tell appearance preferences to set dark mode to true"#)

        case .openApp:
            let name = argument.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return "Which app? Type it after the keyword, like “open Safari”" }
            return launch("/usr/bin/open", ["-a", name], wait: true) == nil ? nil : "Couldn't find an app called “\(name)”"

        case .openURL:
            var link = argument.trimmingCharacters(in: .whitespaces)
            if !link.contains("://") { link = "https://" + link }
            guard let url = URL(string: link), url.host != nil else { return "“\(argument)” isn't a link" }
            NSWorkspace.shared.open(url)
            return nil

        case .webSearch:
            let query = argument.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return "What to search for? Type it after the keyword, like “search cats”" }
            guard let url = SearchEngine.url(for: query) else { return "The search engine's address is wrong: it needs {query} in it. Check Settings." }
            NSWorkspace.shared.open(url)
            return nil

        case .shell:
            guard !argument.isEmpty else { return "Which command? Type it after the keyword" }
            // Its output gets a window of its own
            OutputRunner.shared.run(argument)
            return nil

        case .settings:
            // Opened by the launcher itself
            return nil
        }
    }

    private static func appleScript(_ source: String) -> String? {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        return error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed"
    }

    private static func launch(_ path: String, _ arguments: [String], wait: Bool = false) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        guard wait else { return nil }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? nil : "\(path) exited with \(process.terminationStatus)"
    }
}
