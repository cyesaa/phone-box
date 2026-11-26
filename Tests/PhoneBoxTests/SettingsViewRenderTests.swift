import AppKit
import PhoneBoxCore
import SwiftUI
import Testing
@testable import PhoneBox

/// The settings window cannot be opened in a test, and running PhoneBox would start its server: this draws
/// `SettingsView` with `SettingsModel.sample` into PNG files under the temporary folder, every section in Turkish
/// (light and dark) and in English (light), to look at. Opening windows holds the main thread for seconds, which
/// makes the timing tests that run beside it fail, so this runs only in `make test-ui`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHONEBOX_UI"] == "1"))
struct SettingsViewRenderTests {
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PhoneBoxSettings", isDirectory: true)

    @Test func drawsEverySection() throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let variants: [(language: String, appearance: NSAppearance.Name, name: String)] = [
            ("tr", .aqua, "light"), ("tr", .darkAqua, "dark"), ("en", .aqua, "light"),
        ]
        for variant in variants {
            try inLanguage(variant.language) {
                for section in SettingsSection.allCases {
                    let model = SettingsModel.sample
                    model.section = section
                    let png = try Self.render(SettingsView(model: model), appearance: variant.appearance)
                    let url = Self.folder.appendingPathComponent("settings-\(section.rawValue)-\(variant.language)-\(variant.name).png")
                    try png.write(to: url)
                    print("Settings window drawn: \(url.path)")
                    #expect(png.count > 20_000, "\(url.lastPathComponent)")
                }
            }
        }
    }

    /// The other states each section can be in: cable mode, a Claude Code failure, Open at Login waiting for approval, an
    /// update.
    @Test func drawsTheOtherStates() throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try inLanguage("tr") {
            for section in SettingsSection.allCases {
                let model = SettingsModel.sample
                model.section = section
                model.mode = .cable
                model.phones = PhoneCounts(onCable: 0, overWiFi: 0, waitingForCable: 1)
                model.status = .waitingForCable
                model.claudeHooksInstalled = false
                model.claudeFailure = L10n.claudeSettingsNotJSON
                model.claudeSettingsExists = false
                model.loginItem = .needsApproval
                model.update = .available(LatestRelease(version: AppVersion("0.5.0")!,
                                                        pageURL: UpdateCheck.repositoryURL))
                model.availableUpdate = "0.5.0"
                model.copied = true
                let png = try Self.render(SettingsView(model: model), appearance: .aqua)
                let url = Self.folder.appendingPathComponent("settings-\(section.rawValue)-tr-states.png")
                try png.write(to: url)
                print("Settings window drawn: \(url.path)")
                #expect(png.count > 20_000, "\(url.lastPathComponent)")
            }
        }
    }

    /// The whole window, title bar included, as a PNG.
    static func render(_ view: some View, appearance: NSAppearance.Name) throws -> Data {
        let size = SettingsWindowController.contentSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PhoneBox"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.setContentSize(size)
        let frame = try #require(host.superview)
        frame.layoutSubtreeIfNeeded()
        frame.displayIfNeeded()
        let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
