import AppKit
import SwiftUI

/// The settings window (design §8 "Ayarlar penceresi"): `SettingsView` in an ordinary window, made the first time it
/// is shown. Closing it only hides it.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let contentSize = NSSize(width: 720, height: 500)
    static let minimumSize = NSSize(width: 680, height: 460)

    /// Each time the window opens or comes to the front.
    var onShow: (() -> Void)?
    private let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
        super.init()
    }

    /// Brings the window to the front, on `section` when one is given. PhoneBox is an accessory app: nothing else would
    /// bring it forward.
    func show(section: SettingsSection? = nil) {
        if let section { model.section = section }
        let window = self.window ?? makeWindow()
        if !window.isVisible { model.copied = false }
        self.window = window
        onShow?()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                                    defer: false)
        window.title = "PhoneBox"
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        // The window keeps its own title, and SwiftUI adds no toolbar to it.
        hosting.sceneBridgingOptions = []
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(Self.contentSize)
        window.center()
        // Where the user left it last time, if anywhere.
        window.setFrameAutosaveName("PhoneBox Settings")
        window.delegate = self
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onShow?()
    }
}

/// ⌘W closes it: PhoneBox has no main menu that would.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
