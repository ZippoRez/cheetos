import XCTest
import AppKit
@testable import Cheetos

final class CommandLibraryTests: XCTestCase {
    @MainActor
    func testSearchFavoritesAndReloadKeepCommandIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "CheetosTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let linux = directory.appendingPathComponent("test-linux.md")
        let ydb = directory.appendingPathComponent("test-ydb.md")
        try "# Linux\n- `lsblk` — Диски и разделы\n- `df -h` — Свободное место\n".write(to: linux, atomically: true, encoding: .utf8)
        try "# YDB\n- `dstool device list` — Диски кластера\n".write(to: ydb, atomically: true, encoding: .utf8)
        let library = CheatSheetLibrary(defaults: defaults, userDirectory: directory, watch: false)
        let matches = library.matchingCommands(query: "ДИСКИ").filter { $0.sheetID.hasPrefix("test-") }
        XCTAssertEqual(Set(matches.map(\.sheetID)), ["test-linux", "test-ydb"])
        XCTAssertEqual(library.matchingCommands(query: "linux диски").map(\.key), ["lsblk"])
        XCTAssertEqual(library.matchingCommands(query: "dstool клаСТЕРА").map(\.key), ["dstool device list"])
        XCTAssertTrue(library.matchingCommands(query: "несуществующая команда").isEmpty)
        let command = try XCTUnwrap(matches.first { $0.key == "lsblk" })
        library.toggleFavorite(command)
        let reloaded = CheatSheetLibrary(defaults: defaults, userDirectory: directory, watch: false)
        XCTAssertEqual(reloaded.matchingCommands(query: "", favoritesOnly: true).map(\.key), ["lsblk"])
        try "# Linux\n- `lsblk` — Новый текст\n".write(to: linux, atomically: true, encoding: .utf8)
        reloaded.load()
        XCTAssertEqual(reloaded.matchingCommands(query: "новый", favoritesOnly: true).map(\.key), ["lsblk"])
        reloaded.setHidden(command.sheetID, hidden: true)
        XCTAssertTrue(reloaded.matchingCommands(query: "", favoritesOnly: true).isEmpty)
        reloaded.setHidden(command.sheetID, hidden: false)
        reloaded.toggleFavorite(command)
        XCTAssertTrue(reloaded.matchingCommands(query: "", favoritesOnly: true).isEmpty)
    }

    @MainActor
    func testEditingBundledSheetPreservesExistingCustomCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CheatSheetLibrary(userDirectory: directory, watch: false)
        let bundled = CheatSheet(id: "edit-test", title: "Test", url: directory.appendingPathComponent("bundle.md"),
                                 isUserProvided: false, content: "original")
        let url = try library.editableURL(for: bundled)
        XCTAssertEqual(url, directory.appendingPathComponent("edit-test.md"))
        XCTAssertEqual(try String(contentsOf: url), "original")
        try "custom".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try library.editableURL(for: bundled), url)
        XCTAssertEqual(try String(contentsOf: url), "custom")
        let custom = CheatSheet.load(id: "edit-test", title: "Test", url: url, isUserProvided: true)
        XCTAssertEqual(try library.editableURL(for: custom), url)
    }

    func testResultSelectionClampsAndSurvivesFiltering() {
        XCTAssertNil(CommandSelection.moved(in: [], current: "a", by: 1))
        XCTAssertEqual(CommandSelection.moved(in: ["a", "b"], current: "a", by: 1), "b")
        XCTAssertEqual(CommandSelection.moved(in: ["a", "b"], current: "b", by: 1), "b")
        XCTAssertEqual(CommandSelection.moved(in: ["a", "b"], current: "a", by: -1), "a")
        XCTAssertEqual(CommandSelection.moved(in: ["b"], current: "a", by: -1), "b")
    }

    func testResultKeysPreserveSearchEditingAndModifiedArrows() {
        XCTAssertEqual(CommandResultAction.resolve(keyCode: 125, modifiers: []), .move(1))
        XCTAssertEqual(CommandResultAction.resolve(keyCode: 126, modifiers: []), .move(-1))
        XCTAssertEqual(CommandResultAction.resolve(keyCode: 36, modifiers: []), .copy)
        XCTAssertEqual(CommandResultAction.resolve(keyCode: 76, modifiers: []), .copy)
        XCTAssertEqual(CommandResultAction.resolve(keyCode: 48, modifiers: []), .open)
        XCTAssertNil(CommandResultAction.resolve(keyCode: 48, modifiers: .shift))
        XCTAssertNil(CommandResultAction.resolve(keyCode: 125, modifiers: .command))
        XCTAssertNil(CommandResultAction.resolve(keyCode: 126, modifiers: .option))
        XCTAssertNil(CommandResultAction.resolve(keyCode: 38, modifiers: [])) // j stays text
        XCTAssertNil(CommandResultAction.resolve(keyCode: 40, modifiers: [])) // k stays text
    }
}
