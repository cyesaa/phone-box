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

    @Test func groupsHelpersIntoTheirAppAndComputesPercentOfOneCore() {
        let apps = [chrome: AppInfo(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", quittable: true)]
        let helperPath = chrome + "/Contents/Frameworks/X.framework/Helpers/Helper.app/Contents/MacOS/Helper"
        let current = [
            ProcessReading(pid: 10, path: chrome + "/Contents/MacOS/Google Chrome", cpuNanos: 3 * second, memory: 100),
            ProcessReading(pid: 11, path: helperPath, cpuNanos: 2 * second, memory: 50),
        ]
        let top = AppUsage.top(previousCPU: [10: 2 * second, 11: second / 2], current: current, elapsedNanos: 2 * second,
                               apps: apps)
        #expect(top == [AppSample(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", cpu: 125, mem: 150,
                                  quittable: true)])
    }

    @Test func newOrResetProcessesCountAsZeroThisTime() {
        let current = [ProcessReading(pid: 7, path: "/usr/bin/node", cpuNanos: 5 * second, memory: 10),
                       ProcessReading(pid: 8, path: "/usr/bin/ruby", cpuNanos: 1, memory: 20)]
        let top = AppUsage.top(previousCPU: [8: 9 * second], current: current, elapsedNanos: second, apps: [:])
        #expect(top.map(\.cpu) == [0, 0])
        #expect(Set(top.map(\.name)) == ["node", "ruby"])
        #expect(top.allSatisfy { !$0.quittable && $0.bundleId == nil })
    }

    @Test func namesAnAppThatMacOSDoesNotListAfterItsBundle() {
        let current = [ProcessReading(pid: 5, path: "/Applications/Tool.app/Contents/MacOS/tool", cpuNanos: 0, memory: 1)]
        #expect(AppUsage.top(previousCPU: [:], current: current, elapsedNanos: second, apps: [:]).first?.name == "Tool")
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
        let top = AppUsage.top(previousCPU: previous, current: current, elapsedNanos: second, apps: [:])
        #expect(top.map(\.name) == ["p8", "p7", "p6", "p5", "p4", "p1", "p2", "p3"])
    }

    @Test func returnsNothingForNoElapsedTime() {
        let current = [ProcessReading(pid: 1, path: "/bin/a", cpuNanos: 1, memory: 1)]
        #expect(AppUsage.top(previousCPU: [:], current: current, elapsedNanos: 0, apps: [:]).isEmpty)
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
