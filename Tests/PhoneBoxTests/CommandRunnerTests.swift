import Testing
@testable import PhoneBox
import PhoneBoxCore

@MainActor
struct CommandRunnerTests {
    @Test func tellsAMissingAudioControlFromARefusedValue() {
        #expect(CommandRunner.result(of: .done) == .ok)
        #expect(CommandRunner.result(of: .unsupported) == .failed(.unsupported))
        #expect(CommandRunner.result(of: .failed) == .failed(.failed))
    }
}
