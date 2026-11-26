import Foundation

/// The commands the phone may send (design §7). A name the phone may not send, unknown names among them, is answered
/// with `not-allowed`; arguments of the wrong shape with `unsupported`. Neither is run.
public enum Command: Equatable, Sendable {
    public enum MediaAction: String, Sendable, CaseIterable {
        case playPause, next, previous
    }

    /// The phone's app list can be 10 s old and merges an app's instances into one row, so the Mac finds the app
    /// again by `bundleId` and never trusts a process id from the phone.
    case quitApp(bundleId: String, force: Bool)
    case media(MediaAction)
    /// 0…1
    case volume(level: Double)
    case mute(on: Bool)
    case lock
    case displaySleep
    case sleep

    /// Every command's protocol name, in the order of design §7: what a phone on the cable may send.
    public static let allNames = ["quitApp", "media", "volume", "mute", "lock", "displaySleep", "sleep"]
    /// What a phone on Wi-Fi may send once "Lock and Music over Wi-Fi" is on (design §5): someone who took over the
    /// network could then lock the screen or skip a song, nothing worse.
    public static let wifiNames = ["media", "lock"]

    /// The protocol name, for logs; one of `allNames`.
    public var name: String {
        switch self {
        case .quitApp: return "quitApp"
        case .media: return "media"
        case .volume: return "volume"
        case .mute: return "mute"
        case .lock: return "lock"
        case .displaySleep: return "displaySleep"
        case .sleep: return "sleep"
        }
    }

    /// Bundle identifiers are short reverse-DNS names; anything longer is junk.
    public static let maxBundleIdLength = 255

    /// `args` is the JSON object text the phone signed. Nil for an unknown name or for arguments of the wrong
    /// shape, including missing or extra keys.
    public static func parse(name: String, args: String) -> Command? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(args.utf8))) as? [String: Any] else { return nil }
        let keys = Set(object.keys)
        switch name {
        case "quitApp":
            guard keys == ["bundleId", "force"], let bundleId = object["bundleId"] as? String, !bundleId.isEmpty,
                  bundleId.utf8.count <= maxBundleIdLength, let force = JSONValue.bool(object["force"])
            else { return nil }
            return .quitApp(bundleId: bundleId, force: force)
        case "media":
            guard keys == ["action"], let raw = object["action"] as? String, let action = MediaAction(rawValue: raw)
            else { return nil }
            return .media(action)
        case "volume":
            guard keys == ["level"], let level = JSONValue.number(object["level"]), (0...1).contains(level) else { return nil }
            return .volume(level: level)
        case "mute":
            guard keys == ["on"], let on = JSONValue.bool(object["on"]) else { return nil }
            return .mute(on: on)
        case "lock":
            return keys.isEmpty ? .lock : nil
        case "displaySleep":
            return keys.isEmpty ? .displaySleep : nil
        case "sleep":
            return keys.isEmpty ? .sleep : nil
        default:
            return nil
        }
    }
}

/// Why a command was not done; the `ack` message's `error` (design §5).
public enum CommandFailure: String, Equatable, Sendable {
    /// The phone may not send this command (`Access.commands`): it is not on the cable, or the name is unknown.
    case notAllowed = "not-allowed"
    /// No app with that bundle identifier can be quit any more.
    case appChanged = "app-changed"
    /// Wrong arguments, or the Mac cannot do it (e.g. an output without volume control).
    case unsupported
    case failed
}

public enum CommandResult: Equatable, Sendable {
    case ok
    case failed(CommandFailure)
}
