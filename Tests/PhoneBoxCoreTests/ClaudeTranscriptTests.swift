import Foundation
import Testing
@testable import PhoneBoxCore

/// The title and the model from the end of a session file (design §14). The format is not documented, so these
/// samples follow what Claude Code and the desktop app wrote on 2026-11-26.
struct ClaudeTranscriptTests {
    static func details(_ lines: [String], startsAtBeginning: Bool = true) -> (title: String?, model: String?) {
        ClaudeTranscript.details(fromTail: Data(lines.joined(separator: "\n").utf8), startsAtBeginning: startsAtBeginning)
    }

    static let user = #"{"type":"user","message":{"role":"user","content":"hi"},"sessionId":"s"}"#
    static func title(_ text: String) -> String { #"{"type":"custom-title","customTitle":"\#(text)","sessionId":"s"}"# }
    static func assistant(_ model: String) -> String {
        #"{"type":"assistant","message":{"model":"\#(model)","role":"assistant","content":[{"type":"text","text":"ok"}]},"sessionId":"s"}"#
    }

    @Test func readsTheTitleAndTheModel() {
        let result = Self.details([Self.user, Self.title("Mac-telefon dashboard bağlantısı"), Self.assistant("claude-opus-5-5"), ""])
        #expect(result.title == "Mac-telefon dashboard bağlantısı")
        #expect(result.model == "Opus 5.5")
    }

    @Test func theLastTitleAndTheLastModelWin() {
        let result = Self.details([Self.title("First"), Self.assistant("claude-sonnet-4-5-20250929"), Self.title("Second"),
                                   Self.assistant("claude-opus-5-5"), Self.user])
        #expect(result.title == "Second")
        #expect(result.model == "Opus 5.5")
    }

    @Test func nothingFoundIsNil() {
        let result = Self.details([Self.user, Self.user])
        #expect(result.title == nil)
        #expect(result.model == nil)
        let empty = ClaudeTranscript.details(fromTail: Data(), startsAtBeginning: true)
        #expect(empty.title == nil)
        #expect(empty.model == nil)
    }

    @Test func skipsTheCutFirstLineOfATail() {
        // The tail starts in the middle of a title line: its end must not count.
        let cut = String(Self.title("Cut title").dropFirst(5))
        #expect(Self.details([Self.title("Whole"), Self.user]).title == "Whole")
        #expect(Self.details([cut, Self.user], startsAtBeginning: false).title == nil)
        #expect(Self.details([Self.title("Kept"), Self.user], startsAtBeginning: false).title == nil)
        #expect(Self.details([Self.user, Self.title("Kept")], startsAtBeginning: false).title == "Kept")
        #expect(Self.details([Self.title("First line"), Self.user], startsAtBeginning: true).title == "First line")
    }

    @Test func toleratesBrokenLinesAndOtherShapes() {
        let result = Self.details([Self.title("Good"), #"{"type":"custom-title","customTitle":"#, #"{"type":"custom-title"}"#,
                                   #"{"type":"custom-title","customTitle":42}"#, #"{"type":"assistant","message":"model"}"#,
                                   #"["model"]"#, Self.assistant("claude-haiku-5-5")])
        #expect(result.title == "Good")
        #expect(result.model == "Haiku 5.5")
    }

    @Test func aBlankTitleDoesNotCountAndALongOneIsCut() {
        #expect(Self.details([Self.title("Real"), Self.title("   ")]).title == "Real")
        #expect(Self.details([Self.title("  Padded  ")]).title == "Padded")
        let long = String(repeating: "ş", count: 150)
        #expect(Self.details([Self.title(long)]).title == String(repeating: "ş", count: 120))
    }

    @Test func aMessageWithoutAKnownModelKeepsTheEarlierOne() {
        // Claude Code writes "<synthetic>" for messages it makes up itself, such as an interruption.
        let result = Self.details([Self.assistant("claude-opus-5-5"), Self.assistant("<synthetic>")])
        #expect(result.model == "Opus 5.5")
    }

    @Test func namesModels() {
        #expect(ClaudeTranscript.modelName("claude-opus-5-5") == "Opus 5.5")
        #expect(ClaudeTranscript.modelName("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
        #expect(ClaudeTranscript.modelName("claude-fable-5-2") == "Fable 5.2")
        #expect(ClaudeTranscript.modelName("claude-haiku-5-5[1m]") == "Haiku 5.5")
        #expect(ClaudeTranscript.modelName("claude-opus-4") == "Opus 4")
        #expect(ClaudeTranscript.modelName("claude-opus-4-20250514") == "Opus 4")
        #expect(ClaudeTranscript.modelName("claude-opus-4-1-20250805") == "Opus 4.1")
    }

    @Test func otherModelIdsHaveNoName() {
        for id in ["claude-3-5-sonnet-20241022", "gpt-4", "", "claude-", "claude-opus", "claude-opus-x", "claude-opus-4-5-6",
                   "claude-opus-4-5-2025", "<synthetic>", "opus", "claude-opus-4-5-20250929-v2", "claude-op_us-4"] {
            #expect(ClaudeTranscript.modelName(id) == nil, "\(id)")
        }
    }
}
