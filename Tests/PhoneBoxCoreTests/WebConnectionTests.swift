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
            // `now` is the page's own clock, which only moves forward; the wall clock is `wall` ms off it and can step.
            var wall = 0;
            var performance = { now: function () { return now; } };
            Date.now = function () { return now + wall; };
            function setTimeout(fn, delay) { timers.push({ at: now + delay, fn: fn }); return timers.length; }
            function setInterval(fn) { intervals.push(fn); return intervals.length; }
            var listeners = {};
            function addEventListener(name, fn) { (listeners[name] = listeners[name] || []).push(fn); }
            function fire(name) { (listeners[name] || []).forEach(function (fn) { fn(); }); }
            var document = { visibilityState: "visible" };
            // The phone locked for `ms`: the page hidden, its own clock stopped (WebKit's `performance.now()` does not
            // count the phone's sleep), the wall clock on. Then unlocked: the three events that come with it.
            function lockFor(ms) { document.visibilityState = "hidden"; fire("visibilitychange"); wall += ms; }
            function unlock() {
              document.visibilityState = "visible";
              fire("visibilitychange"); fire("pageshow"); fire("focus");
            }
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

    @Test func aPageThatKnowsItsBuildReloadsOnTheFirstReadyThatNamesOthers() {
        #expect(string("""
            var same = new PhoneBox.BuildWatch("0123456789ab"), other = new PhoneBox.BuildWatch("0123456789ab");
            [same.changed("0123456789ab"), same.changed("0123456789ab"), same.changed(undefined),
             other.changed("ba9876543210")].join(",")
            """) == "false,false,false,true")
    }

    @Test func aPageWithoutItsBuildGoesByTheFirstReady() {
        #expect(string("""
            var empty = new PhoneBox.BuildWatch(""), missing = new PhoneBox.BuildWatch(null),
                none = new PhoneBox.BuildWatch();
            [empty.changed("0123456789ab"), empty.changed("ba9876543210"), missing.changed("0123456789ab"),
             missing.changed("0123456789ab"), none.changed("0123456789ab"), none.changed("ba9876543210")].join(",")
            """) == "false,true,false,false,false,true")
    }

    @Test func anOwnBuildThatIsNotTwelveHexDigitsCountsAsNone() {
        #expect(string("""
            var odd = ["XYZ", "0123456789a", "0123456789abc", "0123456789AB", "0123456789ag"].map(function (own) {
                var watch = new PhoneBox.BuildWatch(own);
                return [watch.changed("0123456789ab"), watch.changed("ba9876543210")].join("/");
            });
            odd.join(",")
            """) == "false/true,false/true,false/true,false/true,false/true")
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
            receive(s, { v: 1, type: "ready", mode: "cable", host: "Mac", access: { streaming: true, commands: ["quitApp", "media", "volume", "mute", "lock", "displaySleep", "sleep"], cable: true, reason: "ok" } });
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
            var notOnCable = { streaming: false, commands: [], cable: false, reason: "not-on-cable" };
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
            handshake(last(), { streaming: true, commands: ["quitApp", "media", "volume", "mute", "lock", "displaySleep", "sleep"], cable: true, reason: "ok" });
            var before = connection.send({ type: "cmd" });
            connection.replace();
            var replaced = connection.send({ type: "cmd" });
            var s = last(); open(s);
            receive(s, { v: 1, type: "hello", nonce: "m" });
            var afterHello = connection.send({ type: "cmd" });
            receive(s, { v: 1, type: "ready", mode: "cable", host: "Mac", access: { streaming: true, commands: ["quitApp", "media", "volume", "mute", "lock", "displaySleep", "sleep"], cable: true, reason: "ok" } });
            [before, replaced, afterHello, connection.send({ type: "cmd" }), connection.nonce, sockets.length].join(" ")
            """)
        #expect(result == "true false false true m 2")
    }

    /// The phone's clock set back (by hand, or a large correction) while the page waits to retry: the waits are timed on
    /// the page's own clock, so it goes on retrying.
    @Test func keepsRetryingWhenTheWallClockStepsBack() {
        let result = string("""
            fail(last());
            wall = -3600000;
            advance(1500);
            var afterOne = sockets.length;
            fail(last());
            advance(2500);
            [afterOne, sockets.length].join(" ")
            """)
        #expect(result == "2 3")
    }

    /// The same step while the socket has silently died: the values still go stale after more than 3 s and the socket
    /// is replaced after more than 5 s (checked once a second).
    @Test func findsASilentSocketWhenTheWallClockStepsBack() {
        let result = string("""
            handshake(last(), { streaming: true, commands: [], cable: true, reason: "ok" });
            receive(last(), { v: 1, type: "snapshot", t: 1 });
            wall = -3600000;
            advance(4500);
            var stale = connection.stale, count = sockets.length;
            advance(1500);
            [stale, count, sockets.length].join(" ")
            """)
        #expect(result == "true 1 2")
    }

    /// The Mac began closing a socket, and the once-a-second tick opened the next one before the first one's close
    /// event came. That late event belongs to a socket that is gone: the live one stays as it is.
    @Test func aLateCloseFromASocketThatWasReplacedChangesNothing() {
        let result = string("""
            var streaming = { streaming: true, commands: [], cable: true, reason: "ok" };
            var first = last();
            handshake(first, streaming);
            first.readyState = 2;   // closing: the Mac's close frame came, the close event has not yet
            advance(1000);
            var second = last();
            handshake(second, streaming);
            receive(second, { v: 1, type: "snapshot", t: 1 });
            var waits = timers.length;
            closeWith(first, 1001);
            [sockets.length, connection.state, connection.stale, connection.retries, timers.length - waits, states.join(",")].join(" ")
            """)
        #expect(result == "2 streaming false 0 0 connecting,streaming,streaming")
    }

    /// After two minutes locked, the socket the phone slept on is dead, but by the page's own clock its last message
    /// is a second old: the wall clock tells how long the page was away, and the socket is replaced at once instead of
    /// showing stale values as live for another five seconds.
    @Test func replacesTheSocketAtOnceAfterTheLockedPhoneSlept() {
        let result = string("""
            handshake(last(), { streaming: true, commands: [], cable: true, reason: "ok" });
            receive(last(), { v: 1, type: "snapshot", t: 1 });
            advance(1000);
            lockFor(120000);
            unlock();
            [sockets.length, sockets[0].readyState, sockets[0].onclose === null, connection.stale].join(" ")
            """)
        #expect(result == "2 3 true true")
    }

    /// A lock shorter than a dead socket's silence keeps the socket; a wall clock set back while away replaces it.
    @Test func keepsTheSocketAfterAShortLockAndReplacesItAfterAClockStep() {
        let result = string("""
            handshake(last(), { streaming: true, commands: [], cable: true, reason: "ok" });
            receive(last(), { v: 1, type: "snapshot", t: 1 });
            advance(1000);
            lockFor(4000);
            unlock();
            var afterShort = sockets.length;
            advance(1000);
            receive(last(), { v: 1, type: "snapshot", t: 2 });
            lockFor(-3600000);
            unlock();
            [afterShort, sockets.length].join(" ")
            """)
        #expect(result == "1 2")
    }

    @Test func reconnectsQuicklyWhenTheMacAsks() {
        let result = string("""
            handshake(last(), { streaming: true, commands: ["quitApp", "media", "volume", "mute", "lock", "displaySleep", "sleep"], cable: false, reason: "ok" });
            closeWith(last(), 4002);
            advance(300);
            [opened.join(","), connection.send({ type: "cmd" })].join(" ")
            """)
        #expect(result == "0,300 false")
    }
}
