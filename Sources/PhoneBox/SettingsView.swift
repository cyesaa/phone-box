import AppKit
import PhoneBoxCore
import SwiftUI

/// The settings window's content, like System Settings: the sections in a sidebar, the chosen one's settings as a
/// grouped form (design §8 "Ayarlar penceresi"). It reads and changes only `model`.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        // The sidebar is always there, like System Settings': no toggle, and no collapsing by dragging.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsSection.allCases, selection: selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    SectionIcon(section: section)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .toolbar(removing: .sidebarToggle)
            .background(SidebarLock())
        } detail: {
            Form {
                switch model.section {
                case .connection: ConnectionPane(model: model)
                case .pairing: PairingPane(model: model)
                case .claude: ClaudePane(model: model)
                case .general: GeneralPane(model: model)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: SettingsWindowController.minimumSize.width, minHeight: SettingsWindowController.minimumSize.height)
    }

    private var selection: Binding<SettingsSection?> {
        Binding(get: { model.section }, set: { section in
            if let section {
                model.section = section
            } else {
                // A click below the rows or ⌘-click on the chosen row clears the table's selection: tell SwiftUI to
                // read the section again, so the row is chosen once more.
                model.objectWillChange.send()
            }
        })
    }
}

/// Stops the sidebar from collapsing (by dragging its edge, or "Hide Sidebar"): `columnVisibility` alone leaves the
/// split view item collapsible on macOS 14. Finds the split view controller SwiftUI made as the delegate of the enclosing split view.
private struct SidebarLock: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { LockView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class LockView: NSView {
        // SwiftUI sets the item up after the view enters the window, and again on updates: lock after each layout.
        override func layout() {
            super.layout()
            lock()
        }

        private func lock() {
            var view: NSView? = self
            while let current = view {
                if let controller = (current as? NSSplitView)?.delegate as? NSSplitViewController {
                    for item in controller.splitViewItems where item.behavior == .sidebar {
                        if item.canCollapse { item.canCollapse = false }
                        if item.isCollapsed { item.isCollapsed = false }
                    }
                    return
                }
                view = current.superview
            }
        }
    }
}

/// Runs `action` from the run loop once SwiftUI is done with the click: the flows show modal alerts.
@MainActor
private func later(_ action: @escaping @MainActor () -> Void) {
    RunLoop.main.perform {
        MainActor.assumeIsolated { action() }
    }
}

/// System Settings' coloured rounded square with a white symbol.
private struct SectionIcon: View {
    let section: SettingsSection
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.56, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }

    private var symbol: String {
        switch section {
        case .connection: return "iphone"
        case .pairing: return "qrcode"
        case .claude: return "sparkle"
        case .general: return "gearshape"
        }
    }

    private var color: Color {
        switch section {
        case .connection: return .blue
        case .pairing: return .purple
        case .claude: return .orange
        case .general: return .gray
        }
    }
}

/// The section's name above its first group.
private struct PaneTitle: View {
    let section: SettingsSection

    var body: some View {
        Text(section.title)
            .font(.title2.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.bottom, 6)
    }
}

/// A row's title with the explanation under it.
private struct RowLabel: View {
    let title: String
    let caption: String?

    var body: some View {
        Text(title)
        if let caption { Text(caption) }
    }
}

private struct ConnectionPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            HStack(spacing: 12) {
                SectionIcon(section: .connection, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(dotColor).frame(width: 8, height: 8)
                        Text(SettingsText.title(model.status)).font(.title3.weight(.semibold))
                    }
                    if let detail = SettingsText.detail(model.status) {
                        Text(detail).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } header: {
            PaneTitle(section: .connection)
        }

        Section(L10n.data) {
            Picker(selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text(L10n.modeCable).tag(AccessMode.cable)
                Text(L10n.modeAlways).tag(AccessMode.always)
            } label: {
                RowLabel(title: L10n.sendData, caption: L10n.sendDataCaption)
            }
            .pickerStyle(.segmented)

            Toggle(isOn: Binding(get: { model.lockAndMusicShown }, set: { on in later { model.setLockAndMusic(on) } })) {
                RowLabel(title: L10n.lockAndMusic, caption: L10n.lockAndMusicCaption)
            }
            .toggleStyle(.switch)
            .disabled(!model.lockAndMusicEnabled)
        }

        Section(L10n.network) {
            LabeledContent {
                HStack(spacing: 10) {
                    Text(String(model.port)).monospacedDigit().foregroundStyle(.secondary)
                    Button(L10n.portChange) { later { model.changePort() } }
                }
            } label: {
                RowLabel(title: L10n.port, caption: L10n.portCaption)
            }
        }
    }

    private var dotColor: Color {
        switch model.status {
        case .streaming: return .green
        case .waitingForCable: return .orange
        case .portInUse, .usbUnavailable: return .red
        case .waiting: return .secondary
        }
    }
}

private struct PairingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                if let image = model.qrImage {
                    // At its own size: whole points per module, so it stays sharp.
                    Image(nsImage: image)
                        .interpolation(.none)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel(L10n.qrTitle)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.qrTitle).font(.headline)
                    Text(L10n.qrInstructions)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(model.copied ? L10n.qrCopied : L10n.qrCopy) { model.copyLink() }
                        Button(L10n.qrEnlarge) { later { model.showQR() } }
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        } header: {
            PaneTitle(section: .pairing)
        }

        Section {
            LabeledContent {
                EmptyView()
            } label: {
                RowLabel(title: L10n.pairedPhones, caption: SettingsText.connectedNow(model.phones))
            }
            LabeledContent {
                Button(L10n.resetButton, role: .destructive) { later { model.resetPairing() } }
                    .foregroundStyle(.red)
            } label: {
                RowLabel(title: L10n.resetPairing, caption: L10n.resetMessage)
            }
        }
    }
}

private struct ClaudePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.claudeOn }, set: { on in later { model.setClaudeSessions(on) } })) {
                RowLabel(title: L10n.claudeToggle, caption: L10n.claudeCaption)
            }
            .toggleStyle(.switch)

            LabeledContent {
                HStack(spacing: 6) {
                    if model.claudeOn && model.claudeHooksInstalled {
                        Circle().fill(.green).frame(width: 8, height: 8)
                    }
                    Text(model.claudeStatusText)
                }
            } label: {
                Text(L10n.claudeStatus)
                if let failure = model.claudeFailureText {
                    Text(failure).foregroundStyle(.red)
                }
            }
        } header: {
            PaneTitle(section: .claude)
        }

        Section(L10n.file) {
            LabeledContent {
                Button(L10n.claudeReveal) { model.revealClaudeSettings() }
                    .disabled(!model.claudeSettingsExists)
            } label: {
                Text(verbatim: "~/.claude/settings.json")
                Text(L10n.claudeFileCaption)
            }
        }
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { on in later { model.setLaunchAtLogin(on) } })) {
                RowLabel(title: L10n.launchAtLogin,
                         caption: model.loginItem == .needsApproval ? L10n.loginApprovalMessage : nil)
            }
            .toggleStyle(.switch)
            if model.loginItem == .needsApproval {
                HStack {
                    Spacer()
                    Button(L10n.loginOpenSettings) { model.openLoginItems() }
                }
            }
        } header: {
            PaneTitle(section: .general)
        }

        Section(L10n.updates) {
            // Redrawn every minute: "son denetim 5 dk önce" grows.
            TimelineView(.everyMinute) { context in
                LabeledContent {
                    HStack(spacing: 8) {
                        if model.availableUpdate != nil {
                            Button(L10n.updateInstallButton) { later { model.installUpdate() } }
                                .buttonStyle(.borderedProminent)
                        }
                        Button(L10n.updateCheckNow) { model.checkForUpdates() }
                            .disabled(!model.canCheckForUpdates)
                    }
                } label: {
                    Text(verbatim: "PhoneBox \(model.version)")
                    Text(model.updateText(now: context.date))
                }
            }
        }

        Section(L10n.about) {
            LabeledContent {
                Button(L10n.open) { model.openRepository() }
            } label: {
                Text(L10n.openOnGitHub)
                Text(verbatim: "github.com/\(UpdateCheck.repository) · \(L10n.mitLicense)")
            }
            LabeledContent {
                Button(L10n.open) { model.openLicenses() }
            } label: {
                RowLabel(title: L10n.licenses, caption: L10n.licensesCaption)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(model: .sample)
    }
}
