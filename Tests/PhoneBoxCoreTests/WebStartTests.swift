import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's `Resources/web/app.js` in JavaScriptCore with stand-ins for the other scripts: a page that is
/// missing one of them (it did not load) or whose start throws shows the offline card and loads itself again once the
/// Mac answers, waiting longer each time (design §8 "Sayfa kodu").
struct WebStartTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        // A Turkish phone: i18n.js picks the page's language when it loads.
        context.evaluateScript("var navigator = { language: \"tr-TR\" };")
        context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent("i18n.js"), encoding: .utf8))
        context.setObject(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent("app.js"), encoding: .utf8),
                          forKeyedSubscript: "appSource" as NSString)
        context.evaluateScript("""
            var I18N = PhoneBox.i18n;
            var now = 0, timers = [], reloads = 0, asked = [], answer = "ok", store = {}, errors = [];
            function setTimeout(fn, ms) { timers.push({ at: now + ms, fn: fn }); return timers.length; }
            function advance(ms) {
              var end = now + ms;
              while (now < end) {
                now += 100;
                var due = timers.filter(function (t) { return t.at <= now; });
                timers = timers.filter(function (t) { return t.at > now; });
                due.forEach(function (t) { t.fn(); });
              }
            }
            var sessionStorage = { getItem: function (k) { return k in store ? store[k] : null; },
                                   setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } };
            var localStorage = { getItem: function () { return null; }, setItem: function () {} };
            var location = { host: "mac.local:4747", hash: "", reload: function () { reloads += 1; } };
            // The Mac: answers ("ok"), answers with an error ("busy") or cannot be reached ("down").
            function fetch(url, options) {
              asked.push(url + " " + options.cache);
              if (answer === "down") return Promise.reject(new TypeError("Load failed"));
              return Promise.resolve({ ok: answer === "ok" });
            }
            console.error = function (error) { errors.push(String(error)); };
            function element() { return { hidden: true, textContent: "", className: "", addEventListener: function () {} }; }
            var elements = {};
            function $(id) { return elements[id] || (elements[id] = element()); }
            var document = { getElementById: $, querySelector: function () { return null; },
                             querySelectorAll: function () { return []; }, documentElement: {} };
            function addEventListener() {}
            var window = this;
            // A part of the page that takes any call and gives back another (the real ones need a browser).
            function stand() {
              return new Proxy(function () {}, {
                get: function (target, key) {
                  if (key === Symbol.iterator) return function () { return [][Symbol.iterator](); };
                  return key === "then" ? undefined : stand();
                },
                apply: function () { return stand(); },
                construct: function () { return stand(); }
              });
            }
            var parts = ["fullScreenHeight", "format", "claude", "History", "metrics", "heat", "motion", "rings", "clock",
                         "chart", "readKey", "Connection", "BuildWatch", "Commands", "Throttle", "View", "ClaudeView", "ui",
                         "Controls"];
            // A fresh page whose scripts all loaded but `missing` (a part name, "i18n" or "PBCrypto").
            function page(missing) {
              PhoneBox = { i18n: I18N };
              parts.forEach(function (part) { PhoneBox[part] = stand(); });
              PBCrypto = stand();
              if (missing === "PBCrypto") delete window.PBCrypto;
              else if (missing) delete PhoneBox[missing];
              elements = {};
              timers = [];
            }
            function load() { (0, eval)(appSource); }
            function card() { return [$("state").hidden, $("state-title").textContent, $("status-text").textContent].join(" | "); }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    /// Evaluated on its own, so that the promises it settles have run before the next call reads the result.
    func run(_ code: String) { context.evaluateScript(code) }

    @Test func aPageMissingAScriptShowsTheOfflineCardAndReloadsOnceTheMacAnswers() {
        run(#"page("View"); load();"#)
        #expect(string("card()") == "false | Mac'e ulaşılamıyor | Mac'e ulaşılamıyor")
        #expect(string("$('state-text').textContent === I18N.texts.tr.stateOfflineText") == "true")
        run("advance(4900);")
        #expect(string("[asked.length, reloads].join(' ')") == "0 0")
        run("advance(100);")
        #expect(string(#"[asked.join(","), reloads, store["phonebox-reloads"]].join(" ")"#) == "/ no-store 1 1")
    }

    @Test func everyScriptCounts() {
        let result = string("""
            ["PBCrypto", "i18n"].concat(parts.filter(function (part) { return part !== "readKey" && part !== "BuildWatch" && part !== "Throttle"; }))
              .filter(function (missing) { page(missing); load(); return $("state").hidden || timers.length !== 1; }).join(",")
            """)
        #expect(result == "")
    }

    /// A page that keeps failing: 5 s, 15 s, 30 s, then once a minute, never faster.
    @Test func waitsLongerEachTimeItReloads() {
        #expect(string("""
            [0, 1, 2, 3, 4, 9].map(function (count) {
              store["phonebox-reloads"] = String(count);
              page("Connection");
              load();
              return timers[0].at - now;
            }).join(",")
            """) == "5000,15000,30000,60000,60000,60000")
    }

    /// Reloading while the Mac cannot be reached would end on the browser's error page, which never tries again.
    @Test func waitsForTheMacBeforeReloading() {
        run(#"answer = "down"; page("chart"); load(); advance(5000);"#)
        #expect(string("[asked.length, reloads].join(' ')") == "1 0")
        run(#"answer = "busy"; advance(5000);"#)
        #expect(string("[asked.length, reloads].join(' ')") == "2 0")
        run(#"answer = "ok"; advance(5000);"#)
        #expect(string(#"[asked.length, reloads, store["phonebox-reloads"]].join(" ")"#) == "3 1 1")
    }

    /// A start that throws is the same: the card (nothing over it), and a reload.
    @Test func aStartThatThrowsAlsoRecovers() {
        run(#"""
            page();
            PhoneBox.Connection = function () { throw new Error("broken"); };
            $("start").hidden = false;
            load();
            """#)
        #expect(string("[card(), $('start').hidden, $('guide').hidden, errors.join()].join(' / ')")
            == "false | Mac'e ulaşılamıyor | Mac'e ulaşılamıyor / true / true / Error: broken")
        run("advance(5000);")
        #expect(string("reloads") == "1")
    }

    /// i18n.js may be the script that did not load: the card is still in the page's language.
    @Test func withoutTheTextsTheCardIsStillInThePagesLanguage() {
        #expect(string(#"""
            ["tr-TR", "en-GB"].map(function (language) {
              navigator.language = language;
              page("i18n");
              load();
              var texts = I18N.texts[language.slice(0, 2)];
              return [$("state-title").textContent === texts.stateOffline, $("state-text").textContent === texts.stateOfflineText].join("/");
            }).join(" ")
            """#) == "true/true true/true")
    }

    @Test func aPageThatStartsForgetsItsReloads() {
        run(#"store["phonebox-reloads"] = "3"; page(); load();"#)
        #expect(string(#"[$("state").hidden, timers.length, "phonebox-reloads" in store].join(" ")"#) == "true 0 false")
    }
}
