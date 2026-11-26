import AppKit
import SwiftUI
import Testing
@testable import PhoneBox

/// The sidebar of the settings window behaves like System Settings': a section is always chosen, and it cannot be
/// collapsed. Checked on the real AppKit views SwiftUI builds (design §8 "Ayarlar penceresi"). The first SwiftUI window
/// holds the main thread for seconds, which makes the timing tests that run beside it fail, so this runs only in
/// `make test-ui`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHONEBOX_UI"] == "1"))
struct SettingsSidebarTests {
    private func host(_ model: SettingsModel) -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsWindowController.contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sceneBridgingOptions = []
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(SettingsWindowController.contentSize)
        window.orderFront(nil)
        settle(window)
        return (window, hosting.view)
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func all<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    @Test func aSectionStaysChosenWhenTheTableIsDeselected() throws {
        let model = SettingsModel.sample
        model.section = .claude
        let (window, view) = host(model)
        defer { window.close() }
        let table = try #require(all(NSTableView.self, in: view).first)
        #expect(table.selectedRow == SettingsSection.allCases.firstIndex(of: .claude))
        table.deselectAll(nil)
        settle(window)
        #expect(model.section == .claude)
        #expect(table.selectedRow == SettingsSection.allCases.firstIndex(of: .claude))
    }

    @Test func theSidebarCannotBeCollapsed() throws {
        let (window, view) = host(SettingsModel.sample)
        defer { window.close() }
        settle(window)
        let split = try #require(all(NSSplitView.self, in: view).first)
        let delegate = try #require(split.delegate)
        let sidebar = try #require(split.subviews.first)
        let controller = try #require(delegate as? NSSplitViewController)
        let item = try #require(controller.splitViewItems.first)
        #expect(!item.canCollapse)
        #expect(delegate.splitView?(split, canCollapseSubview: sidebar) != true)
        // A drag past the minimum width would collapse it.
        split.setPosition(0, ofDividerAt: 0)
        settle(window)
        #expect(!split.isSubviewCollapsed(sidebar))
        // The View menu's and the keyboard's "Hide Sidebar".
        controller.toggleSidebar(nil)
        settle(window)
        #expect(!split.isSubviewCollapsed(sidebar))
        #expect(sidebar.frame.width >= 100)
    }
}
