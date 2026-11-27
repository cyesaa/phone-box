import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's `Resources/web/ui.js` in JavaScriptCore against a fake page and a fake keep-awake video: the
/// Start screen and the guide start the video, the page restarts it every 3 s, and a page that lost its pairing lets
/// the screen sleep (design §8 "Ekranı açık tutma").
struct WebUITests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        context.evaluateScript("""
            var now = 0, timers = [], intervals = [], store = {}, refuse = false;
            function setTimeout(fn, ms) { timers.push({ at: now + ms, fn: fn }); return timers.length; }
            function setInterval(fn, ms) { intervals.push({ every: ms, fn: fn }); return intervals.length; }
            // Moves the clock in 100 ms steps, running due timers and intervals.
            function advance(ms) {
              var end = now + ms;
              while (now < end) {
                now += 100;
                var due = timers.filter(function (t) { return t.at <= now; });
                timers = timers.filter(function (t) { return t.at > now; });
                due.forEach(function (t) { t.fn(); });
                intervals.forEach(function (i) { if (now % i.every === 0) i.fn(); });
              }
            }
            var performance = { now: function () { return now; } };
            function element() {
              var listeners = {};
              return {
                hidden: true, textContent: "", value: "", style: {}, classList: { toggle: function () {} },
                addEventListener: function (type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
                fire: function (type) { (listeners[type] || []).forEach(function (fn) { fn({ target: this }); }, this); },
                getBoundingClientRect: function () { return { right: 0, top: 0 }; },
                focus: function () {}, blur: function () {}, setSelectionRange: function () {}
              };
            }
            var elements = {};
            function $(id) { return elements[id] || (elements[id] = element()); }
            // The silent video: iOS pauses it while the page is hidden, and may refuse to start it without a tap.
            var video = $("keepawake"), plays = 0, pauses = 0;
            video.paused = true;
            video.play = function () {
              plays += 1;
              if (refuse) return Promise.reject({ name: "NotAllowedError" });
              video.paused = false;
              return Promise.resolve();
            };
            video.pause = function () { pauses += 1; video.paused = true; };
            var document = { getElementById: $, visibilityState: "visible", execCommand: function () { return false; },
                             documentElement: { style: { setProperty: function () {} } } };
            var navigator = { userAgent: "iPhone", standalone: false };
            var location = { origin: "http://mac.local:4747" };
            var localStorage = { getItem: function (k) { return k in store ? store[k] : null; },
                                 setItem: function (k, v) { store[k] = String(v); } };
            function matchMedia() { return { matches: false }; }
            function addEventListener() {}
            var innerWidth = 852;
            """)
        for name in ["i18n.js", "ui.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("var T = PhoneBox.i18n.texts.tr, ui = PhoneBox.ui;")
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    /// Evaluated on its own, so that the promises it settles have run before the next call reads the result.
    func run(_ code: String) { context.evaluateScript(code) }

    @Test func aStartedPageRestartsTheVideoUntilItsPairingIsLost() {
        run(#"store["phonebox-guide-done"] = "1"; ui.setup(T, true);"#)
        #expect(string("$('start').hidden") == "false")
        run("$('start-button').fire('click');")
        #expect(string("[plays, ui.isStarted(), $('start').hidden].join(' ')") == "1 true true")
        // WebKit paused it while the phone was locked: the 3 s check starts it again.
        run("video.paused = true; advance(3000);")
        #expect(string("[plays, video.paused].join(' ')") == "2 false")
        // "Eşleşmedi": the page is dead, so the screen may sleep.
        run("ui.stopKeepAwake();")
        #expect(string("[pauses, video.paused, ui.isStarted()].join(' ')") == "1 true false")
        // Locked and unlocked again: nothing starts it.
        run("video.paused = true; advance(30000);")
        #expect(string("[plays, $('start').hidden, $('guide').hidden].join(' ')") == "2 true true")
    }

    /// iOS refusing a restart brings the Start screen back on a live page, never on a dead one.
    @Test func aDeadPageNeverAsksForTheTapAgain() {
        run(#"store["phonebox-guide-done"] = "1"; ui.setup(T, true); $('start-button').fire('click');"#)
        run("refuse = true; video.paused = true; advance(3000);")
        #expect(string("[plays, $('start').hidden, ui.isStarted()].join(' ')") == "2 false false")
        run("ui.stopKeepAwake(); advance(30000);")
        #expect(string("[plays, $('start').hidden].join(' ')") == "2 true")
    }

    /// On a first visit the guide is up, and its button would start the video: it goes too. Opened again from "⋯", its
    /// button only closes it.
    @Test func aDeadPageClosesTheGuideAndItsButtonNoLongerStartsTheVideo() {
        run("ui.setup(T, true);")
        #expect(string("[$('guide').hidden, $('guide-done').textContent === T.start].join(' ')") == "false true")
        run("ui.stopKeepAwake();")
        #expect(string("$('guide').hidden") == "true")
        run("$('menu-guide').fire('click');")
        #expect(string("[$('guide').hidden, $('guide-done').textContent === T.close].join(' ')") == "false true")
        run("$('guide-done').fire('click');")
        #expect(string("[plays, $('guide').hidden, $('start').hidden].join(' ')") == "0 true true")
    }
}
