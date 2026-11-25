import Testing
@testable import PhoneBoxCore

struct ServerMessageTests {
    @Test func encodesHello() {
        #expect(ServerMessage.hello(nonce: "ab", app: "PhoneBox 0.1.0").json()
            == #"{"app":"PhoneBox 0.1.0","nonce":"ab","type":"hello","v":1}"#)
    }

    @Test func encodesReadyWithTheAccessObject() {
        #expect(ServerMessage.ready(mode: .cable, host: "Eren's MacBook Pro", access: .notOnCable).json()
            == #"{"access":{"cable":false,"commands":false,"reason":"not-on-cable","streaming":false},"host":"Eren's MacBook Pro","mode":"cable","type":"ready","v":1}"#)
    }

    @Test func encodesAccessFlat() {
        #expect(ServerMessage.access(.onCable).json()
            == #"{"cable":true,"commands":true,"reason":"ok","streaming":true,"type":"access","v":1}"#)
        #expect(ServerMessage.access(.overWiFi).json()
            == #"{"cable":false,"commands":false,"reason":"ok","streaming":true,"type":"access","v":1}"#)
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
            battery: BatterySample(percent: 86, charging: true, minutesLeft: nil),
            apps: [AppSample(pid: 9, bundleId: nil, name: "node", cpu: 1.5, mem: 64, quittable: false)])
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"apps":[{"cpu":1.5,"mem":64,"name":"node","pid":9,"quittable":false}],"#
            + #""battery":{"charging":true,"percent":86},"disk":{"free":10,"total":20,"write":4},"gpu":{"util":17},"#
            + #""net":{"iface":"en0","rx":1200,"tx":30},"power":{"gpu":0.2},"t":5,"temp":{"avg":52.5,"max":56},"#
            + #""type":"snapshot","v":1}"#)
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
