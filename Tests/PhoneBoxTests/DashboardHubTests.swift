import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// A phone's WebSocket that only records what the hub does with it.
@MainActor
final class FakeConnection: PhoneConnection {
    let interfaceName: String?
    let arrivedOnScopedLinkLocal: Bool
    var lastInboundAt = ContinuousClock.now
    private(set) var sent: [ServerMessage] = []
    private(set) var closeCode: UInt16?
    private(set) var authenticated = false
    private(set) var pings = 0
    private(set) var cancelled = false

    init(interfaceName: String, scopedLinkLocal: Bool) {
        self.interfaceName = interfaceName
        self.arrivedOnScopedLinkLocal = scopedLinkLocal
    }

    func send(_ message: ServerMessage) { sent.append(message) }
    func sendPing() { pings += 1 }
    func markAuthenticated() { authenticated = true }
    func close(code: UInt16, reason: String) { closeCode = code }
    func cancel() { cancelled = true }

    var nonce: String? {
        for case let .hello(nonce, _) in sent { return nonce }
        return nil
    }
}

/// Records the commands and answers with `result`; with `hold`, keeps the completions for the test to call.
@MainActor
final class FakeRunner: CommandRunning {
    var result: CommandResult = .ok
    var hold = false
    private(set) var commands: [Command] = []
    private(set) var pending: [@MainActor (CommandResult) -> Void] = []

    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
        commands.append(command)
        if hold { pending.append(completion) } else { completion(result) }
    }
}

@MainActor
struct DashboardHubTests {
    let key = PairingKey.generate()
    let runner = FakeRunner()
    let limits = PowerLimits(start: 25, full: 60)

    func makeHub(mode: AccessMode) -> DashboardHub {
        DashboardHub(mode: mode, key: key, appName: "PhoneBox test", hostName: "Test Mac", powerLimits: limits,
                     commands: runner, usbInterfaces: { ["anri1"] })
    }

    /// A phone on the USB link (`anri1`, scoped link-local) or on Wi-Fi (`en0`), authenticated.
    func connect(_ hub: DashboardHub, onUSB: Bool) -> FakeConnection {
        let phone = onUSB ? FakeConnection(interfaceName: "anri1", scopedLinkLocal: true)
                          : FakeConnection(interfaceName: "en0", scopedLinkLocal: true)
        hub.opened(phone)
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.authMessage(nonce: phone.nonce ?? ""))
        hub.received(#"{"v":1,"type":"auth","mac":"\#(mac)"}"#, from: phone)
        return phone
    }

    func command(_ phone: FakeConnection, seq: Int, name: String, args: String) -> String {
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.commandMessage(
            nonce: phone.nonce ?? "", seq: seq, name: name, args: args))
        let escaped = args.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"v":1,"type":"cmd","seq":\#(seq),"name":"\#(name)","args":"\#(escaped)","mac":"\#(mac)"}"#
    }

    @Test func readyCarriesTheWebBuild() {
        let hub = DashboardHub(mode: .always, key: key, appName: "PhoneBox test", hostName: "Test Mac", powerLimits: limits,
                               build: "0123456789ab", commands: runner, usbInterfaces: { ["anri1"] })
        let phone = connect(hub, onUSB: true)
        #expect(phone.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .onCable,
                                          build: "0123456789ab"))
    }

    @Test func readyCarriesTheMacsNameAndTheConnectionPath() {
        let hub = makeHub(mode: .always)
        let cable = connect(hub, onUSB: true)
        let wifi = connect(hub, onUSB: false)
        #expect(cable.authenticated && wifi.authenticated)
        #expect(cable.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .onCable))
        #expect(wifi.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .overWiFi))
    }

    @Test func runsACommandFromTheCableAndAcksIt() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        hub.received(command(phone, seq: 1, name: "mute", args: #"{"on":true}"#), from: phone)
        #expect(runner.commands == [.mute(on: true)])
        #expect(phone.sent.last == .ack(seq: 1, ok: true, error: nil))
    }

    @Test func refusesCommandsOverWiFiEvenInAlwaysMode() {
        let hub = makeHub(mode: .always)
        let phone = connect(hub, onUSB: false)
        hub.received(command(phone, seq: 1, name: "sleep", args: "{}"), from: phone)
        #expect(runner.commands.isEmpty)
        #expect(phone.sent.last == .ack(seq: 1, ok: false, error: "not-allowed"))
    }

    @Test func anUnscopedAddressOnTheUSBLinkIsNotTheCable() {
        let hub = makeHub(mode: .always)
        let phone = FakeConnection(interfaceName: "anri1", scopedLinkLocal: false)  // IPv4 on the USB link
        hub.opened(phone)
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.authMessage(nonce: phone.nonce ?? ""))
        hub.received(#"{"v":1,"type":"auth","mac":"\#(mac)"}"#, from: phone)
        #expect(phone.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .overWiFi))
    }

    @Test func reportsWhyACommandFailed() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        runner.result = .failed(.appChanged)
        hub.received(command(phone, seq: 3, name: "quitApp", args: #"{"bundleId":"com.example.Gone","force":false}"#), from: phone)
        #expect(runner.commands == [.quitApp(bundleId: "com.example.Gone", force: false)])
        #expect(phone.sent.last == .ack(seq: 3, ok: false, error: "app-changed"))
    }

    @Test func neverRunsUnknownOrMalformedCommands() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        hub.received(command(phone, seq: 1, name: "shutdown", args: "{}"), from: phone)
        hub.received(command(phone, seq: 2, name: "volume", args: #"{"level":"loud"}"#), from: phone)
        #expect(runner.commands.isEmpty)
        #expect(phone.sent.suffix(2) == [.ack(seq: 1, ok: false, error: "not-allowed"), .ack(seq: 2, ok: false, error: "unsupported")])
    }

    @Test func dropsTheAckWhenThePhoneLeftWhileTheCommandRan() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        runner.hold = true
        hub.received(command(phone, seq: 1, name: "lock", args: "{}"), from: phone)
        #expect(runner.pending.count == 1)
        let before = phone.sent.count
        hub.closed(phone)
        runner.pending.first?(.ok)
        #expect(phone.sent.count == before)
    }

    @Test func switchingModesSendsTheNewAccess() {
        let hub = makeHub(mode: .cable)
        var streaming: [Bool] = []
        hub.onStreamingChange = { streaming.append($0) }
        let phone = connect(hub, onUSB: false)
        #expect(phone.sent.last == .ready(mode: .cable, host: "Test Mac", powerLimits: limits, access: .notOnCable))
        hub.mode = .always
        #expect(phone.sent.last == .access(.overWiFi))
        #expect(streaming == [true])
    }

    /// The settings window says how many phones get data, and whether over the cable or over Wi-Fi.
    @Test func reportsThePhonesOnTheCableAndOnWiFi() {
        let hub = makeHub(mode: .cable)
        var counts: [PhoneCounts] = []
        hub.onClientsChange = { counts.append($0) }
        let wifi = connect(hub, onUSB: false)
        #expect(counts.last == PhoneCounts(onCable: 0, overWiFi: 0, waitingForCable: 1))
        _ = connect(hub, onUSB: true)
        #expect(counts.last == PhoneCounts(onCable: 1, overWiFi: 0, waitingForCable: 1))
        #expect(counts.last?.streaming == 1)
        hub.mode = .always
        #expect(counts.last == PhoneCounts(onCable: 1, overWiFi: 1, waitingForCable: 0))
        #expect(counts.last?.streaming == 2)
        hub.closed(wifi)
        #expect(counts.last == PhoneCounts(onCable: 1, overWiFi: 0, waitingForCable: 0))
    }

    @Test func lockAndMusicOverWiFiOpensOnlyThoseToWiFiPhones() {
        let hub = makeHub(mode: .always)
        let wifi = connect(hub, onUSB: false)
        let cable = connect(hub, onUSB: true)
        #expect(wifi.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .overWiFi))
        #expect(Access.overWiFi.commands.isEmpty)
        let cableSent = cable.sent.count

        hub.lockAndMusicOverWiFi = true
        #expect(wifi.sent.last == .access(Access(streaming: true, commands: ["media", "lock"], cable: false, reason: "ok")))
        hub.received(command(wifi, seq: 1, name: "lock", args: "{}"), from: wifi)
        #expect(runner.commands == [.lock])
        #expect(wifi.sent.last == .ack(seq: 1, ok: true, error: nil))
        hub.received(command(wifi, seq: 2, name: "volume", args: #"{"level":0.5}"#), from: wifi)
        #expect(runner.commands == [.lock])
        #expect(wifi.sent.last == .ack(seq: 2, ok: false, error: "not-allowed"))
        #expect(cable.sent.count == cableSent)

        hub.lockAndMusicOverWiFi = false
        #expect(wifi.sent.last == .access(.overWiFi))
        #expect(cable.sent.count == cableSent)
    }

    @Test func lockAndMusicOverWiFiChangesNothingInCableMode() {
        let hub = makeHub(mode: .cable)
        let wifi = connect(hub, onUSB: false)
        let sent = wifi.sent.count
        hub.lockAndMusicOverWiFi = true
        #expect(wifi.sent.count == sent)
        hub.received(command(wifi, seq: 1, name: "lock", args: "{}"), from: wifi)
        #expect(runner.commands.isEmpty)
        #expect(wifi.sent.last == .ack(seq: 1, ok: false, error: "not-allowed"))
    }

    @Test func aWiFiPhoneThatConnectsWhileItIsOnGetsLockAndMusic() {
        let hub = DashboardHub(mode: .always, lockAndMusicOverWiFi: true, key: key, appName: "PhoneBox test", hostName: "Test Mac",
                               powerLimits: limits, commands: runner, usbInterfaces: { ["anri1"] })
        let wifi = connect(hub, onUSB: false)
        #expect(wifi.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .overWiFiWithLockAndMusic))
        hub.received(command(wifi, seq: 1, name: "media", args: #"{"action":"playPause"}"#), from: wifi)
        #expect(runner.commands == [.media(.playPause)])
    }

    @Test func aWiFiPhoneMayLockOnlyOnceEvery30SecondsButTheCableIsNotLimited() {
        let hub = DashboardHub(mode: .always, lockAndMusicOverWiFi: true, key: key, appName: "PhoneBox test", hostName: "Test Mac",
                               powerLimits: limits, commands: runner, usbInterfaces: { ["anri1"] })
        let wifi = connect(hub, onUSB: false)
        hub.received(command(wifi, seq: 1, name: "lock", args: "{}"), from: wifi)
        hub.received(command(wifi, seq: 2, name: "lock", args: "{}"), from: wifi)
        #expect(runner.commands == [.lock])
        #expect(wifi.sent.suffix(2) == [.ack(seq: 1, ok: true, error: nil), .ack(seq: 2, ok: false, error: "failed")])

        let cable = connect(hub, onUSB: true)
        hub.received(command(cable, seq: 1, name: "lock", args: "{}"), from: cable)
        hub.received(command(cable, seq: 2, name: "lock", args: "{}"), from: cable)
        #expect(runner.commands == [.lock, .lock, .lock])
        #expect(cable.sent.suffix(2) == [.ack(seq: 1, ok: true, error: nil), .ack(seq: 2, ok: true, error: nil)])
    }

    @Test func aConnectedWiFiPhoneLosesLockAndMusicInCableModeAndGetsThemBack() {
        let hub = DashboardHub(mode: .always, lockAndMusicOverWiFi: true, key: key, appName: "PhoneBox test", hostName: "Test Mac",
                               powerLimits: limits, commands: runner, usbInterfaces: { ["anri1"] })
        let wifi = connect(hub, onUSB: false)
        hub.mode = .cable
        #expect(wifi.sent.last == .access(.notOnCable))
        hub.mode = .always
        #expect(wifi.sent.last == .access(Access(streaming: true, commands: ["media", "lock"], cable: false, reason: "ok")))
    }

    @Test func pluggingInAnIPhoneMovesWiFiPhonesToTheCableInBothModes() {
        for mode in AccessMode.allCases {
            let hub = makeHub(mode: mode)
            let wifi = connect(hub, onUSB: false)
            let cable = connect(hub, onUSB: true)
            hub.iPhonePluggedIn()
            #expect(wifi.closeCode == DashboardHub.reconnectCode, "\(mode)")
            #expect(cable.closeCode == nil, "\(mode)")
        }
    }

    /// Liveness runs on a monotonic clock that counts sleep: setting the Mac's clock neither drops live phones nor keeps
    /// dead ones.
    @Test func dropsAPhoneSilentForLongerThanTheLimitAndPingsTheOthers() {
        let hub = makeHub(mode: .always)
        let silent = connect(hub, onUSB: false)
        let live = connect(hub, onUSB: true)
        let now = ContinuousClock.now
        silent.lastInboundAt = now - .seconds(DashboardHub.silenceLimit + 1)
        live.lastInboundAt = now - .seconds(DashboardHub.silenceLimit - 1)
        hub.checkLiveness(now: now)
        #expect(silent.cancelled && silent.pings == 0)
        #expect(!live.cancelled && live.pings == 1)
    }

    @Test func aBadSignatureClosesTheConnection() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        let forged = command(phone, seq: 1, name: "mute", args: #"{"on":true}"#).replacingOccurrences(of: "mute", with: "lock")
        hub.received(forged, from: phone)
        #expect(phone.closeCode == Session.policyViolationCode)
        #expect(runner.commands.isEmpty)
    }
}
