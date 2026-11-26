import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's `Resources/web/controls.js` in JavaScriptCore against a fake page (the strip, the "⋯" menu's
/// commands, the app panel, the confirmation, the toast), a fake clock and `commands.js` on a fake socket: a control
/// sends its command only when `access.commands` names it (design §8 "Komut etkileşimleri").
struct WebControlsTests {
    static let needsTheCable = "Bu komut sadece kabloyla çalışır"
    static let allNames = #"["quitApp", "media", "volume", "mute", "lock", "displaySleep", "sleep"]"#

    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        context.evaluateScript("""
            var now = 1000, timers = [], sent = [], open = true;
            var performance = { now: function () { return now; } };
            function setTimeout(fn, ms) { timers.push({ at: now + ms, fn: fn }); return timers.length; }
            function clearTimeout() {}
            function advance(ms) {
              now += ms;
              var due = timers.filter(function (t) { return t.at <= now; });
              timers = timers.filter(function (t) { return t.at > now; });
              due.forEach(function (t) { t.fn(); });
            }
            var PBCrypto = { hmacHex: function () { return "signature"; } };
            // Just enough of an element for controls.js: classes, listeners, data attributes and text.
            function element(dataset) {
              var classes = {}, listeners = {};
              return {
                dataset: dataset || {}, textContent: "", hidden: false, style: { setProperty: function () {} },
                classList: {
                  toggle: function (name, on) { if (on) classes[name] = true; else delete classes[name]; },
                  add: function (name) { classes[name] = true; },
                  remove: function (name) { delete classes[name]; },
                  contains: function (name) { return Boolean(classes[name]); }
                },
                setAttribute: function () {}, removeAttribute: function () {},
                addEventListener: function (type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
                fire: function (type, event) {
                  event = event || {};
                  event.target = this;
                  (listeners[type] || []).forEach(function (fn) { fn(event); });
                },
                querySelector: function () { return track; },
                getBoundingClientRect: function () { return { left: 0, width: 100 }; },
                setPointerCapture: function () {}
              };
            }
            var track = element();
            var elements = { "media-previous": element({ media: "previous" }), "media-play": element({ media: "playPause" }),
                             "media-next": element({ media: "next" }) };
            var menuItems = ["lock", "displaySleep", "sleep"].map(function (name) { return element({ command: name }); });
            menuItems.forEach(function (item) { elements["menu-" + item.dataset.command] = item; });
            function $(id) { return elements[id] || (elements[id] = element()); }
            var document = {
              getElementById: $,
              querySelectorAll: function (selector) {
                if (selector === "[data-media]") return [$("media-previous"), $("media-play"), $("media-next")];
                return selector === "#menu [data-command]" ? menuItems : [];
              }
            };
            var PhoneBox = { ui: { menuOpenedAt: -Infinity, menuClosedAt: -Infinity, closeMenu: function () {} } };
            """)
        for name in ["i18n.js", "format.js", "commands.js", "controls.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var link = { key: new Uint8Array(32), nonce: function () { return open ? "6e6f6e6365" : null; },
                         send: function (m) { if (!open) return false; sent.push(m); return true; } };
            // No answer ever times out here: a late "Olmadı" would land in another tap's toast.
            var commands = new PhoneBox.Commands(link, { later: function () {}, now: function () { return now; } });
            var controls = new PhoneBox.Controls(PhoneBox.i18n.texts.tr, PhoneBox.format("tr"), commands);
            controls.setSnapshot({ t: 1, audio: { volume: 0.5, muted: false }, media: { title: "Song", playing: true } });
            var app = { name: "Chess", bundleId: "com.apple.Chess", quittable: true, cpu: 1, mem: 1000 };
            function allow(names) { controls.setAccess({ streaming: true, commands: names, cable: false, reason: "ok" }); }
            // Each control as a finger uses it, confirmations accepted once they have settled.
            var taps = {
              previous: function () { $("media-previous").fire("click"); },
              playPause: function () { $("media-play").fire("click"); },
              next: function () { $("media-next").fire("click"); },
              volume: function () { $("volume").fire("pointerdown", { clientX: 30, pointerId: 1 }); $("volume").fire("pointerup"); },
              mute: function () { $("mute").fire("click"); },
              lock: function () { $("menu-lock").fire("click"); },
              displaySleep: function () { $("menu-displaySleep").fire("click"); },
              sleep: function () { $("menu-sleep").fire("click"); advance(500); $("confirm-ok").fire("click"); },
              quit: function () { controls.openApp(app); advance(500); $("sheet-quit").fire("click"); },
              forceQuit: function () {
                controls.openApp(app); advance(500); $("sheet-force").fire("click"); advance(500); $("confirm-ok").fire("click");
              }
            };
            // One tap, after the previous one has settled: what went out ("-" for nothing) and the toast, if any.
            function tap(name) {
              advance(500);
              var before = sent.length;
              $("toast-text").textContent = "";
              taps[name]();
              var out = sent.slice(before).map(function (m) { return m.name; }).join("+") || "-";
              var toast = $("toast-text").textContent;
              return name + ":" + out + (toast ? " (" + toast + ")" : "");
            }
            function tapAll() { return Object.keys(taps).map(tap).join(", "); }
            // The controls that look dim.
            function dim() {
              return ["media-previous", "media-play", "media-next", "volume", "mute", "menu-lock", "menu-displaySleep",
                      "menu-sleep", "sheet-quit", "sheet-force"].filter(function (id) { return $(id).classList.contains("off"); }).join(",");
            }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func overWiFiWithLockAndMusicOnlyTheMediaButtonsAndLockSend() {
        let refused = "- (\(Self.needsTheCable))"
        #expect(string(#"allow(["media", "lock"]); dim()"#) == "volume,mute,menu-displaySleep,menu-sleep,sheet-quit,sheet-force")
        #expect(string("tapAll()") == "previous:media, playPause:media, next:media, volume:\(refused), mute:\(refused), lock:lock, "
            + "displaySleep:\(refused), sleep:\(refused), quit:\(refused), forceQuit:\(refused)")
    }

    @Test func onTheCableEveryControlSends() {
        #expect(string("allow(\(Self.allNames)); dim()") == "")
        #expect(string("tapAll()") == "previous:media, playPause:media, next:media, volume:volume, mute:mute, lock:lock, "
            + "displaySleep:displaySleep, sleep:sleep, quit:quitApp, forceQuit:quitApp")
    }

    @Test func withNoCommandsNothingSends() {
        let refused = "- (\(Self.needsTheCable))"
        #expect(string("allow([]); dim()")
            == "media-previous,media-play,media-next,volume,mute,menu-lock,menu-displaySleep,menu-sleep,sheet-quit,sheet-force")
        #expect(string("tapAll()") == "previous:\(refused), playPause:\(refused), next:\(refused), volume:\(refused), "
            + "mute:\(refused), lock:\(refused), displaySleep:\(refused), sleep:\(refused), quit:\(refused), forceQuit:\(refused)")
    }

    /// Allowed, but the socket is not authenticated (reconnecting): dim, and a tap says it did not work.
    @Test func aSocketThatCannotSendDimsEveryControl() {
        #expect(string("open = false; allow(\(Self.allNames)); dim()")
            == "media-previous,media-play,media-next,volume,mute,menu-lock,menu-displaySleep,menu-sleep,sheet-quit,sheet-force")
        #expect(string(#"tap("previous") + ", " + tap("lock")"#) == "previous:- (Olmadı), lock:- (Olmadı)")
    }

    @Test func aNotAllowedAnswerShowsTheSameToast() {
        #expect(string(#"""
            allow(["media", "lock"]);
            tap("lock");
            commands.acked({ seq: sent[sent.length - 1].seq, ok: false, error: "not-allowed" });
            $("toast-text").textContent
            """#) == Self.needsTheCable)
        #expect(string("PhoneBox.i18n.texts.en.errorNotAllowed") == "This command needs the cable")
    }
}
