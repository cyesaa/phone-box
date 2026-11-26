import Darwin
import Foundation
import PhoneBoxCore

/// PhoneBox's hooks in `~/.claude/settings.json` (design §14 "Kurulum"); `ClaudeHooks` decides what the file says.
/// A symlink (a dotfiles folder) is followed and stays a symlink; before the file changes, the old one is kept as
/// `settings.json.phonebox-backup` next to it; the new one is written atomically with the old one's permissions.
struct ClaudeHooksFile {
    enum Failure: Error {
        /// The file says something PhoneBox does not understand; it was left as it was.
        case hooks(ClaudeHooks.Failure)
        case file(Error)
    }

    static let backupSuffix = ".phonebox-backup"
    let settingsURL: URL

    init(settingsURL: URL = ClaudePaths.settings) {
        self.settingsURL = settingsURL
    }

    /// Adds PhoneBox's hooks for `executable`, replacing any earlier ones; creates the folder and the file if needed.
    func install(executable: String) throws {
        let url = realURL()
        let existing = try read(url)
        let updated = try translatingFailure { try ClaudeHooks.install(into: existing, command: ClaudeHooks.command(executable: executable)) }
        try write(updated, to: url, replacing: existing)
    }

    /// Removes PhoneBox's hooks; false when there were none (or no file), and then the file is not touched.
    @discardableResult
    func remove() throws -> Bool {
        let url = realURL()
        guard let existing = try read(url), !ClaudeHooks.installedCommands(in: existing).isEmpty else { return false }
        let updated = try translatingFailure { try ClaudeHooks.remove(from: existing) }
        try write(updated, to: url, replacing: existing)
        return true
    }

    /// The commands of PhoneBox's hooks in the file; none when it is missing or unreadable.
    func installedCommands() -> [String] {
        guard let data = try? read(realURL()) else { return [] }
        return ClaudeHooks.installedCommands(in: data)
    }

    /// The settings file itself, following symlinks to it (relative ones from the link's folder).
    func realURL() -> URL {
        var url = settingsURL
        for _ in 0..<32 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { break }
            url = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).absoluteURL.standardizedFileURL
        }
        return url
    }

    private func translatingFailure(_ change: () throws -> Data) throws -> Data {
        do {
            return try change()
        } catch let failure as ClaudeHooks.Failure {
            throw Failure.hooks(failure)
        } catch {
            throw Failure.file(error)
        }
    }

    /// Nil when there is no such file.
    private func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw Failure.file(error)
        }
    }

    private func write(_ data: Data, to url: URL, replacing existing: Data?) throws {
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A new file may come to hold API keys (`env`): only this user reads it.
            var mode: mode_t = 0o600
            if let existing {
                if let permissions = try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber {
                    mode = mode_t(permissions.uint16Value & 0o7777)
                }
                try Self.writeAtomically(existing, to: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + Self.backupSuffix), mode: mode)
            }
            try Self.writeAtomically(data, to: url, mode: mode)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.file(error)
        }
    }

    /// Writes a temporary file next to `url` with `mode` from the start, then renames it over `url`: a reader sees the
    /// old file or the new one, never part of one, and never with wider permissions.
    private static func writeAtomically(_ data: Data, to url: URL, mode: mode_t) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // open() applies the umask; fchmod() does not.
        var written = fchmod(descriptor, mode) == 0
        written = written && data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base + offset, bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += count
            }
            return true
        }
        written = written && fsync(descriptor) == 0
        var code = errno
        close(descriptor)
        if written, rename(temporary.path, url.path) == 0 { return }
        if written { code = errno }
        unlink(temporary.path)
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
