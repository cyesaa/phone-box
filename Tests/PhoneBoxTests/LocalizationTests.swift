import Foundation
import Testing

/// The menu and its dialogs exist in English and Turkish (design §8 "Menü çubuğu"): both files must have the same
/// keys, and each text the same placeholders, or `String(format:)` would read the wrong argument.
struct LocalizationTests {
    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)

    static func strings(_ language: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    static func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%[@dfs]")
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
    }

    @Test func englishAndTurkishHaveTheSameKeysAndPlaceholders() throws {
        let english = try Self.strings("en")
        let turkish = try Self.strings("tr")
        #expect(Set(english.keys) == Set(turkish.keys))
        #expect(english.count == 45)
        for (key, text) in english {
            #expect(Self.placeholders(text) == Self.placeholders(turkish[key] ?? ""), "\(key)")
        }
    }
}
