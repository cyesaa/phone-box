import Foundation
import JavaScriptCore
import Testing
@testable import PhoneBoxCore

/// Runs the dashboard's `Resources/web/commands.js` in JavaScriptCore with a fake link and fake timers: the signature
/// must be exactly what `MessageAuth` checks, each answer must reach its command, and the volume slider must keep to
/// 4 values a second.
struct WebCommandTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        for name in ["sha256.js", "commands.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var now = 0, timers = [], sent = [], results = [], open = true, nonce = "6e6f6e6365";
            function later(fn, ms) { timers.push({ at: now + ms, fn: fn }); }
            function advance(ms) {
              now += ms;
              var due = timers.filter(function (t) { return t.at <= now; });
              timers = timers.filter(function (t) { return t.at > now; });
              due.forEach(function (t) { t.fn(); });
            }
            var key = new Uint8Array(32); for (var i = 0; i < 32; i += 1) key[i] = i;
            var link = { key: key, nonce: function () { return open ? nonce : null; },
              send: function (m) { if (!open) return false; sent.push(m); return true; } };
            var commands = new PhoneBox.Commands(link, { later: later });
            function done(label) { return function (result) { results.push(label + ":" + result); }; }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func signsCommandsExactlyAsTheMacChecks() throws {
        let message = string("""
            commands.run("volume", { level: 0.5 }, null);
            JSON.stringify(sent[0])
            """)
        let key = Data((0..<32).map { UInt8($0) })
        let args = #"{"level":0.5}"#
        let mac = MessageAuth.hmacHex(key: key, message: MessageAuth.commandMessage(nonce: "6e6f6e6365", seq: 1, name: "volume", args: args))
        #expect(message == #"{"v":1,"type":"cmd","seq":1,"name":"volume","args":"{\"level\":0.5}","mac":"\#(mac)"}"#)
        #expect(MessageAuth.isValid(signature: mac, key: key, message: "cmd:6e6f6e6365:1:volume:" + args))
    }

    @Test func matchesEachAnswerToItsCommand() {
        let result = string("""
            var a = commands.run("lock", {}, done("lock"));
            var b = commands.run("quitApp", { bundleId: "com.apple.Chess", force: false }, done("quit"));
            commands.acked({ seq: b, ok: false, error: "app-changed" });
            commands.acked({ seq: a, ok: true });
            commands.acked({ seq: a, ok: true });            // a second answer is ignored
            commands.acked({ seq: 99, ok: true });           // and so is one for no command
            [a, b, results.join(" ")].join(" ")
            """)
        #expect(result == "1 2 quit:app-changed lock:ok")
    }

    @Test func failsAtOnceWhenItCannotGoOutAndKeepsTheNumber() {
        let result = string("""
            open = false;
            var a = commands.run("sleep", {}, done("sleep"));
            open = true;
            var b = commands.run("lock", {}, done("lock"));
            [a, b, sent.length, results.join(" ")].join(" ")
            """)
        #expect(result == "0 1 1 sleep:failed")
    }

    @Test func failsWhenNoAnswerComesWithinFiveSeconds() {
        let result = string("""
            var a = commands.run("displaySleep", {}, done("display"));
            advance(4900);
            var early = results.length;
            advance(200);
            commands.acked({ seq: a, ok: true });            // too late
            [early, results.join(" ")].join(" ")
            """)
        #expect(result == "0 display:failed")
    }

    /// The Mac closes the socket on the 11th command within one second: the page keeps to 9 and fails the 10th
    /// without sending it.
    @Test func sendsAtMostNineCommandsASecond() {
        let result = string("""
            var limited = new PhoneBox.Commands(link, { now: function () { return now; }, later: later });
            var seqs = [];
            for (var i = 1; i <= 10; i += 1) seqs.push(limited.run("media", { action: "next" }, done("c" + i)));
            var first = sent.length;
            advance(1001);
            var again = limited.run("lock", {}, done("lock"));
            [first, seqs[8], seqs[9], again, sent.length, results.join(" ")].join(" ")
            """)
        #expect(result == "9 9 0 10 10 c10:failed")
    }

    @Test func keepsTheVolumeToFourValuesASecondAndSendsTheLast() {
        let result = string("""
            var out = [];
            var throttle = new PhoneBox.Throttle(250, function (v) { out.push(now + "=" + v); },
                                                 { now: function () { return now; }, later: later });
            throttle.push(0.1);              // goes at once
            advance(100); throttle.push(0.2);
            advance(100); throttle.push(0.3);  // replaces 0.2, still waiting
            advance(50);                     // 250 ms after the first: 0.3 goes
            advance(50); throttle.push(0.4);   // waits until 500
            advance(20); throttle.flush();     // let go at 320: 0.4 goes half an interval after 0.3, at 375
            advance(55);
            advance(145);                    // the timer at 500 sends nothing new
            throttle.flush();                // nothing left
            out.join(" ")
            """)
        #expect(result == "0=0.1 250=0.3 375=0.4")
    }

    /// A timer set before a send must not fire early after it: the Mac closes a socket that sends more than 10
    /// commands a second.
    @Test func neverSendsTwoValuesCloserThanHalfAnInterval() {
        let result = string("""
            var out = [];
            var throttle = new PhoneBox.Throttle(250, function (v) { out.push(now + "=" + v); },
                                                 { now: function () { return now; }, later: later });
            throttle.push(0.1);              // goes at once
            advance(100); throttle.push(0.2);  // a timer for 250
            advance(10); throttle.flush();     // let go at 110: 0.2 goes at 125
            advance(15);
            advance(5); throttle.push(0.3);    // touched again at 130: 250 after 125, at 375
            advance(120);                    // the timer for 250 is void
            advance(125);
            out.join(" ")
            """)
        #expect(result == "0=0.1 125=0.2 375=0.3")
    }

    @Test func aNewDragSendsTheSameValueAgain() {
        let result = string("""
            var out = [];
            var throttle = new PhoneBox.Throttle(250, function (v) { out.push(now + "=" + v); },
                                                 { now: function () { return now; }, later: later });
            throttle.push(0.5); throttle.flush();
            advance(1000); throttle.push(0.5);  // same drag: already sent
            throttle.reset(); throttle.push(0.5);  // a new drag: the Mac may have moved since
            out.join(" ")
            """)
        #expect(result == "0=0.5 1000=0.5")
    }
}
