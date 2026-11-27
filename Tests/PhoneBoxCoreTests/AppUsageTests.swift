import Foundation
import Testing
@testable import PhoneBoxCore

struct AppUsageTests {
    let chrome = "/Applications/Google Chrome.app"
    let second: UInt64 = 1_000_000_000

    @Test func findsTheOutermostAppBundle() {
        let helper = chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/"
            + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(AppUsage.bundlePath(forExecutable: helper) == chrome)
        #expect(AppUsage.bundlePath(forExecutable: chrome + "/Contents/MacOS/Google Chrome") == chrome)
        #expect(AppUsage.bundlePath(forExecutable: "/usr/bin/swift-frontend") == nil)
        #expect(AppUsage.bundlePath(forExecutable: "/Users/eren/my.application/run") == nil)
    }

    @Test func removesDirectionMarksFromNames() {
        #expect(AppUsage.displayName("\u{200E}WhatsApp") == "WhatsApp")
        #expect(AppUsage.displayName(" \u{202B}Safari\u{202C} ") == "Safari")
        #expect(AppUsage.displayName("çğıöşü") == "çğıöşü")
    }

    @Test func flattensControlCharactersSeparatorsAndInvisibleMarks() {
        #expect(AppUsage.displayName("Line\nbreak\tand\u{2028}separator") == "Line break and separator")
        #expect(AppUsage.displayName("zero\u{200B}width\u{FEFF}") == "zerowidth")
        #expect(AppUsage.displayName("  many   spaces\u{00A0} ") == "many spaces")
        #expect(AppUsage.displayName("\u{0007}\u{200E}\n ") == "")
    }

    @Test func keepsJoinersThatEmojiAndScriptsNeed() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(AppUsage.displayName("\(family) ailesi") == "\(family) ailesi")
        #expect(AppUsage.displayName("\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}")
            == "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}")
        #expect(AppUsage.displayName("\u{200E}\(family)") == family)
    }

    @Test func fallsBackToTheBundleOrExecutableName() {
        #expect(AppUsage.name(app: "\u{200E} ", bundle: "/Applications/Notes.app", executable: "/x/Notes") == "Notes")
        #expect(AppUsage.name(app: nil, bundle: "/Applications/My.app.Tools.app", executable: "/x/y") == "My.app.Tools")
        #expect(AppUsage.name(app: nil, bundle: nil, executable: "/usr/bin/node") == "node")
        #expect(AppUsage.name(app: "", bundle: nil, executable: "") == "?")
    }

    @Test func keepsTiesInAStableOrder() {
        let tied = (1...4).map { AppSample(pid: Int32(10 - $0), bundleId: nil, name: ["d", "b", "c", "a"][$0 - 1], cpu: 0,
                                         mem: 5, quittable: false) }
        #expect(tied.sorted(by: AppUsage.busier).map(\.name) == ["a", "b", "c", "d"])
        #expect(tied.shuffled().sorted(by: AppUsage.larger).map(\.name) == ["a", "b", "c", "d"])
        let twins = [9, 3].map { AppSample(pid: $0, bundleId: nil, name: "x", cpu: 1, mem: 1, quittable: false) }
        #expect(twins.sorted(by: AppUsage.busier).map(\.pid) == [3, 9])
    }

    @Test func boundsTheSizeOfACharacterPiledWithMarks() {
        let piled = "a" + String(repeating: "\u{0301}", count: 5_000)
        #expect(AppUsage.displayName(piled).unicodeScalars.count <= AppUsage.maxNameLength * 4)
        #expect(AppUsage.displayName(piled).unicodeScalars.first == "a")
    }

    @Test func groupsHelpersIntoTheirAppAndComputesPercentOfOneCore() {
        let apps = [chrome: AppInfo(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", quittable: true,
                                    regular: true)]
        let helperPath = chrome + "/Contents/Frameworks/X.framework/Helpers/Helper.app/Contents/MacOS/Helper"
        let current = [
            ProcessReading(pid: 10, path: chrome + "/Contents/MacOS/Google Chrome", cpuNanos: 3 * second, memory: 100),
            ProcessReading(pid: 11, path: helperPath, cpuNanos: 2 * second, memory: 50),
        ]
        let top = AppUsage.top(previousCPU: [10: 2 * second, 11: second / 2], previousSampleAt: 0, current: current, elapsedNanos: 2 * second,
                               apps: apps)
        #expect(top == [AppSample(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", cpu: 125, mem: 150,
                                  quittable: true)])
    }

    /// Simulator ships inside Xcode but is an app of its own: its row is "Simulator", whether Xcode runs or not.
    @Test func filesAnAppInsideAnotherAppUnderItself() {
        let xcode = "/Applications/Xcode.app"
        let simulator = xcode + "/Contents/Developer/Applications/Simulator.app"
        let simulatorInfo = AppInfo(pid: 30, bundleId: "com.apple.iphonesimulator", name: "Simulator", quittable: true,
                                    regular: true)
        let simulatorProcess = ProcessReading(pid: 30, path: simulator + "/Contents/MacOS/Simulator", cpuNanos: 2 * second,
                                              memory: 300)
        let alone = AppUsage.top(previousCPU: [30: second], previousSampleAt: 0, current: [simulatorProcess], elapsedNanos: second,
                                 apps: [simulator: simulatorInfo])
        #expect(alone == [AppSample(pid: 30, bundleId: "com.apple.iphonesimulator", name: "Simulator", cpu: 100, mem: 300,
                                    quittable: true)])

        let xcodeInfo = AppInfo(pid: 20, bundleId: "com.apple.dt.Xcode", name: "Xcode", quittable: true, regular: true)
        let xcodeProcess = ProcessReading(pid: 20, path: xcode + "/Contents/MacOS/Xcode", cpuNanos: second, memory: 500)
        let both = AppUsage.top(previousCPU: [20: 0, 30: second], previousSampleAt: 0, current: [simulatorProcess, xcodeProcess],
                                elapsedNanos: second, apps: [simulator: simulatorInfo, xcode: xcodeInfo])
        #expect(both.count == 2)
        #expect(both.first { $0.name == "Simulator" }?.mem == 300)
        #expect(both.first { $0.name == "Xcode" }?.mem == 500)
    }

    /// macOS lists some helper bundles as apps too (accessory apps, not in the Dock): they still count as their app.
    @Test func keepsListedHelperAppsUnderTheirApp() {
        let helper = chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Aperitif).app"
        let apps = [
            chrome: AppInfo(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", quittable: true, regular: true),
            helper: AppInfo(pid: 12, bundleId: "com.google.Chrome.helper", name: "Google Chrome Helper", quittable: false,
                            regular: false),
        ]
        let current = [ProcessReading(pid: 12, path: helper + "/Contents/MacOS/Google Chrome Helper (Aperitif)",
                                      cpuNanos: second, memory: 40)]
        let top = AppUsage.top(previousCPU: [12: 0], previousSampleAt: 0, current: current, elapsedNanos: second, apps: apps)
        #expect(top == [AppSample(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", cpu: 100, mem: 40,
                                  quittable: true)])
    }

    /// A compiler that started after the last sample used all its CPU time since then (a 3 s window here).
    @Test func aProcessBornSinceTheLastSampleCountsAllItsCPU() {
        let lastSample = 100 * second
        let current = [
            ProcessReading(pid: 40, path: "/usr/bin/clang", cpuNanos: 3 * second / 2, memory: 10, startNanos: lastSample + second),
            ProcessReading(pid: 41, path: "/usr/bin/clang", cpuNanos: second / 2, memory: 10, startNanos: lastSample + 2 * second),
            // Seen for the first time but older than the last sample (it was not readable then): 0 % this time.
            ProcessReading(pid: 42, path: "/usr/bin/swift", cpuNanos: 9 * second, memory: 10, startNanos: lastSample - second),
        ]
        let top = AppUsage.top(previousCPU: [:], previousSampleAt: lastSample, current: current, elapsedNanos: 3 * second,
                               apps: [:])
        #expect(top.first { $0.name == "clang" }?.cpu.rounded() == 67)
        #expect(top.first { $0.name == "swift" }?.cpu == 0)
    }

    /// A new process with the pid of one from the last sample is not measured against the old one's counter.
    @Test func aReusedPidCountsTheNewProcessFromItsStart() {
        let lastSample = 100 * second
        let current = [ProcessReading(pid: 50, path: "/usr/bin/node", cpuNanos: second, memory: 10,
                                      startNanos: lastSample + second / 2)]
        let top = AppUsage.top(previousCPU: [50: second / 4], previousSampleAt: lastSample, current: current,
                               elapsedNanos: 2 * second, apps: [:])
        #expect(top.first?.cpu == 50)
    }

    @Test func newOrResetProcessesCountAsZeroThisTime() {
        let current = [ProcessReading(pid: 7, path: "/usr/bin/node", cpuNanos: 5 * second, memory: 10),
                       ProcessReading(pid: 8, path: "/usr/bin/ruby", cpuNanos: 1, memory: 20)]
        let top = AppUsage.top(previousCPU: [8: 9 * second], previousSampleAt: 0, current: current, elapsedNanos: second, apps: [:])
        #expect(top.map(\.cpu) == [0, 0])
        #expect(Set(top.map(\.name)) == ["node", "ruby"])
        #expect(top.allSatisfy { !$0.quittable && $0.bundleId == nil })
    }

    @Test func namesAnAppThatMacOSDoesNotListAfterItsBundle() {
        let current = [ProcessReading(pid: 5, path: "/Applications/Tool.app/Contents/MacOS/tool", cpuNanos: 0, memory: 1)]
        #expect(AppUsage.top(previousCPU: [:], previousSampleAt: 0, current: current, elapsedNanos: second, apps: [:]).first?.name == "Tool")
    }

    @Test func listsTopByCPUThenTopByMemoryWithoutDuplicates() {
        var current: [ProcessReading] = []
        var previous: [Int32: UInt64] = [:]
        for index in 1...8 {
            let pid = Int32(index)
            previous[pid] = 0
            // CPU grows with the index, memory shrinks with it.
            current.append(ProcessReading(pid: pid, path: "/bin/p\(index)", cpuNanos: UInt64(index) * second / 10,
                                          memory: UInt64(100 - index)))
        }
        let top = AppUsage.top(previousCPU: previous, previousSampleAt: 0, current: current, elapsedNanos: second, apps: [:])
        #expect(top.map(\.name) == ["p8", "p7", "p6", "p5", "p4", "p1", "p2", "p3"])
    }

    @Test func returnsNothingForNoElapsedTime() {
        let current = [ProcessReading(pid: 1, path: "/bin/a", cpuNanos: 1, memory: 1)]
        #expect(AppUsage.top(previousCPU: [:], previousSampleAt: 0, current: current, elapsedNanos: 0, apps: [:]).isEmpty)
    }

    @Test func capsNamesAtEightyCharacters() {
        #expect(AppUsage.displayName(String(repeating: "a", count: 200)).count == AppUsage.maxNameLength)
        let exact = String(repeating: "b", count: 80)
        #expect(AppUsage.displayName(exact) == exact)
    }

    @Test func neverSplitsACharacterWhenCapping() {
        let thumb = "\u{1F44D}\u{1F3FD}"
        let name = String(repeating: "a", count: 79) + thumb + "tail"
        let shown = AppUsage.displayName(name)
        #expect(shown.count == 80)
        #expect(shown.hasSuffix(thumb))
    }
}
