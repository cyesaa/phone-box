import Foundation
import JavaScriptCore
import Testing

/// Runs the Claude Code page's `Resources/web/claude.js` in JavaScriptCore (design §14): when the page comes by itself
/// and when it goes back (`Pager`), how long a state has lasted, the words for each state, how many columns the cards
/// take and which way a swipe goes.
struct WebClaudeTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        for name in ["i18n.js", "claude.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var C = PhoneBox.claude, TR = PhoneBox.i18n.texts.tr, EN = PhoneBox.i18n.texts.en;
            function waiting(id, since) { return { id: id, title: id, project: "p", state: "waiting", reason: "turn", since: since }; }
            function working(id, since) { return { id: id, title: id, project: "p", state: "working", activity: "think", since: since }; }
            // One snapshot's sessions a second from `start` (ms): what the pager said to each, "-" for nothing.
            function run(pager, steps, start) {
              return steps.map(function (sessions, index) { return pager.update(sessions, (start || 0) + index * 1000) || "-"; }).join(" ");
            }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    // ---- Pager

    @Test func opensWhenASessionStartsWaiting() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), out = [pager.onClaude];
              out.push(run(pager, [[], [working("a", 0)], [waiting("a", 2000)], [waiting("a", 2000)]]), pager.onClaude);
              return out.join(" | ");
            })()
            """) == "false | - - open - | true")
    }

    /// A reload or "Start" makes a new page: what already waits counts as new.
    @Test func sessionsThatAlreadyWaitWhenThePageLoadsAreNew() {
        #expect(string(#"run(new C.Pager(), [[working("b", 0), waiting("a", 5)]])"#) == "open")
    }

    @Test func goesBackThreeSecondsAfterTheLastWaitEnded() {
        #expect(string("""
            (function () {
              var pager = new C.Pager();
              var out = [pager.update([waiting("a", 0)], 0), pager.update([working("a", 1000)], 1000),
                         pager.update([working("a", 1000)], 3999), pager.update([working("a", 1000)], 4000), pager.onClaude];
              return out.join(",");
            })()
            """) == "open,,,close,false")
    }

    @Test func aNewWaitOnTheClaudePageStartsTheThreeSecondsOver() {
        #expect(string("""
            (function () {
              var pager = new C.Pager();
              var out = [pager.update([waiting("a", 0)], 0), pager.update([], 1000), pager.update([waiting("b", 2500)], 2500),
                         pager.update([], 3000), pager.update([], 5999), pager.update([], 6000)];
              return out.join(",");
            })()
            """) == "open,,,,,close")
    }

    @Test func doesNotReopenAfterTheUserWentBackWhileTheSameSessionsWait() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), both = [waiting("a", 0), waiting("b", 0)];
              var out = [pager.update(both, 0)];
              pager.userShowed("dashboard");
              out.push(pager.onClaude, run(pager, [both, both, [waiting("b", 0)], [working("a", 4000), waiting("b", 0)]], 1000));
              return out.join(",");
            })()
            """) == "open,false,- - - -")
    }

    @Test func reopensWhenOneOfThemStartsWaitingAgain() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), out = [pager.update([waiting("a", 0), waiting("b", 0)], 0)];
              pager.userShowed("dashboard");
              // "a" waits again with a new start, straight away: the user has not seen this wait.
              out.push(run(pager, [[waiting("a", 0), waiting("b", 0)], [waiting("a", 2000), waiting("b", 0)]], 1000));
              pager.userShowed("dashboard");
              // "b" worked for a while, then waits again.
              out.push(run(pager, [[waiting("a", 2000), working("b", 4000)], [waiting("a", 2000), waiting("b", 6000)]], 4000));
              return out.join(",");
            })()
            """) == "open,- open,- open")
    }

    @Test func aWaitThatBeganOnTheClaudePageCountsAsSeen() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), out = [pager.update([waiting("a", 0)], 0), pager.update([waiting("a", 0), waiting("b", 1000)], 1000)];
              pager.userShowed("dashboard");
              out.push(run(pager, [[waiting("a", 0), waiting("b", 1000)], [waiting("b", 1000)]], 2000));
              return out.join(",");
            })()
            """) == "open,,- -")
    }

    /// Only the waits of the current sessions are remembered: a key that went away is new if it ever comes back.
    @Test func forgetsWaitsThatEnded() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), out = [pager.update([waiting("a", 0)], 0)];
              pager.userShowed("dashboard");
              out.push(run(pager, [[], [waiting("a", 0)]], 1000));
              return out.join(",");
            })()
            """) == "open,- open")
    }

    @Test func aPageTheUserOpenedNeverGoesBackByItself() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), out = [];
              pager.userShowed("claude");
              out.push(pager.onClaude, run(pager, [[], [waiting("a", 1000)], [], [], [], [], []]), pager.onClaude);
              // Came by itself, the user went back, then swiped to it again: it stays too.
              var again = new C.Pager();
              out.push(again.update([waiting("a", 0)], 0));
              again.userShowed("dashboard");
              again.userShowed("claude");
              out.push(run(again, [[], [], [], [], [], []], 1000), again.onClaude);
              return out.join(",");
            })()
            """) == "true,- - - - - - -,true,open,- - - - - -,true")
    }

    @Test func turningTheFeatureOffGoesBack() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), out = [pager.update([waiting("a", 0)], 0), pager.update(null, 1000), pager.onClaude,
                                                pager.update(undefined, 2000)];
              var manual = new C.Pager();
              manual.userShowed("claude");
              out.push(manual.update(undefined, 0), manual.onClaude);
              return out.join(",");
            })()
            """) == "open,close,false,,close,false")
    }

    /// A snapshot without sessions says nothing about them (the feature was off for a moment, or a snapshot could not
    /// be encoded): the waits the user has seen stay seen.
    @Test func aSnapshotWithoutSessionsKeepsTheSeenWaits() {
        #expect(string("""
            (function () {
              var pager = new C.Pager(), out = [pager.update([waiting("a", 0)], 0)];
              pager.userShowed("dashboard");
              out.push(run(pager, [null, [waiting("a", 0)]], 1000));
              return out.join(",");
            })()
            """) == "open,- -")
    }

    // ---- Texts and layout

    @Test func writesHowLongAStateHasLasted() {
        #expect(string("[0, 42000, 599999, 600000, 3599999, 3600000, 7200000, -5000].map(function (ms) { return C.elapsed(TR, ms); }).join(',')")
            == "0:00,0:42,9:59,10 dk,59 dk,1 sa,2 sa,0:00")
        #expect(string("[61000, 720000, 9000000].map(function (ms) { return C.elapsed(EN, ms); }).join(',')") == "1:01,12 min,2 h")
    }

    @Test func namesEachStateInBothLanguages() {
        let states = """
            [{ state: "waiting", reason: "question" }, { state: "waiting", reason: "permission" }, { state: "waiting", reason: "turn" },
             { state: "working", activity: "think" }, { state: "working", activity: "command" }, { state: "working", activity: "edit" },
             { state: "working", activity: "read" }, { state: "working", activity: "web" }, { state: "working", activity: "agent" },
             { state: "working", activity: "tool" }, { state: "working", activity: "background" }, { state: "ready" }]
            """
        #expect(string("\(states).map(function (s) { return C.stateText(TR, s); }).join(' | ')")
            == "Soru soruyor | İzin istiyor | Sıra sende | Düşünüyor | Komut çalıştırıyor | Dosya düzenliyor | Dosya okuyor | "
            + "Web'e bakıyor | Alt görev çalıştırıyor | Araç kullanıyor | Arka planda çalışıyor | Hazır")
        #expect(string("\(states).map(function (s) { return C.stateText(EN, s); }).join(' | ')")
            == "Asking you | Needs permission | Your turn | Thinking | Running a command | Editing files | Reading files | "
            + "Searching the web | Running a subtask | Using a tool | Working in the background | Ready")
    }

    /// A newer Mac may send a reason or an activity this page does not know: it still says something true.
    @Test func fallsBackForAnUnknownReasonOrActivity() {
        #expect(string(#"[C.stateText(TR, { state: "waiting", reason: "x" }), C.stateText(TR, { state: "working" }), C.stateText(TR, { state: "x" })].join(" | ")"#)
            == "Sıra sende | Düşünüyor | Hazır")
    }

    @Test func writesTheHeaderCounts() {
        #expect(string("[TR.claudeSessions(3), TR.claudeWaiting(2), EN.claudeSessions(1), EN.claudeSessions(4), EN.claudeWaiting(1)].join(' | ')")
            == "3 oturum | · 2 seni bekliyor | 1 session | 4 sessions | · 1 waiting for you")
        #expect(string("[TR.claudeEmpty, EN.claudeEmpty].join(' | ')") == "Açık Claude oturumu yok | No open Claude Code sessions")
    }

    @Test func saysHowManySessionsDoNotFit() {
        #expect(string("[TR.claudeMore(3), EN.claudeMore(1), EN.claudeMore(4)].join(' | ')")
            == "+3 oturum daha | +1 more session | +4 more sessions")
    }

    @Test func laysTheCardsOutInColumns() {
        #expect(string("[0, 1, 2, 4, 5, 12].map(function (n) { return C.columns(n, true); }).join(',')") == "2,2,2,2,3,3")
        #expect(string("[0, 1, 5, 12].map(function (n) { return C.columns(n, false); }).join(',')") == "1,1,1,1")
    }

    /// In landscape the cards fill the page's height: one session is one tall card in the left column, two are two
    /// tall cards side by side (like the approved prototype).
    @Test func laysTheCardsOutInAsManyRowsAsTheyFill() {
        #expect(string("[0, 1, 2, 3, 4, 5, 6, 7, 12].map(function (n) { var g = C.grid(n, true); return g.columns + 'x' + g.rows; }).join(',')")
            == "2x1,2x1,2x1,2x2,2x2,3x2,3x2,3x3,3x4")
        #expect(string("[1, 3, 12].map(function (n) { var g = C.grid(n, false); return g.columns + 'x' + g.rows; }).join(',')")
            == "1x1,1x3,1x12")
    }

    @Test func aSwipeGoesUpOrDownWhenItIsLongAndMostlyVertical() {
        #expect(string("JSON.stringify([C.swipe(0, -41), C.swipe(5, 41), C.swipe(0, 40), C.swipe(0, -40), C.swipe(-45, -45), C.swipe(50, -45), C.swipe(-30, -45)])")
            == #"["claude","dashboard",null,null,null,null,"claude"]"#)
    }

    @Test func theDashboardLoadsTheClaudeScriptsInOrder() throws {
        let html = try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent("index.html"), encoding: .utf8)
        let scripts = html.components(separatedBy: "<script src=\"").dropFirst().compactMap { $0.components(separatedBy: "\"").first }
        func place(_ name: String) -> Int { scripts.firstIndex(of: name) ?? -1 }
        #expect(place("claude.js") > place("format.js") && place("format.js") >= 0)
        #expect(place("claudeview.js") > place("view.js") && place("view.js") >= 0)
        #expect(place("claudeview.js") < place("app.js"))
    }
}
