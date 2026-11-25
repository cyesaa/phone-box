import Testing
@testable import PhoneBoxCore

struct ServerMessageTests {
    @Test func encodesHello() {
        #expect(ServerMessage.hello(nonce: "ab", app: "PhoneBox 0.1.0").json()
            == #"{"app":"PhoneBox 0.1.0","nonce":"ab","type":"hello","v":1}"#)
    }

    @Test func encodesReadyWithTheAccessObject() {
        #expect(ServerMessage.ready(mode: .cable, access: .notOnCable).json()
            == #"{"access":{"commands":false,"reason":"not-on-cable","streaming":false},"mode":"cable","type":"ready","v":1}"#)
    }

    @Test func encodesAccessFlat() {
        #expect(ServerMessage.access(.granted).json()
            == #"{"commands":true,"reason":"ok","streaming":true,"type":"access","v":1}"#)
    }

    @Test func encodesSnapshotAndLeavesOutMissingMetrics() {
        let cpu = CPUSample(total: 12.5, cores: [10, 15], pCores: 1, load: [1, 2, 3])
        #expect(ServerMessage.snapshot(Snapshot(t: 1_000, cpu: cpu)).json()
            == #"{"cpu":{"cores":[10,15],"load":[1,2,3],"pCores":1,"total":12.5},"t":1000,"type":"snapshot","v":1}"#)
    }

    @Test func encodesAcks() {
        #expect(ServerMessage.ack(seq: 4, ok: true, error: nil).json() == #"{"ok":true,"seq":4,"type":"ack","v":1}"#)
        #expect(ServerMessage.ack(seq: 5, ok: false, error: "not-allowed").json()
            == #"{"error":"not-allowed","ok":false,"seq":5,"type":"ack","v":1}"#)
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
}
