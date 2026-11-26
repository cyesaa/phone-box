import Foundation
import Testing
@testable import PhoneBoxCore

struct WebBuildTests {
    let files = ["index.html": Data("<html>".utf8), "app.js": Data("run()".utf8)]

    @Test func namesTheSameFilesTheSameWay() {
        let name = WebBuild.fingerprint(files)
        #expect(name.count == 12)
        #expect(name.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(WebBuild.fingerprint(["app.js": Data("run()".utf8), "index.html": Data("<html>".utf8)]) == name)
        #expect(WebBuild.fingerprint([:]) == "e3b0c44298fc")
    }

    @Test func anyChangeGivesAnotherName() {
        let name = WebBuild.fingerprint(files)
        var edited = files
        edited["app.js"] = Data("run();".utf8)
        var renamed = files
        renamed["main.js"] = renamed.removeValue(forKey: "app.js")
        var added = files
        added["new.css"] = Data()
        // Moving a byte from one file's end to the next file's start must count too.
        let moved = ["a": Data("xy".utf8), "b": Data("z".utf8)]
        let shifted = ["a": Data("x".utf8), "b": Data("yz".utf8)]
        #expect(Set([name, WebBuild.fingerprint(edited), WebBuild.fingerprint(renamed), WebBuild.fingerprint(added)]).count == 4)
        #expect(WebBuild.fingerprint(moved) != WebBuild.fingerprint(shifted))
    }

    @Test func stampsTheBuildIntoIndexHTML() {
        let html = Data("<head>\n<meta name=\"phonebox-build\" content=\"\">\n<title>PhoneBox</title>\n</head>".utf8)
        #expect(WebBuild.stamp(html, build: "0123456789ab")
                == Data("<head>\n<meta name=\"phonebox-build\" content=\"0123456789ab\">\n<title>PhoneBox</title>\n</head>".utf8))
    }

    @Test func stampsOnlyTwelveLowercaseHexDigits() {
        let html = Data(#"<meta name="phonebox-build" content="">"#.utf8)
        for build in ["", "0123456789a", "0123456789abc", "0123456789AB", "0123456789ag", #"0123456789"x"#,
                      "０１２３４５６７８９ab"] {
            #expect(WebBuild.stamp(html, build: build) == html, "\(build)")
        }
    }

    @Test func leavesHTMLWithoutTheEmptyTagAlone() {
        let stamped = Data(#"<meta name="phonebox-build" content="ba9876543210">"#.utf8)
        #expect(WebBuild.stamp(stamped, build: "0123456789ab") == stamped)
        #expect(WebBuild.stamp(Data("<html>".utf8), build: "0123456789ab") == Data("<html>".utf8))
    }

    @Test func theDashboardCarriesTheEmptyTagOnce() throws {
        let html = try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent("index.html"), encoding: .utf8)
        #expect(html.components(separatedBy: WebBuild.emptyTag).count == 2)
    }
}
