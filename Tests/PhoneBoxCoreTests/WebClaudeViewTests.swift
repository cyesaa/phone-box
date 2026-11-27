import Foundation
import JavaScriptCore
import Testing

/// Runs the Claude Code page's `Resources/web/claudeview.js` in JavaScriptCore against a fake card list: in portrait,
/// when even compact cards do not fit, only the cards that fit completely stay (design §14).
struct WebClaudeViewTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        context.evaluateScript("""
            function classes() {
              var names = {};
              return {
                toggle: function (name, on) { if (on === undefined) on = !names[name]; if (on) names[name] = true; else delete names[name]; },
                add: function (name) { names[name] = true; },
                remove: function (name) { delete names[name]; },
                contains: function (name) { return Boolean(names[name]); }
              };
            }
            function element() {
              return { hidden: false, textContent: "", style: { setProperty: function () {} }, classList: classes(),
                       children: [], addEventListener: function () {}, toggleAttribute: function () {} };
            }
            // A card laid out `top` px below the list's top, `height` px tall; `shift` is how far a running animation
            // (its `transform`) moves it on screen, which layout does not see.
            function card(index, top, height) {
              var c = element();
              c.style.order = String(index);
              c.offsetTop = top;
              c.offsetHeight = height;
              c.shift = 0;
              c.getBoundingClientRect = function () {
                return { top: listTop + top + c.shift, bottom: listTop + top + height + c.shift };
              };
              return c;
            }
            // The list's height: less once the "+N" line under it takes its place.
            var listTop = 120, cards = [], room = 656, roomWithLine = 633;
            var list = element();
            var elements = { "claude-list": list };
            Object.defineProperty(list, "clientHeight", { get: function () { return $("claude-more").hidden ? room : roomWithLine; } });
            list.querySelectorAll = function () { return cards; };
            list.getBoundingClientRect = function () { return { top: listTop, bottom: listTop + list.clientHeight }; };
            // As in the browser: the list's own height, or how far its cards reach, transforms counted.
            Object.defineProperty(list, "scrollHeight", { get: function () {
              return cards.filter(function (c) { return !c.classList.contains("cut"); })
                .reduce(function (most, c) { return Math.max(most, c.offsetTop + c.offsetHeight + c.shift); }, list.clientHeight);
            } });
            function $(id) { return elements[id] || (elements[id] = element()); }
            var document = { getElementById: $, addEventListener: function () {} };
            function addEventListener() {}
            function matchMedia(query) { return { matches: query.indexOf("portrait") >= 0 }; }
            """)
        for name in ["i18n.js", "clock.js", "claude.js", "motion.js", "claudeview.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var view = new PhoneBox.ClaudeView(PhoneBox.i18n.texts.tr, new PhoneBox.claude.Pager(), { text: "" });
            view.enabled = true;
            // Eleven compact cards, 56 px tall with 6 px between them, in a list 656 px high (633 px over the "+N" line):
            // ten fit, the tenth ending at 614 px.
            for (var i = 0; i < 11; i += 1) {
              cards.push(card(i, i * 62, 56));
              view.cards.set("s" + i, { element: cards[i] });
            }
            function shown() {
              var more = $("claude-more");
              return cards.filter(function (c) { return !c.classList.contains("cut"); }).length + (more.hidden ? "" : " " + more.textContent);
            }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func keepsTheCardsThatFit() {
        #expect(string("view.fit(); shown()") == "10 +1 oturum daha")
    }

    /// The tenth card has only just come in: its entry animation still holds it 24 px lower. It is measured where it
    /// will rest, so it stays.
    @Test func aCardThatIsStillComingInIsMeasuredWhereItWillRest() {
        #expect(string("cards[9].shift = 24; view.fit(); shown()") == "10 +1 oturum daha")
    }

    /// While the page slides in, every card comes in from 24 px below, one after another.
    @Test func cardsArrivingWithThePageAreMeasuredWhereTheyWillRest() {
        #expect(string("cards.forEach(function (c) { c.shift = 24; }); view.fit(); shown()") == "10 +1 oturum daha")
    }

    /// Ten cards that all fit, the last one ending 16 px above the bottom, and it is still coming in: on screen it
    /// reaches past the bottom, where it rests it does not. Neither compact cards nor the "+N" line.
    @Test func allTheCardsFitWhileTheLastIsStillComingIn() {
        #expect(string("""
            cards.pop(); view.cards.delete("s10");
            room = 630; roomWithLine = 607;
            cards[9].shift = 24;
            view.fit();
            shown() + " " + list.classList.contains("compact")
            """) == "10 false")
    }
}
