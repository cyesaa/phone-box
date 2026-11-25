/// A running app as `NSWorkspace` lists it.
public struct RunningApp: Equatable, Sendable {
    public var pid: Int32
    public var bundleId: String?
    /// `activationPolicy == .regular`: a Dock app with a menu bar.
    public var regular: Bool
    public init(pid: Int32, bundleId: String?, regular: Bool) {
        self.pid = pid
        self.bundleId = bundleId
        self.regular = regular
    }
}

/// Which apps the phone may quit (design §7): the app list's `quittable` and the `quitApp` command use the same
/// rule. Only Dock apps; never Finder (it is part of the desktop and relaunches) or PhoneBox itself.
public enum QuitRule {
    public static let finder = "com.apple.finder"

    public static func isQuittable(_ app: RunningApp, ownPid: Int32) -> Bool {
        app.regular && app.bundleId != finder && app.pid != ownPid
    }

    /// Every quittable instance of `bundleId`: the phone's row merges an app's instances. Empty when there is
    /// none, which the phone hears as `app-changed`.
    public static func targets(bundleId: String, among apps: [RunningApp], ownPid: Int32) -> [Int32] {
        apps.filter { $0.bundleId == bundleId && isQuittable($0, ownPid: ownPid) }.map(\.pid)
    }
}
