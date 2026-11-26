import AppKit

@main
@MainActor
enum PhoneBoxApp {
    static func main() {
        // Helper modes, before anything of AppKit is touched (design §14): Claude Code runs `PhoneBox --claude-hook` for
        // its hook events, the uninstaller `PhoneBox --remove-claude-hooks`.
        switch CommandLine.arguments.dropFirst().first {
        case "--claude-hook":
            ClaudeHookForwarder.run()
            exit(0)
        case "--remove-claude-hooks":
            exit((try? ClaudeHooksFile().remove()) != nil ? 0 : 1)
        default:
            break
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // Route SIGTERM (e.g. `pkill`) through normal termination.
        signal(SIGTERM, SIG_IGN)
        // A write to a vanished peer must fail with an error, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler {
            MainActor.assumeIsolated { app.terminate(nil) }
        }
        termSource.resume()
        withExtendedLifetime((delegate, termSource)) {
            app.run()
        }
    }
}
