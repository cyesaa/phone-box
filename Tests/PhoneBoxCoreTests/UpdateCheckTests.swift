import Foundation
import Testing
@testable import PhoneBoxCore

struct AppVersionTests {
    @Test func readsTagsAndBundleVersions() {
        #expect(AppVersion("0.1.0")?.description == "0.1.0")
        #expect(AppVersion("v1.2.3")?.description == "1.2.3")
        #expect(AppVersion("V2.0")?.description == "2.0.0")
        #expect(AppVersion(" 3 ")?.description == "3.0.0")
        #expect(AppVersion("0.1.1\n")?.description == "0.1.1")
        #expect(AppVersion("\t0.1.1\r\n")?.description == "0.1.1")
    }

    @Test func refusesWhatIsNotAVersion() {
        for text in ["", "latest", "1.x", "1.2.3.4", "1.2.3-beta", "1..2", "١.٢"] {
            #expect(AppVersion(text) == nil, "\(text)")
        }
    }

    @Test func comparesNumericallyPartByPart() throws {
        let v = { (s: String) throws -> AppVersion in try #require(AppVersion(s)) }
        #expect(try v("0.1.0") < v("0.1.1"))
        #expect(try v("0.1.9") < v("0.10.0"))
        #expect(try v("0.9.9") < v("1.0.0"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try !(v("0.1.0") < v("0.1.0")))
    }
}

struct LatestReleaseTests {
    func json(_ fields: String) -> Data { Data("{\(fields)}".utf8) }

    @Test func readsTheTagAndThePage() {
        let release = LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "https://github.com/cyesaa/phone-box/releases/tag/v0.2.0", "draft": false, "prerelease": false"#))
        #expect(release?.version.description == "0.2.0")
        #expect(release?.pageURL.absoluteString == "https://github.com/cyesaa/phone-box/releases/tag/v0.2.0")
    }

    @Test func skipsDraftsPrereleasesAndJunk() {
        let page = "https://github.com/cyesaa/phone-box/releases/tag/v0.2.0"
        #expect(LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "\#(page)", "draft": true"#)) == nil)
        #expect(LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "\#(page)", "prerelease": true"#)) == nil)
        #expect(LatestRelease.parse(json(#""tag_name": "nightly", "html_url": "\#(page)""#)) == nil)
        #expect(LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "file:///etc/passwd""#)) == nil)
        #expect(LatestRelease.parse(json(#""message": "Not Found""#)) == nil)
        #expect(LatestRelease.parse(Data("not json".utf8)) == nil)
    }

    @Test func opensOnlyAReleasePageOnGitHub() {
        for url in ["", "https://x.y", "https://example.com/cyesaa/phone-box/releases/tag/v0.2.0",
                    "https://github.com.example.com/releases", "https://github.com@example.com/releases",
                    "http://github.com/cyesaa/phone-box/releases/tag/v0.2.0", "https:///releases"] {
            #expect(LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "\#(url)""#)) == nil, "\(url)")
        }
    }
}

struct UpdateCheckTests {
    let current = AppVersion("0.1.0")!

    func release(_ version: String) -> LatestRelease {
        LatestRelease(version: AppVersion(version)!, pageURL: URL(string: "https://example.com")!)
    }

    @Test func onlyANewerReleaseIsAnUpdate() {
        #expect(UpdateCheck.availableUpdate(current: current, latest: release("0.2.0")) == release("0.2.0"))
        #expect(UpdateCheck.availableUpdate(current: current, latest: release("0.1.0")) == nil)
        #expect(UpdateCheck.availableUpdate(current: current, latest: release("0.0.9")) == nil)
        #expect(UpdateCheck.availableUpdate(current: current, latest: nil) == nil)
    }

    @Test func checksSoonAfterLaunchThenTwiceADay() {
        #expect(UpdateCheck.launchDelay == 15)
        #expect(UpdateCheck.interval == 12 * 60 * 60)
    }

    @Test func pointsAtThisRepository() {
        #expect(UpdateCheck.latestReleaseURL.absoluteString == "https://api.github.com/repos/cyesaa/phone-box/releases/latest")
        #expect(UpdateCheck.installCommand == "curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash")
    }
}
