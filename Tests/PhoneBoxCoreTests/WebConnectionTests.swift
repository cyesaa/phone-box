import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's `Resources/web/connection.js` in JavaScriptCore against a fake clock, fake timers and a fake
/// WebSocket, to check its reconnect rules (design §5 "Yeniden bağlanma").
struct WebConnectionTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        context.evaluateScript("""
            var now = 1000000, timers = [], intervals = [], sockets = [], states = [], opened = [];
            Date.now = function () { return now; };
            function setTimeout(fn, delay) { timers.push({ at: now + delay, fn: fn }); return timers.length; }
            function setInterval(fn) { intervals.push(fn); return intervals.length; }
            function addEventListener() {}
            var document = { visibilityState: "visible" };
            var location = { host: "mac.local:4747", hash: "" };
            var PBCrypto = { hmacHex: function () { return "signature"; } };
            function WebSocket(url) { this.readyState = 0; this.sent = []; sockets.push(this); opened.push(now - 1000000); }
            WebSocket.CONNECTING = 0; WebSocket.OPEN = 1; WebSocket.CLOSING = 2; WebSocket.CLOSED = 3;
            WebSocket.prototype.send = function (text) { this.sent.push(JSON.parse(text)); };
            WebSocket.prototype.close = function () { this.readyState = 3; };
            // Moves the clock in 100 ms steps, running due timers and the once-a-second ticker.
            function advance(ms) {
              var end = now + ms;
              while (now < end) {
                now += 100;
                var due = timers.filter(function (t) { return t.at <= now; });
                timers = timers.filter(function (t) { return t.at > now; });
                due.forEach(function (t) { t.fn(); });
                if (now % 1000 === 0) intervals.forEach(function (f) { f(); });
              }
            }
            function last() { return sockets[sockets.length - 1]; }
            function open(s) { s.readyState = 1; }
            function receive(s, message) { s.onmessage({ data: JSON.stringify(message) }); }
            function fail(s) { s.readyState = 3; s.onclose({ code: 1006 }); }
            function closeWith(s, code) { s.readyState = 3; s.onclose({ code: code }); }
            function handshake(s, access) {
              open(s);
              receive(s, { v: 1, type: "hello", nonce: "n" });
              receive(s, { v: 1, type: "ready", mode: "cable", host: "Mac", access: access });
            }
            """)
        let url = WebPageTests.webDirectory.appendingPathComponent("connection.js")
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        context.evaluateScript("""
            var connection = new PhoneBox.Connection(new Uint8Array(32), {
              onState: function (kind) { states.push(kind); }, onStale: function () {}, onReady: function () {},
              onAccess: function () {}, onSnapshot: function () {}
            });
            connection.start();
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func reloadsOnlyWhenALaterReadyNamesOtherFiles() {
        #expect(string("""
            var watch = new PhoneBox.BuildWatch();
            [watch.changed("0123456789ab"), watch.changed("0123456789ab"), watch.changed(undefined), watch.changed(""),
             watch.changed("ba9876543210")].join(",")
            """) == "false,false,false,false,true")
    }

    @Test func backsOffOneTwoFiveSecondsAndKeepsTheOfflineCardUp() {
        let result = string("""
            for (var i = 0; i < 5; i += 1) { var count = sockets.length; fail(last()); while (sockets.length === count) advance(100); }
            opened.join(",") + " / " + states.join(",")
            """)
        #expect(result == "0,1000,3000,8000,13000,18000 / connecting,connecting,connecting,offline,offline,offline")
    }

    @Test func sendsCommandsOnlyAfterReady() {
        let result = string("""
            var s = last(); open(s);
            var before = connection.send({ type: "cmd" });
            receive(s, { v: 1, type: "hello", nonce: "n" });
            var afterHello = connection.send({ type: "cmd" });
            receive(s, { v: 1, type: "ready", mode: "cable", host: "Mac", access: { streaming: true, commands: true, cable: true, reason: "ok" } });
            var afterReady = connection.send({ type: "cmd" });
            [before, afterHello, afterReady, s.sent.map(function (m) { return m.type; }).join("+")].join(" ")
            """)
        #expect(result == "false false true auth+cmd")
    }

    @Test func givesUpOnASocketThatNeverAuthenticates() {
        let result = string("""
            open(last());
            advance(6000);
            var stillOpen = sockets[0].readyState;
            advance(1000);
            var closedAt = sockets[0].readyState;
            advance(1000);
            [stillOpen, closedAt, sockets.length, states.join(",")].join(" ")
            """)
        #expect(result == "1 3 2 connecting,connecting")
    }

    @Test func keepsThePlugInCardAcrossRechecks() {
        let result = string("""
            var notOnCable = { streaming: false, commands: false, cable: false, reason: "not-on-cable" };
            handshake(last(), notOnCable);
            advance(10500);
            var count = sockets.length;
            handshake(last(), notOnCable);
            [count, states.join(",")].join(" ")
            """)
        #expect(result == "2 connecting,cable,cable")
    }

    @Test func stopsForGoodOnAWrongKey() {
        let result = string("""
            open(last());
            closeWith(last(), 4001);
            advance(30000);
            [sockets.length, states.join(","), connection.send({ type: "cmd" })].join(" ")
            """)
        #expect(result == "1 connecting,unpaired false")
    }

    @Test func aReplacedSocketMustAuthenticateAgainBeforeCommands() {
        let result = string("""
            handshake(last(), { streaming: true, commands: true, cable: true, reason: "ok" });
            var before = connection.send({ type: "cmd" });
            connection.replace();
            var replaced = connection.send({ type: "cmd" });
            var s = last(); open(s);
            receive(s, { v: 1, type: "hello", nonce: "m" });
            var afterHello = connection.send({ type: "cmd" });
            receive(s, { v: 1, type: "ready", mode: "cable", host: "Mac", access: { streaming: true, commands: true, cable: true, reason: "ok" } });
            [before, replaced, afterHello, connection.send({ type: "cmd" }), connection.nonce, sockets.length].join(" ")
            """)
        #expect(result == "true false false true m 2")
    }

    @Test func reconnectsQuicklyWhenTheMacAsks() {
        let result = string("""
            handshake(last(), { streaming: true, commands: true, cable: false, reason: "ok" });
            closeWith(last(), 4002);
            advance(300);
            [opened.join(","), connection.send({ type: "cmd" })].join(" ")
            """)
        #expect(result == "0,300 false")
    }
}
