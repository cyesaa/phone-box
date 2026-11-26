import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// Runs `body` with the texts of `Resources/<language>.lproj` instead of the test runner's bundle, which has none.
func inLanguage<R>(_ language: String, _ body: () throws -> R) rethrows -> R {
    let bundle = Bundle(url: LocalizationTests.resources.appendingPathComponent("\(language).lproj", isDirectory: true))!
    return try L10n.$bundle.withValue(bundle, operation: body)
}

/// The status line and the settings window's texts (design §8 "Menü çubuğu", "Ayarlar penceresi").
@MainActor
struct SettingsTextTests {
    @Test func theStatusComesFromThePortThePhonesAndUSB() {
        let one = PhoneCounts(onCable: 1, overWiFi: 0, waitingForCable: 0)
        let waiting = PhoneCounts(onCable: 0, overWiFi: 0, waitingForCable: 1)
        #expect(ConnectionStatus.decide(portInUse: 4747, phones: one, usbAvailable: true) == .portInUse(4747))
        #expect(ConnectionStatus.decide(portInUse: nil, phones: one, usbAvailable: false) == .streaming(one))
        #expect(ConnectionStatus.decide(portInUse: nil, phones: waiting, usbAvailable: true) == .waitingForCable)
        #expect(ConnectionStatus.decide(portInUse: nil, phones: PhoneCounts(), usbAvailable: false) == .usbUnavailable)
        #expect(ConnectionStatus.decide(portInUse: nil, phones: PhoneCounts(), usbAvailable: true) == .waiting)
        #expect(ConnectionStatus.streaming(one).isActive)
        #expect(!ConnectionStatus.waitingForCable.isActive)
    }

    @Test func theMenuKeepsItsStatusLine() {
        inLanguage("tr") {
            let two = PhoneCounts(onCable: 1, overWiFi: 1, waitingForCable: 0)
            #expect(SettingsText.menuLine(.streaming(two)) == "iPhone bağlı · 2 cihaz")
            #expect(SettingsText.menuLine(.waiting) == "iPhone bekleniyor")
            #expect(SettingsText.menuLine(.waitingForCable) == "Telefon Wi-Fi'de: kabloyu tak")
            #expect(SettingsText.menuLine(.portInUse(4747)) == "Port 4747 kullanımda")
            #expect(SettingsText.menuLine(.usbUnavailable) == "USB aygıtları görülemiyor")
        }
    }

    @Test func theWindowSaysHowManyPhonesAndOverWhat() {
        inLanguage("tr") {
            let cable = PhoneCounts(onCable: 1, overWiFi: 0, waitingForCable: 0)
            let wifi = PhoneCounts(onCable: 0, overWiFi: 2, waitingForCable: 0)
            let both = PhoneCounts(onCable: 1, overWiFi: 1, waitingForCable: 1)
            #expect(SettingsText.title(.streaming(cable)) == "iPhone bağlı")
            #expect(SettingsText.detail(.streaming(cable)) == "1 cihaz · kabloyla")
            #expect(SettingsText.detail(.streaming(wifi)) == "2 cihaz · Wi-Fi'den")
            #expect(SettingsText.detail(.streaming(both)) == "2 cihaz · 1 kabloyla, 1 Wi-Fi'den")
            #expect(SettingsText.title(.waiting) == "iPhone bekleniyor")
            #expect(SettingsText.title(.waitingForCable) == "Telefon Wi-Fi'de: kabloyu tak")
            #expect(SettingsText.title(.portInUse(4747)) == "Port 4747 kullanımda")
            #expect(SettingsText.detail(.waitingForCable)?.contains("Her zaman") == true)
            #expect(SettingsText.detail(.portInUse(4747)) != nil)
            #expect(SettingsText.detail(.waiting) != nil)
            #expect(SettingsText.detail(.usbUnavailable) == nil)
        }
        inLanguage("en") {
            let both = PhoneCounts(onCable: 1, overWiFi: 1, waitingForCable: 0)
            #expect(SettingsText.title(.streaming(both)) == "iPhone connected")
            #expect(SettingsText.detail(.streaming(both)) == "2 connected · 1 over the cable, 1 over Wi-Fi")
        }
    }

    /// The pairing section counts every phone connected now, also the ones on Wi-Fi waiting for the cable.
    @Test func thePairingSectionCountsThePhonesConnectedNow() {
        inLanguage("tr") {
            #expect(SettingsText.connectedNow(PhoneCounts()) == "Şu an bağlı telefon yok")
            #expect(SettingsText.connectedNow(PhoneCounts(onCable: 0, overWiFi: 0, waitingForCable: 1))
                == "Şu an bağlı: 1 cihaz · Wi-Fi'den")
            #expect(SettingsText.connectedNow(PhoneCounts(onCable: 1, overWiFi: 1, waitingForCable: 1))
                == "Şu an bağlı: 3 cihaz · 1 kabloyla, 2 Wi-Fi'den")
        }
    }

    @Test func theClaudeStatusSaysWhetherTheHooksAreThereAndWhoWaits() {
        inLanguage("tr") {
            #expect(SettingsText.claudeStatus(on: false, hooksInstalled: true, sessions: 3, waiting: 1) == "Kapalı")
            #expect(SettingsText.claudeStatus(on: true, hooksInstalled: false, sessions: 0, waiting: 0)
                == "Hook'lar kurulu değil")
            #expect(SettingsText.claudeStatus(on: true, hooksInstalled: true, sessions: 2, waiting: 0)
                == "Hook'lar kurulu · 2 oturum")
            #expect(SettingsText.claudeStatus(on: true, hooksInstalled: true, sessions: 3, waiting: 1)
                == "Hook'lar kurulu · 3 oturum · 1 seni bekliyor")
            #expect(SettingsText.claudeFailure("Geçerli bir JSON değil.")
                == "~/.claude/settings.json değiştirilemedi: Geçerli bir JSON değil.")
        }
        inLanguage("en") {
            #expect(SettingsText.claudeStatus(on: true, hooksInstalled: true, sessions: 3, waiting: 1)
                == "Hooks installed · sessions: 3 · waiting for you: 1")
        }
    }

    @Test func theUpdateLineSaysWhatTheLastCheckFoundAndWhen() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let release = LatestRelease(version: try #require(AppVersion("0.5.0")),
                                    pageURL: try #require(URL(string: "https://github.com/cyesaa/phone-box")))
        inLanguage("tr") {
            #expect(SettingsText.update(status: .upToDate, lastChecked: now - 300, now: now, automatic: true)
                == "Güncel · son denetim 5 dk önce · 12 saatte bir kendiliğinden denetler")
            #expect(SettingsText.update(status: .available(release), lastChecked: now - 2 * 3600, now: now, automatic: false)
                == "0.5.0 sürümü var · son denetim 2 sa önce")
            #expect(SettingsText.update(status: .failed, lastChecked: now - 20, now: now, automatic: false)
                == "Denetlenemedi · son denetim az önce")
            #expect(SettingsText.update(status: .checking, lastChecked: now - 300, now: now, automatic: false)
                == "Denetleniyor…")
            #expect(SettingsText.update(status: .installing, lastChecked: now - 300, now: now, automatic: true)
                == "Yükleniyor…")
            #expect(SettingsText.update(status: .idle, lastChecked: nil, now: now, automatic: true)
                == "Henüz denetlenmedi · 12 saatte bir kendiliğinden denetler")
            // The installer ran but left this copy running: only when the last check was.
            #expect(SettingsText.update(status: .idle, lastChecked: now - 3 * 86400, now: now, automatic: false)
                == "Son denetim 3 gün önce")
        }
        inLanguage("en") {
            #expect(SettingsText.update(status: .upToDate, lastChecked: now - 60, now: now, automatic: true)
                == "Up to date · last checked 1 min ago · checks by itself every 12 hours")
        }
    }

    @Test func agesAreRoundedDown() {
        inLanguage("tr") {
            #expect(SettingsText.ago(-5) == "az önce")
            #expect(SettingsText.ago(59) == "az önce")
            #expect(SettingsText.ago(60) == "1 dk önce")
            #expect(SettingsText.ago(3599) == "59 dk önce")
            #expect(SettingsText.ago(3600) == "1 sa önce")
            #expect(SettingsText.ago(86399) == "23 sa önce")
            #expect(SettingsText.ago(86400) == "1 gün önce")
        }
    }
}
