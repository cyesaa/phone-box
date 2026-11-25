import Testing
@testable import PhoneBoxCore

struct QuitRuleTests {
    let ownPid: Int32 = 500
    let apps = [
        RunningApp(pid: 10, bundleId: "com.google.Chrome", regular: true),
        RunningApp(pid: 11, bundleId: "com.google.Chrome", regular: true),
        RunningApp(pid: 12, bundleId: "com.google.Chrome.helper", regular: false),
        RunningApp(pid: 20, bundleId: "com.apple.finder", regular: true),
        RunningApp(pid: 30, bundleId: "com.apple.Spotlight", regular: false),
        RunningApp(pid: 500, bundleId: "com.example.Self", regular: true),
        RunningApp(pid: 40, bundleId: nil, regular: true),
    ]

    @Test func quitsEveryRegularInstanceOfTheBundle() {
        #expect(QuitRule.targets(bundleId: "com.google.Chrome", among: apps, ownPid: ownPid) == [10, 11])
    }

    @Test func neverQuitsFinderBackgroundAppsOrItself() {
        #expect(QuitRule.targets(bundleId: "com.apple.finder", among: apps, ownPid: ownPid).isEmpty)
        #expect(QuitRule.targets(bundleId: "com.apple.Spotlight", among: apps, ownPid: ownPid).isEmpty)
        #expect(QuitRule.targets(bundleId: "com.example.Self", among: apps, ownPid: ownPid).isEmpty)
    }

    @Test func anAppThatIsGoneHasNoTargets() {
        #expect(QuitRule.targets(bundleId: "com.example.Gone", among: apps, ownPid: ownPid).isEmpty)
    }

    @Test func quittableMatchesTheTargets() {
        #expect(QuitRule.isQuittable(apps[0], ownPid: ownPid))
        #expect(!QuitRule.isQuittable(apps[2], ownPid: ownPid))
        #expect(!QuitRule.isQuittable(apps[3], ownPid: ownPid))
        #expect(!QuitRule.isQuittable(apps[5], ownPid: ownPid))
    }
}
