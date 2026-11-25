import Foundation
import PhoneBoxCore

/// Runs the phone's commands on the Mac (design §7). The commands themselves arrive in a later task; until then
/// every signed, allowed command is answered `unsupported` and nothing runs.
@MainActor
final class CommandRunner: CommandRunning {
    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
        completion(.failed(.unsupported))
    }
}
