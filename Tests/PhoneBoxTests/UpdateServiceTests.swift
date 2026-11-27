import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// What the update row and the menu offer after something went wrong (design §8 "Menü çubuğu").
@MainActor
struct UpdateServiceTests {
    static let newer = LatestRelease(version: AppVersion("0.5.0")!, pageURL: URL(string: "https://github.com/cyesaa/phone-box/releases/tag/v0.5.0")!)
    static let same = LatestRelease(version: AppVersion("0.4.1")!, pageURL: URL(string: "https://github.com/cyesaa/phone-box/releases/tag/v0.4.1")!)

    /// A failed install (no network for the download, a bad signature) keeps the update it found, so "Install…" is
    /// there to try again (bughunt #6); so does a failed check.
    @Test func aFailureKeepsTheUpdateFoundBefore() {
        let current = AppVersion("0.4.1")
        #expect(UpdateService.statusAfterFailure(current: current, lastFound: Self.newer) == .available(Self.newer))
        #expect(UpdateService.statusAfterFailure(current: current, lastFound: Self.same) == .failed)
        #expect(UpdateService.statusAfterFailure(current: current, lastFound: nil) == .failed)
        #expect(UpdateService.statusAfterFailure(current: nil, lastFound: Self.newer) == .failed)
    }
}
