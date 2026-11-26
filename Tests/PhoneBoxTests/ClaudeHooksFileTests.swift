import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// PhoneBox's hooks in a settings file (design §14 "Kurulum"). Every test works in its own temporary folder, never in
/// the real `~/.claude`.
struct ClaudeHooksFileTests {
    static let executable = "/Applications/PhoneBox.app/Contents/MacOS/PhoneBox"
    static let command = ClaudeHooks.command(executable: executable)
    static let userFile = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pbc-\(UUID().uuidString)", isDirectory: true)
    var claudeFolder: URL { folder.appendingPathComponent(".claude", isDirectory: true) }
    var settings: URL { claudeFolder.appendingPathComponent("settings.json") }
    var backup: URL { claudeFolder.appendingPathComponent("settings.json.phonebox-backup") }
    var file: ClaudeHooksFile { ClaudeHooksFile(settingsURL: settings) }

    func cleanUp() { try? FileManager.default.removeItem(at: folder) }

    func write(_ text: String, to url: URL, mode: Int = 0o600) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    func mode(_ url: URL) throws -> Int {
        try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    static func object(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func installCreatesTheFolderAndTheFile() throws {
        defer { cleanUp() }
        #expect(file.installedCommands() == [])
        try file.install(executable: Self.executable)
        #expect(file.installedCommands() == Array(repeating: Self.command, count: ClaudeHooks.events.count))
        // There was nothing to keep a copy of.
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(try mode(settings) == 0o600)
    }

    @Test func installKeepsACopyOfTheFileItChanges() throws {
        defer { cleanUp() }
        try write(Self.userFile, to: settings, mode: 0o640)
        try file.install(executable: Self.executable)
        #expect(FileManager.default.contents(atPath: backup.path) == Data(Self.userFile.utf8))
        #expect(try mode(settings) == 0o640)
        #expect(try mode(backup) == 0o640)
        let installed = try Self.object(FileManager.default.contents(atPath: settings.path))
        #expect(installed["model"] as? String == "opus")
        #expect(Set(file.installedCommands()) == [Self.command])
        // No temporary file is left next to it.
        let names = try FileManager.default.contentsOfDirectory(atPath: claudeFolder.path).sorted()
        #expect(names == ["settings.json", "settings.json.phonebox-backup"])
    }

    @Test func writesThroughASymlinkAndKeepsIt() throws {
        defer { cleanUp() }
        let dotfiles = folder.appendingPathComponent("dotfiles", isDirectory: true)
        let real = dotfiles.appendingPathComponent("settings.json")
        try write(Self.userFile, to: real)
        try FileManager.default.createDirectory(at: claudeFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: settings.path, withDestinationPath: "../dotfiles/settings.json")
        try file.install(executable: Self.executable)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path) == "../dotfiles/settings.json")
        #expect(ClaudeHooks.installedCommands(in: try #require(FileManager.default.contents(atPath: real.path))).count
            == ClaudeHooks.events.count)
        #expect(FileManager.default.contents(atPath: dotfiles.appendingPathComponent("settings.json.phonebox-backup").path)
            == Data(Self.userFile.utf8))
        #expect(try file.remove())
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path) == "../dotfiles/settings.json")
        #expect(try Self.object(FileManager.default.contents(atPath: real.path)) == Self.object(Data(Self.userFile.utf8)))
    }

    /// `~/.claude` itself can be a link into a dotfiles folder, and `settings.json` a relative link from there: `..`
    /// climbs out of the folder the link really is in.
    @Test func followsARelativeLinkInsideALinkedFolder() throws {
        defer { cleanUp() }
        let dotfiles = folder.appendingPathComponent("dotfiles", isDirectory: true)
        let shared = dotfiles.appendingPathComponent("shared/settings.json")
        try write(Self.userFile, to: shared)
        try FileManager.default.createDirectory(at: dotfiles.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: claudeFolder.path, withDestinationPath: "dotfiles/claude")
        try FileManager.default.createSymbolicLink(atPath: settings.path, withDestinationPath: "../shared/settings.json")
        try file.install(executable: Self.executable)
        #expect(ClaudeHooks.installedCommands(in: try #require(FileManager.default.contents(atPath: shared.path))).count
            == ClaudeHooks.events.count)
        #expect(FileManager.default.contents(atPath: shared.path + ClaudeHooksFile.backupSuffix) == Data(Self.userFile.utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: claudeFolder.path) == "dotfiles/claude")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path) == "../shared/settings.json")
        // Nothing where the links' text alone would lead.
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("shared").path))
        #expect(file.installedCommands().count == ClaudeHooks.events.count)
    }

    /// The copy is always the file as it was before PhoneBox touched it.
    @Test func theBackupIsTheFileFromBeforePhoneBox() throws {
        defer { cleanUp() }
        try write(Self.userFile, to: settings)
        try file.install(executable: Self.executable)
        // Installed again for a PhoneBox that moved: the copy is still the user's own file.
        try file.install(executable: "/Users/me/Applications/PhoneBox.app/Contents/MacOS/PhoneBox")
        #expect(FileManager.default.contents(atPath: backup.path) == Data(Self.userFile.utf8))
        // Removing keeps no copy.
        try FileManager.default.removeItem(at: backup)
        #expect(try file.remove())
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    /// At launch with the feature on (design §14 "Kurulum"); the decision itself is `ClaudeHooks.launchCheck`.
    @Test func theLaunchCheckReadsTheFile() throws {
        defer { cleanUp() }
        let app = folder.appendingPathComponent("A/PhoneBox.app/Contents/MacOS/PhoneBox")
        let copy = folder.appendingPathComponent("B/PhoneBox.app/Contents/MacOS/PhoneBox")
        for executable in [app, copy] { try write("#!/bin/sh\n", to: executable, mode: 0o755) }
        // No file: the user took the hooks out.
        #expect(file.launchCheck(executable: app.path) == .removed)
        try file.install(executable: app.path)
        #expect(file.launchCheck(executable: app.path) == .current)
        #expect(file.launchCheck(executable: copy.path) == .otherCopy)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("A"))
        #expect(file.launchCheck(executable: copy.path) == .reinstall)
        // A file PhoneBox cannot read, and a folder where the file should be.
        try write("{ not json", to: settings)
        #expect(file.launchCheck(executable: copy.path) == .unreadable)
        try FileManager.default.removeItem(at: settings)
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
        #expect(file.launchCheck(executable: copy.path) == .unreadable)
    }

    @Test func removeTakesOutOnlyPhoneBoxsHooks() throws {
        defer { cleanUp() }
        try write(Self.userFile, to: settings)
        try file.install(executable: Self.executable)
        #expect(try file.remove())
        #expect(try Self.object(FileManager.default.contents(atPath: settings.path)) == Self.object(Data(Self.userFile.utf8)))
        #expect(file.installedCommands() == [])
    }

    @Test func removeWithNothingToRemoveLeavesTheFileAlone() throws {
        defer { cleanUp() }
        #expect(try !file.remove())
        #expect(!FileManager.default.fileExists(atPath: settings.path))
        try write(Self.userFile, to: settings)
        #expect(try !file.remove())
        #expect(FileManager.default.contents(atPath: settings.path) == Data(Self.userFile.utf8))
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        // Nor does a file PhoneBox cannot read have any of its hooks.
        try write("{ not json", to: settings)
        #expect(try !file.remove())
    }

    @Test func refusesAFileItDoesNotUnderstandAndLeavesItAsItWas() throws {
        defer { cleanUp() }
        for (text, expected) in [("{ not json", ClaudeHooks.Failure.notJSON), ("[]", .notAnObject),
                                 (#"{"hooks":{"Stop":{}}}"#, .eventNotAnArray("Stop"))] {
            try write(text, to: settings)
            do {
                try file.install(executable: Self.executable)
                Issue.record("installed into \(text)")
            } catch let ClaudeHooksFile.Failure.hooks(failure) {
                #expect(failure == expected)
            }
            #expect(FileManager.default.contents(atPath: settings.path) == Data(text.utf8))
            #expect(!FileManager.default.fileExists(atPath: backup.path))
        }
    }

    @Test func aFileErrorIsReported() throws {
        defer { cleanUp() }
        // A folder where the file should be.
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
        do {
            try file.install(executable: Self.executable)
            Issue.record("installed into a folder")
        } catch ClaudeHooksFile.Failure.file {
        }
    }
}
