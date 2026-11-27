import Foundation

/// What the Mac is playing (design §6). Left out of the snapshot when nothing is.
public struct MediaSample: Equatable, Codable, Sendable {
    public var title: String
    public var artist: String?
    /// The player's name, e.g. "Spotify" or "Google Chrome".
    public var app: String
    public var playing: Bool
    public init(title: String, artist: String?, app: String, playing: Bool) {
        self.title = title
        self.artist = artist
        self.app = app
        self.playing = playing
    }
}

/// The default output's volume (design §6). Left out when the output has no volume control.
public struct AudioSample: Equatable, Codable, Sendable {
    /// 0…1
    public var volume: Double
    public var muted: Bool
    public init(volume: Double, muted: Bool) {
        self.volume = volume
        self.muted = muted
    }
}

/// One track as mediaremote-adapter reports it, before the player's bundle identifier becomes a name.
public struct NowPlayingTrack: Equatable, Sendable {
    public var title: String
    public var artist: String?
    /// The player, or its parent app for a helper (a browser for a web player).
    public var bundleId: String
    public var playing: Bool
    public init(title: String, artist: String?, bundleId: String, playing: Bool) {
        self.title = title
        self.artist = artist
        self.bundleId = bundleId
        self.playing = playing
    }
}

/// Lines of `mediaremote-adapter.pl <framework> stream --no-diff --no-artwork`:
/// `{"type":"data","diff":false,"payload":{…}}`, where an empty payload means nothing is playing. Titles and
/// artists come from any app, so they get the same cleaning and length cap as app names.
public enum NowPlayingStream {
    public enum Line: Equatable, Sendable {
        case track(NowPlayingTrack)
        case nothing
        case invalid
    }

    public static func parse(_ line: String) -> Line {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              object["type"] as? String == "data"
        else { return .invalid }
        guard let payload = object["payload"] as? [String: Any],
              let title = (payload["title"] as? String).map(AppUsage.displayName), !title.isEmpty,
              let bundleId = nonEmpty(payload["parentApplicationBundleIdentifier"]) ?? nonEmpty(payload["bundleIdentifier"])
        else { return .nothing }
        let artist = (payload["artist"] as? String).map(AppUsage.displayName).flatMap { $0.isEmpty ? nil : $0 }
        let playing = JSONValue.bool(payload["playing"]) ?? JSONValue.integer(payload["playing"]).map { $0 != 0 } ?? false
        return .track(NowPlayingTrack(title: title, artist: artist, bundleId: bundleId, playing: playing))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.utf8.count <= Command.maxBundleIdLength else { return nil }
        return text
    }
}

/// Turns the adapter's stdout chunks into lines; a chunk may end anywhere, even inside a UTF-8 character.
public struct LineAssembler: Sendable {
    /// Without artwork a line is a few hundred bytes; this much without a newline means the stream is junk.
    public static let maxLineBytes = 64 * 1024
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if buffer.count > Self.maxLineBytes { buffer.removeAll() }
        return lines
    }

    public mutating func reset() {
        buffer.removeAll()
    }
}

/// The track to show. Between two tracks the adapter briefly reports nothing playing; keeping the last track for
/// `grace` stops the phone's card from blinking (NotchBox saw the same gap). Times are monotonic instants
/// (`ContinuousClock.now`): setting the Mac's clock back cannot keep a stopped track on the page.
public struct NowPlayingState: Sendable {
    public static let grace: Duration = .seconds(1.5)
    private var track: NowPlayingTrack?
    private var nothingSince: ContinuousClock.Instant?

    public init() {}

    public mutating func received(_ line: NowPlayingStream.Line, at now: ContinuousClock.Instant) {
        switch line {
        case let .track(track):
            self.track = track
            nothingSince = nil
        case .nothing:
            if track != nil, nothingSince == nil { nothingSince = now }
        case .invalid:
            break
        }
    }

    public func current(at now: ContinuousClock.Instant) -> NowPlayingTrack? {
        if let nothingSince, now - nothingSince >= Self.grace { return nil }
        return track
    }

    /// The adapter stopped or restarted: forget everything.
    public mutating func clear() {
        track = nil
        nothingSince = nil
    }
}
