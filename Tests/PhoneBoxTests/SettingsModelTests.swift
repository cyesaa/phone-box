import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// What the settings window's controls do (design §8 "Ayarlar penceresi"), with the app's flows replaced by recorders.
@MainActor
struct SettingsModelTests {
    func makeModel(mode: AccessMode = .always, lockAndMusic: Bool = false, claudeOn: Bool = false) -> SettingsModel {
        SettingsModel(mode: mode, lockAndMusic: lockAndMusic, port: 4747, link: "http://mac.local:4747/#k=old",
                      claudeOn: claudeOn, version: "0.4.0", checksAutomatically: true)
    }

    @Test func cableModeTurnsTheWiFiSwitchOffAndDimsIt() {
        let model = makeModel(mode: .always, lockAndMusic: true)
        var applied: [AccessMode] = []
        model.actions.applyMode = { applied.append($0) }
        #expect(model.lockAndMusicShown && model.lockAndMusicEnabled)

        model.setMode(.cable)
        #expect(applied == [.cable])
        #expect(!model.lockAndMusicShown)
        #expect(!model.lockAndMusicEnabled)
        // The setting itself stays: back in "always" mode the switch is on again.
        model.setMode(.always)
        #expect(applied == [.cable, .always])
        #expect(model.lockAndMusicShown)
        model.setMode(.always)
        #expect(applied == [.cable, .always])
    }

    @Test func lockAndMusicAsksBeforeItGoesOnButNotBeforeItGoesOff() {
        let model = makeModel()
        var asked = 0
        var answer = false
        var applied: [Bool] = []
        model.actions.confirmLockAndMusic = { asked += 1; return answer }
        model.actions.applyLockAndMusic = { applied.append($0) }

        model.setLockAndMusic(true)
        #expect(asked == 1 && applied.isEmpty && !model.lockAndMusicShown)
        answer = true
        model.setLockAndMusic(true)
        #expect(asked == 2 && applied == [true] && model.lockAndMusicShown)
        model.setLockAndMusic(false)
        #expect(asked == 2 && applied == [true, false] && !model.lockAndMusicShown)
    }

    @Test func lockAndMusicCannotChangeInCableMode() {
        let model = makeModel(mode: .cable)
        var applied: [Bool] = []
        model.actions.confirmLockAndMusic = { true }
        model.actions.applyLockAndMusic = { applied.append($0) }
        model.setLockAndMusic(true)
        #expect(applied.isEmpty && !model.lockAndMusic)
    }

    @Test func turningClaudeOnAsksAndInstallsTheHooks() {
        let model = makeModel()
        var answer = false
        var changes: [Bool] = []
        model.actions.confirmClaudeSessions = { answer }
        model.actions.changeClaudeSessions = { on in changes.append(on); return (on, nil) }

        model.setClaudeSessions(true)
        #expect(changes.isEmpty && !model.claudeOn)
        answer = true
        model.setClaudeSessions(true)
        #expect(changes == [true] && model.claudeOn)
    }

    @Test func aClaudeFailureShowsItsReasonUntilAChangeWorks() {
        inLanguage("tr") {
            let model = makeModel()
            var failure: String? = "Geçerli bir JSON değil."
            model.actions.changeClaudeSessions = { on in failure == nil ? (on, nil) : (false, failure) }

            model.setClaudeSessions(true)
            #expect(!model.claudeOn)
            #expect(model.claudeFailureText == "~/.claude/settings.json değiştirilemedi: Geçerli bir JSON değil.")
            failure = nil
            model.setClaudeSessions(true)
            #expect(model.claudeOn)
            #expect(model.claudeFailureText == nil)
        }
    }

    /// Turning it off asks nothing and the feature stops even when the hooks cannot be removed.
    @Test func turningClaudeOffAsksNothingAndStopsEvenWhenTheRemovalFails() {
        let model = makeModel(claudeOn: true)
        var asked = false
        model.actions.confirmClaudeSessions = { asked = true; return true }
        model.actions.changeClaudeSessions = { _ in (false, "It is not valid JSON.") }
        model.setClaudeSessions(false)
        #expect(!asked)
        #expect(!model.claudeOn)
        #expect(model.claudeFailure == "It is not valid JSON.")
    }

    @Test func theClaudeStatusFollowsTheMonitor() {
        inLanguage("tr") {
            let model = makeModel(claudeOn: true)
            model.claudeHooksInstalled = true
            model.claudeSessions = 3
            model.claudeWaiting = 1
            #expect(model.claudeStatusText == "Hook'lar kurulu · 3 oturum · 1 seni bekliyor")
            model.claudeOn = false
            #expect(model.claudeStatusText == "Kapalı")
        }
    }

    @Test func aResetAsksAndThenShowsTheNewLink() {
        let model = makeModel()
        var answer = false
        var resets = 0
        model.actions.confirmReset = { answer }
        model.actions.resetPairing = { resets += 1; return "http://mac.local:4747/#k=new" }
        let oldImage = model.qrImage
        model.copyLink()
        #expect(model.copied)

        model.resetPairing()
        #expect(resets == 0 && model.link == "http://mac.local:4747/#k=old")
        answer = true
        model.resetPairing()
        #expect(resets == 1 && model.link == "http://mac.local:4747/#k=new")
        #expect(model.qrImage != nil && model.qrImage !== oldImage)
        #expect(!model.copied)
    }

    @Test func copyLinkCopiesTheLink() {
        let model = makeModel()
        var copied: [String] = []
        model.actions.copyLink = { copied.append($0) }
        model.copyLink()
        #expect(copied == ["http://mac.local:4747/#k=old"])
        #expect(model.copied)
    }

    @Test func aNewPortIsShownOnlyOnceTheDashboardListensThere() {
        let model = makeModel()
        var chosen: UInt16? = 5000
        var moves: [UInt16] = []
        var finish: (@MainActor (String?) -> Void)?
        model.actions.askPort = { _ in chosen }
        model.actions.movePort = { port, completion in
            moves.append(port)
            finish = completion
        }

        model.changePort()
        #expect(moves == [5000] && model.port == 4747)
        finish?(nil)
        #expect(model.port == 4747 && model.link == "http://mac.local:4747/#k=old")
        model.changePort()
        finish?("http://mac.local:5000/#k=old")
        #expect(model.port == 5000 && model.link == "http://mac.local:5000/#k=old")

        // The same port, or a cancelled dialog, moves nothing.
        model.changePort()
        chosen = nil
        model.changePort()
        #expect(moves == [5000, 5000])
    }

    @Test func openAtLoginShowsWhatMacOSSays() {
        let model = makeModel()
        var calls = 0
        var next = LoginItemState.needsApproval
        model.actions.toggleLaunchAtLogin = { calls += 1; return next }
        model.setLaunchAtLogin(true)
        #expect(calls == 1 && model.loginItem == .needsApproval && model.launchAtLogin)
        // Already on (waiting for approval): nothing to do.
        model.setLaunchAtLogin(true)
        #expect(calls == 1)
        next = .off
        model.setLaunchAtLogin(false)
        #expect(calls == 2 && model.loginItem == .off && !model.launchAtLogin)
    }

    @Test func theUpdateRowFollowsTheUpdater() {
        inLanguage("tr") {
            let model = makeModel()
            let now = Date()
            model.update = .checking
            #expect(model.updateText(now: now) == "Denetleniyor…")
            #expect(model.canCheckForUpdates)
            model.update = .upToDate
            model.lastChecked = now
            #expect(model.updateText(now: now) == "Güncel · son denetim az önce · 12 saatte bir kendiliğinden denetler")
            model.update = .installing
            #expect(!model.canCheckForUpdates)
        }
    }

    @Test func theSampleHasSomethingInEverySection() {
        let model = SettingsModel.sample
        #expect(model.status.isActive)
        #expect(model.qrImage != nil)
        #expect(model.claudeOn && model.claudeSessions > 0)
        #expect(model.lastChecked != nil)
    }
}
