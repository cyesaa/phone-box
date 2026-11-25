import Testing
@testable import PhoneBoxCore

struct CommandTests {
    @Test func parsesEveryCommandOfDesignSection7() {
        #expect(Command.parse(name: "quitApp", args: #"{"bundleId":"com.google.Chrome","force":false}"#)
            == .quitApp(bundleId: "com.google.Chrome", force: false))
        #expect(Command.parse(name: "quitApp", args: #"{"force":true,"bundleId":"com.google.Chrome"}"#)
            == .quitApp(bundleId: "com.google.Chrome", force: true))
        #expect(Command.parse(name: "media", args: #"{"action":"playPause"}"#) == .media(.playPause))
        #expect(Command.parse(name: "media", args: #"{"action":"next"}"#) == .media(.next))
        #expect(Command.parse(name: "media", args: #"{"action":"previous"}"#) == .media(.previous))
        #expect(Command.parse(name: "volume", args: #"{"level":0.35}"#) == .volume(level: 0.35))
        #expect(Command.parse(name: "volume", args: #"{"level":0}"#) == .volume(level: 0))
        #expect(Command.parse(name: "volume", args: #"{"level":1}"#) == .volume(level: 1))
        #expect(Command.parse(name: "mute", args: #"{"on":true}"#) == .mute(on: true))
        #expect(Command.parse(name: "lock", args: "{}") == .lock)
        #expect(Command.parse(name: "displaySleep", args: "{}") == .displaySleep)
        #expect(Command.parse(name: "sleep", args: "{}") == .sleep)
    }

    @Test func refusesUnknownNames() {
        for name in ["shutdown", "Lock", "", "quitApp:x", "run"] {
            #expect(Command.parse(name: name, args: "{}") == nil)
        }
    }

    @Test func refusesArgumentsOfTheWrongShape() {
        let bad: [(String, String)] = [
            ("quitApp", #"{"bundleId":"a"}"#),                          // force missing
            ("quitApp", #"{"bundleId":"","force":false}"#),             // empty bundle id
            ("quitApp", #"{"bundleId":"a","force":0}"#),                // 0 is not a boolean
            ("quitApp", #"{"bundleId":7,"force":false}"#),
            ("quitApp", #"{"bundleId":"a","force":false,"pid":812}"#),      // extra key: a pid is never trusted
            ("quitApp", #"{"bundleId":"a","force":false,"path":"/bin/sh"}"#),
            ("media", #"{"action":"stop"}"#),
            ("media", #"{}"#),
            ("volume", #"{"level":1.5}"#),
            ("volume", #"{"level":-0.1}"#),
            ("volume", #"{"level":true}"#),
            ("volume", #"{"level":"0.5"}"#),
            ("mute", #"{"on":1}"#),
            ("lock", #"{"now":true}"#),
            ("sleep", "[]"),
            ("sleep", "not json"),
            ("displaySleep", ""),
        ]
        for (name, args) in bad {
            #expect(Command.parse(name: name, args: args) == nil, "\(name) \(args)")
        }
    }

    @Test func capsTheBundleIdentifierLength() {
        let long = String(repeating: "a", count: Command.maxBundleIdLength + 1)
        #expect(Command.parse(name: "quitApp", args: #"{"bundleId":"\#(long)","force":false}"#) == nil)
        let longest = String(repeating: "a", count: Command.maxBundleIdLength)
        #expect(Command.parse(name: "quitApp", args: #"{"bundleId":"\#(longest)","force":false}"#)
            == .quitApp(bundleId: longest, force: false))
    }

    @Test func namesMatchTheProtocol() {
        #expect(Command.quitApp(bundleId: "a", force: true).name == "quitApp")
        #expect(Command.media(.next).name == "media")
        #expect(Command.volume(level: 0.2).name == "volume")
        #expect(Command.mute(on: false).name == "mute")
        #expect(Command.lock.name == "lock")
        #expect(Command.displaySleep.name == "displaySleep")
        #expect(Command.sleep.name == "sleep")
    }
}
