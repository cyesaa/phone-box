import Testing
@testable import PhoneBoxCore

struct ServerMessageTests {
    @Test func encodesHello() {
        #expect(ServerMessage.hello(nonce: "ab", app: "PhoneBox 0.1.0").json()
            == #"{"app":"PhoneBox 0.1.0","nonce":"ab","type":"hello","v":1}"#)
    }

    @Test func encodesReadyWithTheAccessObjectAndThePowerLimits() {
        let ready = ServerMessage.ready(mode: .cable, host: "Eren's MacBook Pro", powerLimits: PowerLimits(start: 15, full: 35.5),
                                        access: .notOnCable)
        #expect(ready.json()
            == #"{"access":{"cable":false,"commands":[],"reason":"not-on-cable","streaming":false},"host":"Eren's MacBook Pro","limits":{"power":[15,35.5]},"mode":"cable","type":"ready","v":1}"#)
    }

    @Test func readyNamesTheDashboardsFilesWhenItKnowsThem() {
        let ready = ServerMessage.ready(mode: .always, host: "Mac", powerLimits: PowerLimits(start: 15, full: 35),
                                        access: .overWiFi, build: "0123456789ab")
        #expect(ready.json()
            == #"{"access":{"cable":false,"commands":[],"reason":"ok","streaming":true},"build":"0123456789ab","host":"Mac","limits":{"power":[15,35]},"mode":"always","type":"ready","v":1}"#)
    }

    @Test func readyListsTheCommandsThePhoneMaySend() {
        let limits = PowerLimits(start: 15, full: 35)
        #expect(ServerMessage.ready(mode: .always, host: "Mac", powerLimits: limits, access: .overWiFiWithLockAndMusic).json()
            == #"{"access":{"cable":false,"commands":["media","lock"],"reason":"ok","streaming":true},"host":"Mac","limits":{"power":[15,35]},"mode":"always","type":"ready","v":1}"#)
        #expect(ServerMessage.ready(mode: .cable, host: "Mac", powerLimits: limits, access: .onCable).json()
            == #"{"access":{"cable":true,"commands":["quitApp","media","volume","mute","lock","displaySleep","sleep"],"reason":"ok","streaming":true},"host":"Mac","limits":{"power":[15,35]},"mode":"cable","type":"ready","v":1}"#)
    }

    @Test func encodesAccessFlat() {
        #expect(ServerMessage.access(.onCable).json()
            == #"{"cable":true,"commands":["quitApp","media","volume","mute","lock","displaySleep","sleep"],"reason":"ok","streaming":true,"type":"access","v":1}"#)
        #expect(ServerMessage.access(.overWiFi).json()
            == #"{"cable":false,"commands":[],"reason":"ok","streaming":true,"type":"access","v":1}"#)
        #expect(ServerMessage.access(.overWiFiWithLockAndMusic).json()
            == #"{"cable":false,"commands":["media","lock"],"reason":"ok","streaming":true,"type":"access","v":1}"#)
    }

    @Test func encodesSnapshotAndLeavesOutMissingMetrics() {
        let cpu = CPUSample(total: 12.5, cores: [10, 15], pCores: 1, load: [1, 2, 3])
        #expect(ServerMessage.snapshot(Snapshot(t: 1_000, cpu: cpu)).json()
            == #"{"cpu":{"cores":[10,15],"load":[1,2,3],"pCores":1,"total":12.5},"t":1000,"type":"snapshot","v":1}"#)
    }

    @Test func encodesEveryPlan3AMetric() {
        let snapshot = Snapshot(
            t: 5, gpu: GPUSample(util: 17), temp: TemperatureSample(avg: 52.5, max: 56), power: PowerSample(gpu: 0.2, system: nil),
            net: NetworkSample(rx: 1_200, tx: 30, iface: "en0"), disk: DiskSample(free: 10, total: 20, read: nil, write: 4),
            battery: BatterySample(percent: 86, charging: true, plugged: true, minutesLeft: nil),
            apps: [AppSample(pid: 9, bundleId: nil, name: "node", cpu: 1.5, mem: 64, quittable: false)])
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"apps":[{"cpu":1.5,"mem":64,"name":"node","pid":9,"quittable":false}],"#
            + #""battery":{"charging":true,"percent":86,"plugged":true},"disk":{"free":10,"total":20,"write":4},"gpu":{"util":17},"#
            + #""net":{"iface":"en0","rx":1200,"tx":30},"power":{"gpu":0.2},"t":5,"temp":{"avg":52.5,"max":56},"#
            + #""type":"snapshot","v":1}"#)
    }

    @Test func encodesMediaAndAudio() {
        let snapshot = Snapshot(t: 9, media: MediaSample(title: "Kara Toprak", artist: nil, app: "Spotify", playing: true),
                                audio: AudioSample(volume: 0.5, muted: false))
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"audio":{"muted":false,"volume":0.5},"media":{"app":"Spotify","playing":true,"title":"Kara Toprak"},"t":9,"type":"snapshot","v":1}"#)
    }

    @Test func encodesThePhonesBattery() {
        let snapshot = Snapshot(t: 3, phone: PhoneBatterySample(percent: 76, charging: true, plugged: true))
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"phone":{"charging":true,"percent":76,"plugged":true},"t":3,"type":"snapshot","v":1}"#)
    }

    @Test func encodesClaudeSessions() {
        let session = ClaudeSession(id: "s1", title: "Menü", project: "PhoneBox", model: "Opus 5.5", state: .waiting,
                                    reason: .question, activity: nil, since: 1_700)
        #expect(ServerMessage.snapshot(Snapshot(t: 2, claude: [session])).json()
            == #"{"claude":[{"id":"s1","model":"Opus 5.5","project":"PhoneBox","reason":"question","since":1700,"state":"waiting","title":"Menü"}],"t":2,"type":"snapshot","v":1}"#)
        // On but no session open: an empty list, so the page keeps its second page.
        #expect(ServerMessage.snapshot(Snapshot(t: 2, claude: [])).json() == #"{"claude":[],"t":2,"type":"snapshot","v":1}"#)
        // Off: no `claude` at all.
        #expect(ServerMessage.snapshot(Snapshot(t: 2)).json() == #"{"t":2,"type":"snapshot","v":1}"#)
    }

    @Test func aSnapshotThatFallsBackKeepsItsClaudeSessions() {
        // Without them the page would take the feature for turned off and leave the Claude page for a second.
        let session = ClaudeSession(id: "s", title: "T", project: "P", model: nil, state: .ready, reason: nil, activity: nil, since: 1)
        let snapshot = Snapshot(t: 7, cpu: CPUSample(total: .nan, cores: [], pCores: 0, load: []), claude: [session])
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"claude":[{"id":"s","project":"P","since":1,"state":"ready","title":"T"}],"t":7,"type":"snapshot","v":1}"#)
    }

    @Test func aSnapshotWithANonFiniteNumberFallsBackToItsTimestamp() {
        let snapshot = Snapshot(t: 7, cpu: CPUSample(total: .nan, cores: [], pCores: 0, load: []), gpu: GPUSample(util: 3))
        #expect(ServerMessage.snapshot(snapshot).json() == #"{"t":7,"type":"snapshot","v":1}"#)
    }

    @Test func encodesAcks() {
        #expect(ServerMessage.ack(seq: 4, ok: true, error: nil).json() == #"{"ok":true,"seq":4,"type":"ack","v":1}"#)
        #expect(ServerMessage.ack(seq: 5, ok: false, error: "not-allowed").json()
            == #"{"error":"not-allowed","ok":false,"seq":5,"type":"ack","v":1}"#)
    }

    @Test func buildsAcksFromCommandResults() {
        #expect(ServerMessage.ack(seq: 1, result: .ok) == .ack(seq: 1, ok: true, error: nil))
        #expect(ServerMessage.ack(seq: 2, result: .failed(.appChanged)) == .ack(seq: 2, ok: false, error: "app-changed"))
        #expect(ServerMessage.ack(seq: 3, result: .failed(.notAllowed)) == .ack(seq: 3, ok: false, error: "not-allowed"))
    }
}

struct ClientMessageTests {
    @Test func parsesAuth() {
        #expect(ClientMessage.parse(#"{"v":1,"type":"auth","mac":"ff"}"#) == .auth(mac: "ff"))
    }

    @Test func parsesCommandsKeepingArgsAsText() {
        #expect(ClientMessage.parse(#"{"v":1,"type":"cmd","seq":2,"name":"mute","args":"{\"on\":true}","mac":"aa"}"#)
            == .command(seq: 2, name: "mute", args: #"{"on":true}"#, mac: "aa"))
    }

    @Test func rejectsOtherVersionsTypesAndJunk() {
        #expect(ClientMessage.parse(#"{"v":2,"type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":1,"type":"hello"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":1,"type":"cmd","seq":"2","name":"x","args":"{}","mac":"a"}"#) == nil)
        #expect(ClientMessage.parse("not json") == nil)
        #expect(ClientMessage.parse("[1,2]") == nil)
    }

    @Test func versionMustBeTheInteger1() {
        #expect(ClientMessage.parse(#"{"v":true,"type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":1.0,"type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":"1","type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"type":"auth","mac":"ff"}"#) == nil)
    }

    @Test func sequenceNumbersMustBePositiveSafeIntegers() {
        func cmd(_ seq: String) -> ClientMessage? {
            ClientMessage.parse(#"{"v":1,"type":"cmd","seq":\#(seq),"name":"lock","args":"{}","mac":"a"}"#)
        }
        #expect(cmd("1") == .command(seq: 1, name: "lock", args: "{}", mac: "a"))
        #expect(cmd("9007199254740991") == .command(seq: 9_007_199_254_740_991, name: "lock", args: "{}", mac: "a"))
        #expect(cmd("true") == nil)
        #expect(cmd("2.0") == nil)
        #expect(cmd("2.5") == nil)
        #expect(cmd("0") == nil)
        #expect(cmd("-3") == nil)
        #expect(cmd("9007199254740992") == nil)
        #expect(cmd("1e3") == nil)
    }
}
