import AppKit
import Testing
@testable import PhoneBox

/// The menu bar menu since 0.4.0 (design §8 "Menü çubuğu"): the settings moved to the settings window.
@MainActor
struct MenuBarMenuTests {
    @Test func theMenuHasTheStatusSettingsQRUpdatesAndQuit() {
        inLanguage("tr") {
            let statusLine = NSMenuItem(title: "iPhone bekleniyor", action: nil, keyEquivalent: "")
            let installItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let menu = MenuBarController.makeMenu(statusLine: statusLine, installItem: installItem, target: nil)
            let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
            #expect(titles == ["iPhone bekleniyor", "-", "Ayarlar…", "QR kodunu göster…", "-", "", "Güncellemeleri denetle…",
                               "-", "PhoneBox'tan çık"])
            let settings = menu.items[2]
            #expect(settings.keyEquivalent == ",")
            #expect(settings.keyEquivalentModifierMask == .command)
            #expect(menu.items[8].keyEquivalent == "q")
            #expect(menu.items[5] === installItem)
            #expect(installItem.isHidden)
        }
    }

    @Test func theSettingsLeftTheMenu() {
        inLanguage("tr") {
            let menu = MenuBarController.makeMenu(statusLine: NSMenuItem(), installItem: NSMenuItem(), target: nil)
            let titles = menu.items.map(\.title)
            for gone in ["Veri gönder", "Sadece kablo takılıyken", "Her zaman, Wi-Fi'de de", "Wi-Fi'den Kilit ve Müzik",
                         "Claude Code Oturumları", "Girişte başlat", "Eşleştirmeyi sıfırla…"] {
                #expect(!titles.contains(gone), "\(gone)")
            }
            #expect(!titles.contains { $0.hasPrefix("Port") })
        }
    }
}
