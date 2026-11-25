import AppKit

@main
@MainActor
enum PhoneBoxApp {
    static func main() {
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
